@preconcurrency import AVFoundation
@preconcurrency import CoreImage
import Foundation

struct VideoDepthRecipe: Codable, Sendable {
    var version = 1
    let originalSHA256: String
    let resultSHA256: String
    let resultBytes: Int64
    let intent: VideoDepthIntent
    let original: VideoFileInfo
    let result: VideoFileInfo
    let frames: Int
    let processedFrames: Int
    let fallbackFrames: Int
    let aiProcessing: String
    var temporalRegisteredFrames: Int? = nil
    var temporalRejectedHistoryFrames: Int? = nil
}
struct VideoDepthResult: Identifiable, Sendable {
    let id: UUID
    let url: URL
    let recipe: VideoDepthRecipe
}

// One job, no retained frame history. Actor reentrancy is guarded explicitly.
// Original encoded bytes are never rewritten. Cancellation removes only our pending folder.
actor VideoDepthProcessor {
    static let shared = VideoDepthProcessor()
    private var active = false
    typealias FrameRenderer = @Sendable (CIImage, VideoDepthKeyframe, VideoDepthQuality) throws -> CIImage?

    func render(_ original: VideoOriginal, intent: VideoDepthIntent, destination: URL? = nil,
                progress: @escaping @Sendable (Double) -> Void = { _ in },
                frameRenderer: FrameRenderer? = nil) async throws -> VideoDepthResult {
        guard !active else { throw ImageEditingError.invalid("다른 심도 영상을 처리 중입니다. 완료 후 다시 시도하세요.") }
        active = true; defer { active = false }
        guard intent.valid else { throw ImageEditingError.invalid("심도 시간 설정이 올바르지 않습니다.") }
        let info = try await VideoStore.inspect(original.url)
        guard info == original.info, VideoStore.hasKnownSDRTransfer(info), info.audioTrackCount <= 1,
              VideoDepthPolicy.supports(width: info.displayWidth, height: info.displayHeight, fps: Double(info.nominalFrameRate), duration: info.durationSeconds) else {
            throw ImageEditingError.invalid("심도 영상은 SDR H.264/HEVC · 최대 4K/60fps · 10분까지 지원합니다.")
        }
        let hashBefore = try VideoStore.hashFile(original.url)
        let root = try destination ?? VideoDepthStore.root()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let id = UUID(), pending = root.appendingPathComponent(".pending-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: pending, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: pending) }
        let output = pending.appendingPathComponent("Depth.mov")
        let asset = AVURLAsset(url: original.url)
        guard let video = try await asset.loadTracks(withMediaType: .video).first else { throw CameraError.invalidPhotoData }
        let audio = try await asset.loadTracks(withMediaType: .audio).first
        let transform = try await video.load(.preferredTransform)
        guard let values = VideoDepthPolicy.coreImageTransform(a: transform.a,b: transform.b,c: transform.c,d: transform.d,
            tx: transform.tx,ty: transform.ty,inputHeight: Double(info.encodedHeight),outputHeight: Double(info.displayHeight)) else { throw CameraError.invalidPhotoData }
        let upright = CGAffineTransform(a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5])
        let canvas = CGRect(x: 0, y: 0, width: info.encodedWidth, height: info.encodedHeight).applying(upright)
        guard abs(canvas.minX) < 1, abs(canvas.minY) < 1, abs(canvas.width - Double(info.displayWidth)) < 1,
              abs(canvas.height - Double(info.displayHeight)) < 1 else { throw CameraError.invalidPhotoData }
        let reader = try AVAssetReader(asset: asset)
        let videoOutput = AVAssetReaderTrackOutput(track: video, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else { throw CameraError.invalidPhotoData }; reader.add(videoOutput)
        let writer = try AVAssetWriter(outputURL: output, fileType: .mov)
        let rate = try await video.load(.estimatedDataRate)
        guard let bitrate = VideoDepthPolicy.bitrate(width: info.displayWidth, height: info.displayHeight, fps: Double(info.nominalFrameRate), original: Double(rate), hevc: info.codec == .hevc) else { throw CameraError.invalidPhotoData }
        let settings: [String: Any] = [AVVideoCodecKey: info.codec == .hevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: info.displayWidth, AVVideoHeightKey: info.displayHeight,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitrate],
            AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2, AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2]]
        guard writer.canApply(outputSettings: settings, forMediaType: .video) else { throw CameraError.invalidPhotoData }
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        videoInput.expectsMediaDataInRealTime = false
        videoInput.mediaTimeScale = try await video.load(.naturalTimeScale)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: info.displayWidth, kCVPixelBufferHeightKey as String: info.displayHeight,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]])
        guard writer.canAdd(videoInput) else { throw CameraError.invalidPhotoData }; writer.add(videoInput)
        var audioOutput: AVAssetReaderTrackOutput?, audioInput: AVAssetWriterInput?
        if let audio {
            let descriptions = try await audio.load(.formatDescriptions)
            guard let format = descriptions.first else { throw CameraError.invalidPhotoData }
            let out = AVAssetReaderTrackOutput(track: audio, outputSettings: nil)
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: format)
            input.expectsMediaDataInRealTime = false
            guard reader.canAdd(out), writer.canAdd(input) else { throw CameraError.invalidPhotoData }
            reader.add(out); writer.add(input); audioOutput = out; audioInput = input
        }
        let description = AVMutableMetadataItem()
        description.identifier = .commonIdentifierDescription
        description.value = "PhotoP AI depth · Depth Anything V2 Small + selected-subject matte · SDR derivative · location removed" as NSString
        writer.metadata = [description] // Whitelist: never copy source GPS/device metadata.
        var completed = false
        defer {
            if !completed {
                if reader.status == .reading { reader.cancelReading() }
                if writer.status == .writing { writer.cancelWriting() }
            }
        }
        guard writer.startWriting(), reader.startReading() else { throw writer.error ?? reader.error ?? CameraError.invalidPhotoData }
        writer.startSession(atSourceTime: .zero)
        let context = CIContext(options: [.cacheIntermediates: false, .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!])
        let outputSpace = CGColorSpace(name: CGColorSpace.itur_709)!
        let estimator = ExternalDepthEstimator(), matte = DepthMatteRefiner(), engine = NaturalDepthEngine()
        let tracker = SubjectTrackingVisionEngine()
        let stabilizer = VideoDepthStabilizer()
        var previousSelection: UUID?
        var videoSample = videoOutput.copyNextSampleBuffer(), audioSample = audioOutput?.copyNextSampleBuffer()
        var frames = 0, applied = 0, fallback = 0
        var lastPTS = -Double.infinity
        while videoSample != nil || audioSample != nil {
            try Task.checkCancellation()
            if let sample = audioSample, videoSample == nil || CMTimeCompare(CMSampleBufferGetPresentationTimeStamp(sample), CMSampleBufferGetPresentationTimeStamp(videoSample!)) <= 0 {
                guard let audioInput else { throw CameraError.invalidPhotoData }
                try await Self.ready(audioInput, writer: writer)
                guard audioInput.append(sample) else { throw writer.error ?? CameraError.invalidPhotoData }
                audioSample = audioOutput?.copyNextSampleBuffer()
                continue
            }
            guard let sample = videoSample, let buffer = CMSampleBufferGetImageBuffer(sample) else { throw CameraError.invalidPhotoData }
            let pts = CMSampleBufferGetPresentationTimeStamp(sample), seconds = pts.seconds
            guard seconds.isFinite, seconds >= 0, seconds > lastPTS, let parameters = intent.parameters(at: seconds) else { throw CameraError.invalidPhotoData }
            lastPTS = seconds
            try await Self.ready(videoInput, writer: writer)
            guard let pool = adaptor.pixelBufferPool else { throw CameraError.invalidPhotoData }
            var renderedBuffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &renderedBuffer) == kCVReturnSuccess, let renderedBuffer else { throw CameraError.invalidPhotoData }
            let didApply: Bool = try autoreleasepool {
                let space = try LivePreviewImageProcessor.inputColorSpace(buffer, negotiatedSRGB: true)
                let image = CIImage(cvPixelBuffer: buffer, options: [.colorSpace: space]).transformed(by: upright)
                    .cropped(to: CGRect(x: 0, y: 0, width: info.displayWidth, height: info.displayHeight))
                let result: CIImage?
                if let frameRenderer { result = try frameRenderer(image, parameters, intent.quality) }
                else {
                    var focus = parameters.focus
                    var trusted = !parameters.requiresTracking || parameters.selection != nil
                    if let selection = parameters.selection {
                        // This synchronous batch runs off the capture/render queue.
                        let tracked = try OnDeviceInferenceGate.lock.withLock { try tracker.update(image, selection: selection, time: seconds) }
                        if let target = tracked.focus(at: seconds) { focus = target } else { trusted = false }
                    }
                    if trusted {
                        do {
                            let estimate = try estimator.estimate(image)
                            if previousSelection != parameters.selection?.id { stabilizer.reset() }
                            previousSelection = parameters.selection?.id
                            let field = try stabilizer.update(image: image, field: estimate, time: seconds)
                            let transition = intent.focusTransition(at: seconds)
                            let focusInverse = transition?.inverse(in: field)
                            guard transition == nil || focusInverse != nil else { throw CameraError.invalidPhotoData }
                            let refined = try? matte.refine(color: image, focus: focus, embedded: nil, maximumDimension: 256)
                            result = try engine.renderField(color: image, field: field, aperture: parameters.aperture, focus: focus,
                                profile: parameters.profile, matte: refined, source: "video-ai", qualityPairs: intent.quality.pairs, focusInverseOverride: focusInverse).image
                        } catch is CancellationError { throw CancellationError() }
                        catch { stabilizer.reset(); result = nil } // Invalid/flat field: retain original frame, count and disclose.
                    } else { stabilizer.reset(); result = nil }
                }
                context.render(result ?? image, to: renderedBuffer, bounds: CGRect(x: 0, y: 0, width: info.displayWidth, height: info.displayHeight), colorSpace: outputSpace)
                return result != nil
            }
            guard adaptor.append(renderedBuffer, withPresentationTime: pts) else { throw writer.error ?? CameraError.invalidPhotoData }
            frames += 1; if didApply { applied += 1 } else { fallback += 1 }
            progress(min(0.98, seconds / info.durationSeconds))
            videoSample = videoOutput.copyNextSampleBuffer()
        }
        guard reader.status == .completed, frames > 0, applied > 0 else { throw reader.error ?? ImageEditingError.invalid("심도를 적용할 유효한 프레임이 없습니다. 원본은 보존했습니다. 대상을 다시 선택하세요.") }
        videoInput.markAsFinished(); audioInput?.markAsFinished()
        writer.endSession(atSourceTime: try await asset.load(.duration))
        await writer.finishWriting()
        try Task.checkCancellation()
        guard writer.status == .completed else { throw writer.error ?? CameraError.invalidPhotoData }
        let actual = try await VideoStore.inspect(output)
        guard actual.displayWidth == info.displayWidth, actual.displayHeight == info.displayHeight,
            actual.audioTrackCount == info.audioTrackCount, abs(actual.durationSeconds - info.durationSeconds) < max(0.1, 2 / Double(info.nominalFrameRate)) else { throw CameraError.invalidPhotoData }
        let hashAfter = try VideoStore.hashFile(original.url)
        guard hashBefore == hashAfter else { throw ImageEditingError.invalid("처리 중 원본이 변경되어 결과를 게시하지 않았습니다.") }
        let digest = try VideoStore.hashFile(output)
        var recipe = VideoDepthRecipe(originalSHA256: hashBefore.sha256, resultSHA256: digest.sha256, resultBytes: digest.bytes,
            intent: intent, original: info, result: actual, frames: frames, processedFrames: applied, fallbackFrames: fallback,
            aiProcessing: "Depth Anything V2 Small / NaturalDepthEngine / Vision selected-target tracking")
        recipe.temporalRegisteredFrames = stabilizer.registeredFrames
        recipe.temporalRejectedHistoryFrames = stabilizer.rejectedHistoryFrames
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(recipe).write(to: pending.appendingPathComponent("recipe.json"), options: .atomic)
        let final = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: pending, to: final)
        completed = true; progress(1)
        return .init(id: id, url: final.appendingPathComponent("Depth.mov"), recipe: recipe)
    }
    private static func ready(_ input: AVAssetWriterInput, writer: AVAssetWriter) async throws {
        let start = ProcessInfo.processInfo.systemUptime
        while !input.isReadyForMoreMediaData {
            try Task.checkCancellation()
            guard writer.status == .writing, ProcessInfo.processInfo.systemUptime - start < 30 else { throw writer.error ?? ImageEditingError.invalid("영상 출력 대기 시간이 초과되었습니다.") }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
    }
}

