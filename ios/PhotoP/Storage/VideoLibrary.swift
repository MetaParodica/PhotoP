import Foundation

struct StoredVideo: Identifiable, Sendable {
    var id: URL { url }
    let url: URL
    let manifest: VideoManifest
    let createdAt: Date
}

struct PendingVideo: Identifiable, Sendable {
    var id: URL { url }
    let url: URL
    let bytes: Int64
}

struct VideoLibrarySnapshot: Sendable {
    var videos: [StoredVideo] = []
    var pending: [PendingVideo] = []
    var rejectedCount = 0
}

extension VideoStore {
    static func library(in folder: URL) throws -> VideoLibrarySnapshot {
        let fm = FileManager.default
        guard fm.fileExists(atPath: folder.path) else { return VideoLibrarySnapshot() }
        var result = VideoLibrarySnapshot()
        for job in try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
            if job.lastPathComponent == "Pending" { continue }
            do {
                guard UUID(uuidString: job.lastPathComponent) != nil,
                      try job.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]).isDirectory == true,
                      try job.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw CameraError.invalidPhotoData }
                let original = job.appendingPathComponent("Original.mov")
                let manifestURL = job.appendingPathComponent("manifest.json")
                let manifestSize = try regularFileSize(manifestURL)
                guard manifestSize > 0, manifestSize <= 64 * 1024 else { throw CameraError.invalidPhotoData }
                let manifest = try JSONDecoder().decode(VideoManifest.self, from: Data(contentsOf: manifestURL))
                guard VideoStore.acceptsManifest(manifest), manifest.originalFile == "Original.mov", !manifest.lutBaked,
                      manifest.sha256.count == 64, manifest.sha256.allSatisfy({ "0123456789abcdef".contains($0) }),
                      manifest.bytes > 0, try regularFileSize(original) == manifest.bytes,
                      matches(manifest.actual, configuration: manifest.configuration) else { throw CameraError.invalidPhotoData }
                let date = try original.resourceValues(forKeys: [.creationDateKey]).creationDate ?? .distantPast
                result.videos.append(StoredVideo(url: original, manifest: manifest, createdAt: date))
            } catch { result.rejectedCount += 1 }
        }
        let pendingFolder = folder.appendingPathComponent("Pending", isDirectory: true)
        if fm.fileExists(atPath: pendingFolder.path) {
            guard try pendingFolder.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw CameraError.invalidPhotoData }
            for url in try fm.contentsOfDirectory(at: pendingFolder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) {
                do {
                    try validatePendingPath(url, root: folder)
                    result.pending.append(PendingVideo(url: url, bytes: try regularFileSize(url)))
                } catch { result.rejectedCount += 1 }
            }
        }
        result.videos.sort { $0.createdAt > $1.createdAt }
        result.pending.sort { $0.url.lastPathComponent < $1.url.lastPathComponent }
        return result
    }

    static func verify(_ stored: StoredVideo) async throws -> VideoOriginal {
        // Reopen the manifest and validate the path/size again; list-time values are not trusted.
        let root = stored.url.deletingLastPathComponent().deletingLastPathComponent()
        let current = try await Task.detached(priority: .utility) { try library(in: root) }.value
        guard let item = current.videos.first(where: { $0.url == stored.url }) else { throw CameraError.invalidPhotoData }
        let digest = try await Task.detached(priority: .utility) { try hashFile(item.url) }.value
        guard digest.sha256 == item.manifest.sha256, digest.bytes == item.manifest.bytes else {
            throw ImageEditingError.invalid("영상 원본 해시가 기록과 다릅니다. 파일을 변경하거나 삭제하지 않았습니다.")
        }
        let info = try await inspect(item.url)
        guard info == item.manifest.actual else { throw CameraError.invalidPhotoData }
        return VideoOriginal(url: item.url, info: info)
    }

    static func recover(_ pending: URL, in folder: URL) async throws -> VideoOriginal {
        try validatePendingPath(pending, root: folder)
        guard try regularFileSize(pending) > 0 else { throw CameraError.invalidPhotoData }
        let info = try await inspect(pending)
        guard hasKnownSDRTransfer(info) else { throw ImageEditingError.invalid("파일의 SDR 전달 함수를 확인하지 못해 자동 복구하지 않았습니다. 원본은 유지합니다.") }
        guard let resolution = VideoResolution.allCases.first(where: {
            $0.longEdge == max(info.encodedWidth, info.encodedHeight) && $0.shortEdge == min(info.encodedWidth, info.encodedHeight)
        }), let fps = [24, 25, 30, 50, 60].first(where: { abs(Double($0) - Double(info.nominalFrameRate)) < 0.1 }),
              info.audioTrackCount <= 1 else {
            throw ImageEditingError.invalid("지원 범위의 완성된 SDR MOV(오디오 트랙 0~1개)만 복구할 수 있습니다. 원본 파일은 유지합니다.")
        }
        // The stabilization request is not stored in the file, so it is recorded as unknown.
        return try await finalize(pending, configuration: .init(resolution: resolution, framesPerSecond: fps, codec: info.codec,
                                                                audio: info.audioTrackCount == 1, stabilization: nil),
                                  in: folder, recovered: true)
    }

    static func acceptsManifest(_ manifest: VideoManifest) -> Bool {
        switch manifest.version {
        case 1: return !manifest.audioRequested && !manifest.configuration.audio
        case 2: return manifest.audioRequested == manifest.configuration.audio
        default: return false
        }
    }

    private static func validatePendingPath(_ url: URL, root: URL) throws {
        let expected = root.appendingPathComponent("Pending", isDirectory: true).standardizedFileURL
        guard url.deletingLastPathComponent().standardizedFileURL == expected, url.pathExtension == "mov",
              UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil,
              try expected.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw CameraError.invalidPhotoData }
    }

    private static func regularFileSize(_ url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize else { throw CameraError.invalidPhotoData }
        return Int64(size)
    }
}
