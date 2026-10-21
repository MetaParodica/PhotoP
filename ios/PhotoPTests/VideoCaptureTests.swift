import AVFoundation
import CryptoKit
import XCTest
@testable import PhotoP

final class VideoCaptureTests: XCTestCase {
    func testActiveFormatFPSFilteringRejectsUnsupportedAndHighSpeedRates() {
        XCTAssertEqual(VideoCapturePolicy.frameRates(in: [23.98...30]), [24, 25, 30])
        XCTAssertEqual(VideoCapturePolicy.frameRates(in: [50...60, 120...240]), [50, 60])
        XCTAssertTrue(VideoCapturePolicy.frameRates(in: []).isEmpty)
        XCTAssertEqual(VideoCapturePolicy.frameRates(in: [29.97...29.97]), [])
    }

    func testConfigurationMustMatchActivePresetCapabilities() throws {
        let caps = VideoCapabilities(resolutions: [.hd720, .hd1080], frameRates: [24, 30], codecs: [.h264])
        var configuration = VideoConfiguration()
        XCTAssertNoThrow(try VideoCapturePolicy.validate(configuration, capabilities: caps))
        configuration.resolution = .uhd4K
        XCTAssertThrowsError(try VideoCapturePolicy.validate(configuration, capabilities: caps))
        configuration.resolution = .hd1080; configuration.framesPerSecond = 60
        XCTAssertThrowsError(try VideoCapturePolicy.validate(configuration, capabilities: caps))
        configuration.framesPerSecond = 30; configuration.codec = .hevc
        XCTAssertThrowsError(try VideoCapturePolicy.validate(configuration, capabilities: caps))
    }

    func testVideoShutterCannotExceedFrameIntervalAnd180DegreeSuggestionIsClamped() throws {
        let limits = try VideoCapturePolicy.shutterLimit(sensor: (1.0 / 8000)...1, fps: 60)
        XCTAssertEqual(limits.upperBound, 1.0 / 60)
        XCTAssertEqual(VideoCapturePolicy.suggestedShutter(fps: 60, limits: limits), 1.0 / 120)
        XCTAssertEqual(VideoCapturePolicy.suggestedShutter(fps: 60, limits: (1.0 / 100)...(1.0 / 60)), 1.0 / 100)
        XCTAssertThrowsError(try VideoCapturePolicy.shutterLimit(sensor: 0.1...1, fps: 60))
        XCTAssertThrowsError(try VideoCapturePolicy.shutterLimit(sensor: 0.001...1, fps: 0))
    }

    func testStoppingBeforeStartAndStaleDelegateCallbacks() throws {
        let first = URL(fileURLWithPath: "/first.mov"), second = URL(fileURLWithPath: "/second.mov")
        var job = VideoRecordingLifecycle()
        XCTAssertFalse(job.requestStop())
        try job.begin(first)
        XCTAssertEqual(job.phase, .starting)
        XCTAssertThrowsError(try job.begin(second))
        XCTAssertFalse(job.requestStop())
        XCTAssertEqual(job.phase, .stopping)
        XCTAssertFalse(job.didStart(second)); XCTAssertFalse(job.finish(second))
        XCTAssertTrue(job.didStart(first))
        XCTAssertTrue(job.finish(first)); XCTAssertFalse(job.finish(first))
        try job.begin(second)
        XCTAssertFalse(job.didStart(first)); XCTAssertFalse(job.finish(first))
        XCTAssertFalse(job.didStart(second)); XCTAssertEqual(job.phase, .recording)
        XCTAssertTrue(job.requestStop()); XCTAssertFalse(job.requestStop())
        XCTAssertTrue(job.finish(second)); XCTAssertEqual(job.phase, .idle)
    }

    func testAutomaticLimitErrorCanStillYieldSuccessfullyFinishedFile() {
        XCTAssertTrue(VideoCapturePolicy.finishedSuccessfully(hasError: false, successfulFinishFlag: false))
        XCTAssertTrue(VideoCapturePolicy.finishedSuccessfully(hasError: true, successfulFinishFlag: true))
        XCTAssertFalse(VideoCapturePolicy.finishedSuccessfully(hasError: true, successfulFinishFlag: false))
    }

    func testMoviePreservationInspectsRealEncodedFileAndKeepsExactBytes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let pending = root.appendingPathComponent("pending.mov")
        try await makeMovie(pending)
        let bytes = try Data(contentsOf: pending)
        let info = try await VideoStore.inspect(pending)
        XCTAssertEqual(info.codec, .h264); XCTAssertEqual(info.audioTrackCount, 0)
        XCTAssertEqual(info.encodedWidth, 1280); XCTAssertEqual(info.encodedHeight, 720)
        XCTAssertGreaterThan(info.durationSeconds, 0)
        XCTAssertEqual(info.nominalFrameRate, 30, accuracy: 0.1)
        let configuration = VideoConfiguration(resolution: .hd720, framesPerSecond: 30, codec: .h264)
        let original = try await VideoStore.finalize(pending, configuration: configuration, in: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: pending.path))
        XCTAssertEqual(try Data(contentsOf: original.url), bytes)
        let manifest = try JSONDecoder().decode(VideoManifest.self, from: Data(contentsOf: original.url.deletingLastPathComponent().appendingPathComponent("manifest.json")))
        XCTAssertEqual(manifest.actual, info); XCTAssertEqual(manifest.configuration, configuration)
        XCTAssertEqual(manifest.bytes, Int64(bytes.count))
        XCTAssertEqual(manifest.sha256, SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
        XCTAssertFalse(manifest.lutBaked); XCTAssertFalse(manifest.audioRequested)
    }

    func testInvalidOrMismatchedMovieStaysPending() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let pending = root.appendingPathComponent("pending.mov")
        try Data("not a movie".utf8).write(to: pending)
        do { _ = try await VideoStore.finalize(pending, configuration: .init(), in: root); XCTFail("invalid movie accepted") }
        catch { XCTAssertTrue(FileManager.default.fileExists(atPath: pending.path)) }
        try FileManager.default.removeItem(at: pending)
        try await makeMovie(pending)
        do { _ = try await VideoStore.finalize(pending, configuration: .init(codec: .hevc), in: root); XCTFail("wrong codec accepted") }
        catch { XCTAssertTrue(FileManager.default.fileExists(atPath: pending.path)) }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["pending.mov"])
    }

    private func makeMovie(_ url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 1280, AVVideoHeightKey: 720,
            AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2, AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2]])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 1280, kCVPixelBufferHeightKey as String: 720])
        guard writer.canAdd(input) else { throw CameraError.configuration }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CameraError.configuration }
        writer.startSession(atSourceTime: .zero)
        for index in 0..<6 {
            var attempts = 0
            while !input.isReadyForMoreMediaData {
                attempts += 1
                guard attempts < 500 else { writer.cancelWriting(); throw CameraError.captureTimedOut }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            var buffer: CVPixelBuffer?
            guard let pool = adaptor.pixelBufferPool,
                  CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
                  let buffer else { throw CameraError.configuration }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) { memset(base, Int32(64 + index * 16), CVPixelBufferGetDataSize(buffer)) }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: 30)) else {
                throw writer.error ?? CameraError.invalidPhotoData
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CameraError.invalidPhotoData }
    }
}