enum VideoDepthStore {
    static func root() throws -> URL {
        try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("VideoDepthResults", isDirectory: true)
    }
    static func library(in root: URL? = nil) throws -> [VideoDepthResult] {
        let folder = try root ?? self.root()
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey]).compactMap { directory in
            guard let id = UUID(uuidString: directory.lastPathComponent), (try? directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false else { return nil }
            let file = directory.appendingPathComponent("Depth.mov"), manifest = directory.appendingPathComponent("recipe.json")
            guard (try? file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false,
                  (try? manifest.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false,
                  let size = try? manifest.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0, size < 2_000_000,
                  let data = try? Data(contentsOf: manifest), data.count == size,
                  let recipe = try? JSONDecoder().decode(VideoDepthRecipe.self, from: data), recipe.version == 1, recipe.intent.valid,
                  recipe.frames > 0, recipe.processedFrames > 0, recipe.fallbackFrames >= 0,
                  recipe.processedFrames + recipe.fallbackFrames == recipe.frames else { return nil }
            return .init(id: id, url: file, recipe: recipe)
        }
    }
    static func verify(_ result: VideoDepthResult) async throws {
        let digest = try VideoStore.hashFile(result.url)
        guard digest.sha256 == result.recipe.resultSHA256, digest.bytes == result.recipe.resultBytes,
              try await VideoStore.inspect(result.url) == result.recipe.result else { throw ImageEditingError.invalid("심도 영상 검증에 실패했습니다.") }
    }
}
