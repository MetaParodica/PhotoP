@preconcurrency import AVFoundation
import CryptoKit
import Foundation
import Photos

struct VideoFileInfo: Codable, Equatable, Sendable {
    let durationSeconds: Double
    let encodedWidth: Int
    let encodedHeight: Int
    let displayWidth: Int
    let displayHeight: Int
    let nominalFrameRate: Float
    let codec: VideoCodec
    let audioTrackCount: Int
    let colorPrimaries: String?
    let transferFunction: String?
    let yCbCrMatrix: String?
}

struct VideoOriginal: Sendable {
    let url: URL
    let info: VideoFileInfo
}

struct VideoManifest: Codable, Sendable {
    var version = 1
    let configuration: VideoConfiguration
    let actual: VideoFileInfo
    let sha256: String
    let bytes: Int64
    let originalFile: String
    var lutBaked = false
    var audioRequested = false
    var recoveredFromPending: Bool?
}

enum VideoStore {
    static func root() throws -> URL {
        try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Videos", isDirectory: true)
    }

    static func newRecordingURL() throws -> URL {
        let pending = try root().appendingPathComponent("Pending", isDirectory: true)
        try FileManager.default.createDirectory(at: pending, withIntermediateDirectories: true)
        let free = try FileManager.default.attributesOfFileSystem(forPath: pending.path)[.systemFreeSize] as? NSNumber
        guard free?.int64Value ?? 0 > 64 * 1024 * 1024 else { throw ImageEditingError.invalid("녹화 시작에 최소 64MiB의 저장 공간이 필요합니다.") }
        return pending.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
    }

    static func inspect(_ url: URL) async throws -> VideoFileInfo {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        guard duration.isFinite, duration > 0, tracks.count == 1, let track = tracks.first else {
            throw ImageEditingError.invalid("유효한 영상 트랙·재생 길이를 확인하지 못했습니다. 녹화 파일은 Pending에 보관합니다.")
        }
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let display = size.applying(transform)
        let fps = try await track.load(.nominalFrameRate)
        let descriptions = try await track.load(.formatDescriptions)
        guard let description = descriptions.first, fps.isFinite, fps > 0 else { throw CameraError.invalidPhotoData }
        let dimensions = CMVideoFormatDescriptionGetDimensions(description)
        let codec: VideoCodec
        switch CMFormatDescriptionGetMediaSubType(description) {
        case kCMVideoCodecType_H264: codec = .h264
        case kCMVideoCodecType_HEVC: codec = .hevc
        default: throw ImageEditingError.invalid("현재 지원하지 않는 영상 코덱입니다.")
        }
        func tag(_ key: CFString) -> String? { CMFormatDescriptionGetExtension(description, extensionKey: key) as? String }
        let transfer = tag(kCMFormatDescriptionExtension_TransferFunction)
        guard transfer != (kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String),
              transfer != (kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String),
              dimensions.width > 0, dimensions.height > 0 else { throw CameraError.invalidPhotoData }
        return VideoFileInfo(durationSeconds: duration, encodedWidth: Int(dimensions.width), encodedHeight: Int(dimensions.height),
                             displayWidth: Int(abs(display.width).rounded()), displayHeight: Int(abs(display.height).rounded()),
                             nominalFrameRate: fps, codec: codec, audioTrackCount: audio.count,
                             colorPrimaries: tag(kCMFormatDescriptionExtension_ColorPrimaries), transferFunction: transfer,
                             yCbCrMatrix: tag(kCMFormatDescriptionExtension_YCbCrMatrix))
    }

    static func finalize(_ pending: URL, configuration: VideoConfiguration, in folder: URL? = nil, recovered: Bool = false) async throws -> VideoOriginal {
        let info = try await inspect(pending)
        guard matches(info, configuration: configuration) else { throw CameraError.invalidPhotoData }
        let destination = try folder ?? root()
        return try await Task.detached(priority: .utility) {
            let fm = FileManager.default
            let job = destination.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try fm.createDirectory(at: job, withIntermediateDirectories: true)
            let original = job.appendingPathComponent("Original.mov")
            let manifestURL = job.appendingPathComponent("manifest.json")
            do {
                // Stream hashing instead of loading a potentially 2GiB movie into RAM.
                let (digest, bytes) = try hashFile(pending)
                let manifest = VideoManifest(configuration: configuration, actual: info, sha256: digest, bytes: bytes, originalFile: "Original.mov",
                                             recoveredFromPending: recovered ? true : nil)
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(manifest).write(to: manifestURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                // Same-volume move preserves exact encoded bytes and never re-encodes the movie.
                try fm.moveItem(at: pending, to: original)
                return VideoOriginal(url: original, info: info)
            } catch {
                try? fm.removeItem(at: job)
                throw error
            }
        }.value
    }

    static func matches(_ info: VideoFileInfo, configuration: VideoConfiguration) -> Bool {
        info.durationSeconds.isFinite && info.durationSeconds > 0 && info.displayWidth > 0 && info.displayHeight > 0
            && info.codec == configuration.codec && info.audioTrackCount == 0
            && max(info.encodedWidth, info.encodedHeight) == configuration.resolution.longEdge
            && min(info.encodedWidth, info.encodedHeight) == configuration.resolution.shortEdge
            && abs(Double(info.nominalFrameRate) - Double(configuration.framesPerSecond)) < 1
    }

    static func hasKnownSDRTransfer(_ info: VideoFileInfo) -> Bool {
        info.transferFunction == (kCMFormatDescriptionTransferFunction_ITU_R_709_2 as String)
            || info.transferFunction == (kCVImageBufferTransferFunction_sRGB as String)
    }

    static func hashFile(_ url: URL) throws -> (sha256: String, bytes: Int64) {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256(); var bytes: Int64 = 0
        while let block = try file.read(upToCount: 1024 * 1024), !block.isEmpty {
            hash.update(data: block); bytes += Int64(block.count)
        }
        return (hash.finalize().map { String(format: "%02x", $0) }.joined(), bytes)
    }

    static func addToPhotos(_ url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized else { throw ImageEditingError.invalid("영상 원본은 앱에 보관했습니다. 사진 접근을 허용하거나 파일 공유를 이용해 주세요.") }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions(); options.originalFilename = url.lastPathComponent
            request.addResource(with: .video, fileURL: url, options: options)
        }
    }
}
