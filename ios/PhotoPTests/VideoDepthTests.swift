@preconcurrency import AVFoundation
@preconcurrency import CoreImage
import XCTest
@testable import PhotoP

final class VideoDepthTests: XCTestCase {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private var intent: VideoDepthIntent { .init(keyframes: [.init(time: 0, focus: CGPoint(x: 0.5, y: 0.5), aperture: 1.4, profile: .natural)]) }
    func testRealMovieDerivativePreservesPTSSizeOriginalAndMetadata() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("source.mov"); try await movie(url, rotated: false)
        let original = VideoOriginal(url: url, info: try await VideoStore.inspect(url))
        let before = try VideoStore.hashFile(url)
        let result = try await VideoDepthProcessor().render(original, intent: intent, destination: root) { image, _, _ in
            image.applyingFilter("CIColorInvert")
        }
        try await VideoDepthStore.verify(result)
        XCTAssertEqual(try VideoStore.hashFile(url).sha256, before.sha256)
        XCTAssertEqual(result.recipe.frames, 6); XCTAssertEqual(result.recipe.processedFrames, 6)
        XCTAssertEqual(result.recipe.result.displayWidth, 320); XCTAssertEqual(result.recipe.result.displayHeight, 180)
        let sourceTimes = try await timestamps(url), resultTimes = try await timestamps(result.url)
        XCTAssertEqual(sourceTimes, resultTimes)
        let metadata = try await AVURLAsset(url: result.url).load(.metadata)
        var description = ""
        for item in metadata { if let value = try await item.load(.stringValue) { description += value } }
        XCTAssertTrue(description.contains("AI depth")); XCTAssertFalse(description.contains("37.123"))
        XCTAssertEqual(try VideoDepthStore.library(in: root).count, 1)
        let file = try FileHandle(forWritingTo: result.url); try file.seekToEnd(); try file.write(contentsOf: Data([1])); try file.close()
        do { try await VideoDepthStore.verify(result); XCTFail("tampered result accepted") } catch { }
    }
    func testRotationIsBakedIntoUprightPixels() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("source.mov"); try await movie(url, rotated: true)
        let result = try await VideoDepthProcessor().render(.init(url: url, info: try await VideoStore.inspect(url)), intent: intent, destination: root) { image, _, _ in image }
        XCTAssertEqual(result.recipe.result.encodedWidth, 180); XCTAssertEqual(result.recipe.result.encodedHeight, 320)
        let track = try await AVURLAsset(url: result.url).loadTracks(withMediaType: .video).first!
        let transform = try await track.load(.preferredTransform)
        XCTAssertEqual(transform, .identity)
    }
    func testAllUncertainFramesFailAndRemoveOnlyPending() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("source.mov"); try await movie(url, rotated: false)
        let bytes = try Data(contentsOf: url)
        do {
            _ = try await VideoDepthProcessor().render(.init(url: url, info: try await VideoStore.inspect(url)), intent: intent, destination: root) { _, _, _ in nil }
            XCTFail("empty effect accepted")
        } catch { }
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["source.mov"])
    }
    func testCancellationDoesNotPublishOrDeleteOriginal() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("source.mov"); try await movie(url, rotated: false)
        let original = VideoOriginal(url: url, info: try await VideoStore.inspect(url)), config = intent
        let task = Task { try await VideoDepthProcessor().render(original, intent: config, destination: root) { image, _, _ in image } }
        task.cancel()
        do { _ = try await task.value; XCTFail("cancelled task published") } catch is CancellationError { }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(try VideoDepthStore.library(in: root).isEmpty)
    }
    func testSharedPhotoRendererActuallyBlursMovieFrames() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("source.mov"); try await movie(url, rotated: false)
        let result = try await VideoDepthProcessor().render(.init(url: url, info: try await VideoStore.inspect(url)), intent: intent, destination: root) { image, parameters, quality in
            let field = SoftwareDepthField(width: 32, height: 18, inverseDepth: (0..<576).map { $0 % 32 < 12 ? Float(0.9) : Float(0.2) }, units: .relativeInverse)!
            return try NaturalDepthEngine().renderField(color: image, field: field, aperture: parameters.aperture, focus: parameters.focus,
                profile: parameters.profile, qualityPairs: quality.pairs).image
        }
        XCTAssertEqual(result.recipe.processedFrames, 6)
        let first = AVAssetImageGenerator(asset: AVURLAsset(url: url)), second = AVAssetImageGenerator(asset: AVURLAsset(url: result.url))
        let a = try first.copyCGImage(at: .zero, actualTime: nil), b = try second.copyCGImage(at: .zero, actualTime: nil)
        let originalPixels = try SDRImage.rasterize(a), processedPixels = try SDRImage.rasterize(b)
        XCTAssertNotEqual(originalPixels.rgba, processedPixels.rgba)
    }
    func testAudioPassthroughPreservesTrackAndSamples() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let silent = root.appendingPathComponent("silent.mov"); try await movie(silent, rotated: false)
        // Actual PCM WAV -> composition MOV, not a mocked audio-track count.
        let wave = root.appendingPathComponent("tone.wav")
        var data = Data()
        func word(_ value: UInt32, bytes: Int) { for index in 0..<bytes { data.append(UInt8((value >> (index * 8)) & 255)) } }
        let samples = 12_000
        data.append(Data("RIFF".utf8)); word(UInt32(36 + samples * 2), bytes: 4); data.append(Data("WAVEfmt ".utf8))
        word(16, bytes: 4); word(1, bytes: 2); word(1, bytes: 2); word(48_000, bytes: 4); word(96_000, bytes: 4)
        word(2, bytes: 2); word(16, bytes: 2); data.append(Data("data".utf8)); word(UInt32(samples * 2), bytes: 4)
        for index in 0..<samples { word(UInt32(UInt16(bitPattern: Int16(sin(Double(index) * 0.06) * 8000))), bytes: 2) }
        try data.write(to: wave)
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: silent), audioAsset = AVURLAsset(url: wave)
        let video = try await videoAsset.loadTracks(withMediaType: .video).first!
        let audio = try await audioAsset.loadTracks(withMediaType: .audio).first!
        let duration = try await videoAsset.load(.duration)
        let range = CMTimeRange(start: .zero, duration: duration)
        try composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!.insertTimeRange(range, of: video, at: .zero)
        try composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!.insertTimeRange(range, of: audio, at: .zero)
        let source = root.appendingPathComponent("audio.mov")
        let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough)!
        exporter.outputURL = source; exporter.outputFileType = .mov
        await exporter.export()
        guard exporter.status == .completed else { throw exporter.error ?? CameraError.invalidPhotoData }
        let original = VideoOriginal(url: source, info: try await VideoStore.inspect(source))
        XCTAssertEqual(original.info.audioTrackCount, 1)
        let result = try await VideoDepthProcessor().render(original, intent: intent, destination: root) { image, _, _ in image }
        XCTAssertEqual(result.recipe.result.audioTrackCount, 1)
        let sourceAudio = try await audioBytes(source), resultAudio = try await audioBytes(result.url)
        XCTAssertFalse(sourceAudio.isEmpty); XCTAssertEqual(sourceAudio, resultAudio)
    }
    private func audioBytes(_ url: URL) async throws -> Data {
        let asset = AVURLAsset(url: url)
        let reader = try AVAssetReader(asset: asset)
        let track = try await asset.loadTracks(withMediaType: .audio).first!
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output); reader.startReading()
        var result = Data()
        while let sample = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(sample) {
            let count = CMBlockBufferGetDataLength(block)
            var bytes = [UInt8](repeating: 0, count: count)
            XCTAssertEqual(CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count, destination: &bytes), kCMBlockBufferNoErr)
            result.append(contentsOf: bytes)
        }
        XCTAssertEqual(reader.status, .completed)
        return result
    }
    func testMissingRequiredTargetNeverSilentlyUsesCenterDepth() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("source.mov"); try await movie(url, rotated: false)
        var config = intent; config.keyframes[0].requiresTracking = true
        do {
            _ = try await VideoDepthProcessor().render(.init(url: url, info: try await VideoStore.inspect(url)), intent: config, destination: root)
            XCTFail("missing target applied center blur")
        } catch { XCTAssertTrue(error.localizedDescription.contains("원본")) }
        XCTAssertTrue(try VideoDepthStore.library(in: root).isEmpty)
    }
    func testVisionSequenceRunsOnRealPixelsAndReselectionUsesNewID() throws {
        let image = CIFilter(name: "CICheckerboardGenerator")!.outputImage!.cropped(to: CGRect(x: 0,y: 0,width: 320,height: 180))
        let engine = SubjectTrackingVisionEngine()
        let first = SubjectTrackingSelection(point: CGPoint(x: 0.5,y: 0.5))
        let result = try engine.update(image, selection: first, time: 1)
        XCTAssertEqual(result.selectionID, first.id); XCTAssertTrue(result.confidence.isFinite)
        let second = SubjectTrackingSelection(point: CGPoint(x: 0.3,y: 0.3))
        let next = try engine.update(image, selection: second, time: 1.1, generation: 2)
        XCTAssertEqual(next.selectionID, second.id); XCTAssertEqual(next.generation, 2)
    }
    private func timestamps(_ url: URL) async throws -> [Double] {
        let asset = AVURLAsset(url: url)
        let reader = try AVAssetReader(asset: asset)
        let track = try await asset.loadTracks(withMediaType: .video).first!
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(out); reader.startReading()
        var times: [Double] = []
        while let sample = out.copyNextSampleBuffer() { times.append(CMSampleBufferGetPresentationTimeStamp(sample).seconds) }
        return times
    }
    private func movie(_ url: URL, rotated: Bool) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 320, AVVideoHeightKey: 180,
            AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
            AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2, AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2]])
        if rotated { input.transform = CGAffineTransform(a: 0,b: 1,c: -1,d: 0,tx: 180,ty: 0) }
        let adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,kCVPixelBufferWidthKey as String: 320,kCVPixelBufferHeightKey as String: 180])
        writer.add(input)
        let location = AVMutableMetadataItem(); location.identifier = .quickTimeMetadataLocationISO6709; location.value = "+37.123+127.123/" as NSString
        writer.metadata = [location]
        guard writer.startWriting() else { throw CameraError.configuration }; writer.startSession(atSourceTime: .zero)
        let context = CIContext()
        let pattern = CIFilter(name: "CICheckerboardGenerator", parameters: ["inputWidth": 5,"inputSharpness": 1])!.outputImage!
        for index in 0..<6 {
            var attempts = 0
            while !input.isReadyForMoreMediaData { attempts += 1; guard attempts < 500 else { throw CameraError.captureTimedOut }; try await Task.sleep(nanoseconds: 2_000_000) }
            var buffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, adapter.pixelBufferPool!, &buffer) == kCVReturnSuccess, let buffer else { throw CameraError.invalidPhotoData }
            context.render(pattern, to: buffer, bounds: CGRect(x: 0,y: 0,width: 320,height: 180), colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
            // Deliberately irregular PTS; exporter must not replace them with index/fps.
            guard adapter.append(buffer, withPresentationTime: CMTime(value: Int64([0,2,5,7,10,12][index]), timescale: 60)) else { throw CameraError.invalidPhotoData }
        }
        input.markAsFinished(); await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CameraError.invalidPhotoData }
    }
}
