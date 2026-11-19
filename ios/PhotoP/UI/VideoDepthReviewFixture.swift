#if DEBUG && targetEnvironment(simulator)
@preconcurrency import AVFoundation
import SwiftUI

// A real SDR file, not simulated camera/AF/depth hardware capabilities.
@MainActor
struct VideoDepthReviewFixture: View {
    @State private var item: StoredVideo?
    @State private var failure: String?
    @State private var folder: URL?
    var body: some View {
        NavigationStack {
            if let item { VideoDepthEditorView(item: item) }
            else if let failure { Text(failure).accessibilityIdentifier("video.depth.fixture.failure") }
            else { ProgressView("검증용 영상 준비") }
        }.task {
            do {
                let root = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoP-VideoDepth-UI-" + UUID().uuidString)
                folder = root
                item = try await Task.detached(priority: .userInitiated) { try await Self.make(root) }.value
            } catch { failure = error.localizedDescription }
        }.onDisappear { if let folder { try? FileManager.default.removeItem(at: folder) } }
    }
    nonisolated private static func make(_ root: URL) async throws -> StoredVideo {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("fixture.mov")
        let writer = try AVAssetWriter(outputURL: source, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 1280, AVVideoHeightKey: 720,
            AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2, AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2]])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 1280, kCVPixelBufferHeightKey as String: 720])
        writer.add(input); guard writer.startWriting() else { throw CameraError.invalidPhotoData }; writer.startSession(atSourceTime: .zero)
        for index in 0..<6 {
            var attempts = 0
            while !input.isReadyForMoreMediaData { attempts += 1; guard attempts < 500 else { throw CameraError.captureTimedOut }; try await Task.sleep(nanoseconds: 2_000_000) }
            var pixel: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pixel) == kCVReturnSuccess, let pixel else { throw CameraError.invalidPhotoData }
            CVPixelBufferLockBaseAddress(pixel, [])
            if let base = CVPixelBufferGetBaseAddress(pixel) { memset(base, 100 + Int32(index * 10), CVPixelBufferGetDataSize(pixel)) }
            CVPixelBufferUnlockBaseAddress(pixel, [])
            guard adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(index), timescale: 30)) else { throw CameraError.invalidPhotoData }
        }
        input.markAsFinished(); await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CameraError.invalidPhotoData }
        _ = try await VideoStore.finalize(source, configuration: .init(resolution: .hd720), in: root)
        guard let item = try VideoStore.library(in: root).videos.first else { throw CameraError.invalidPhotoData }
        return item
    }
}
#endif
