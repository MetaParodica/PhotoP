import XCTest
@testable import PhotoP

final class LongExposureArchiveTests: XCTestCase {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func image(_ value: UInt8) -> SDRImage { SDRImage(rgba: Data([value, value, value, 255]), width: 1, height: 1) }
    func testLosslessArchiveAndReprocessingReproducePixels() async throws {
        let root = try folder(), a = image(40), b = image(200)
        let archive = try LongExposureArchive(root: root)
        XCTAssertTrue(try archive.append(a)); XCTAssertTrue(try archive.append(b))
        var stack = try LongExposureStack(first: a, configuration: .init()); try stack.add(b)
        let output = try archive.finish(stack: stack, elapsed: 2, reason: "duration")
        let restored = try await LongExposureArchive.reprocess(output, configuration: .init())
        XCTAssertNotEqual(output, restored)
        XCTAssertEqual(try Data(contentsOf: output), try Data(contentsOf: restored))
        XCTAssertEqual(try SDRImage.decode(output.deletingLastPathComponent().appendingPathComponent("000000.png")).rgba, a.rgba)
    }
    func testCancellationRemovesPendingFiles() throws {
        let root = try folder(), archive = try LongExposureArchive(root: root)
        _ = try archive.append(image(90)); archive.cancel(); archive.cancel()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }
    func testReprocessingRejectsTamperedFrames() async throws {
        let root = try folder(), archive = try LongExposureArchive(root: root), a = image(60)
        _ = try archive.append(a); _ = try archive.append(a)
        var stack = try LongExposureStack(first: a, configuration: .init()); try stack.add(a)
        let output = try archive.finish(stack: stack, elapsed: 2, reason: "duration")
        try Data([1]).write(to: output.deletingLastPathComponent().appendingPathComponent("000000.png"))
        do { _ = try await LongExposureArchive.reprocess(output, configuration: .init()); XCTFail("Expected hash rejection") } catch {}
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".pending") })
    }
    func testStoppedCameraRejectsLongExposureAndCancelIsIdempotent() async {
        let service = CameraService { _ in }
        do { _ = try await service.captureLongExposure(.init()) { _ in }; XCTFail("Expected stopped session") }
        catch { guard case CameraError.interrupted = error else { return XCTFail("Unexpected: \(error)") } }
        service.cancelLongExposure(); service.cancelLongExposure()
    }
    func testCaptureCancellationCompletesOnceAndRemovesArchive() async throws {
        let root = try folder(), archive = try LongExposureArchive(root: root)
        let done = expectation(description: "cancel completes once")
        done.assertForOverFulfill = true
        let job = try LongExposureCapture(configuration: .init(), archive: archive, onProgress: { _ in }) { result in
            if case .success = result { XCTFail("Cancelled job cannot succeed") }
            done.fulfill()
        }
        job.start(); job.cancel(); job.cancel()
        await fulfillment(of: [done], timeout: 2)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }

}
