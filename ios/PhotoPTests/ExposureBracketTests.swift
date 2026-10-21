import XCTest
import AVFoundation
@testable import PhotoP

final class ExposureBracketTests: XCTestCase {
    private func jpeg(_ value: UInt8) throws -> CapturedPhoto {
        let rgba = Data([value, value, value, 255])
        return try CapturedPhoto(data: SDRImage(rgba: rgba, width: 1, height: 1).jpeg(), expectedFormat: .jpeg)
    }
    private func folder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    func testBracketPlanUsesCurrentLimitsAndDoesNotClampToDuplicateExposures() throws {
        let plan = try ExposureBracketPlan.make(center: 0.5, step: 1, limits: -2...2, maximumCount: 3, rawMode: .processed, live: false, exposureMode: .continuousAutoExposure)
        XCTAssertEqual(plan.biases, [-0.5, 0.5, 1.5])
        for center in [1.5, Double.nan] {
            XCTAssertThrowsError(try ExposureBracketPlan.make(center: center, step: 1, limits: -2...2, maximumCount: 3, rawMode: .processed, live: false, exposureMode: .continuousAutoExposure))
        }
        for step in [0, 3, Double.infinity] {
            XCTAssertThrowsError(try ExposureBracketPlan.make(center: 0, step: step, limits: -2...2, maximumCount: 3, rawMode: .processed, live: false, exposureMode: .continuousAutoExposure))
        }
    }
    func testUnsupportedBracketCombinationsAreRejected() {
        for (maximum, raw, live, exposure) in [(0, RawCaptureMode.processed, false, AVCaptureDevice.ExposureMode.continuousAutoExposure),
                                               (2, .processed, false, .continuousAutoExposure), (3, .bayer, false, .continuousAutoExposure),
                                               (3, .appleProRAW, false, .continuousAutoExposure), (3, .processed, true, .continuousAutoExposure),
                                               (3, .processed, false, .custom), (3, .processed, false, .locked)] {
            XCTAssertThrowsError(try ExposureBracketPlan.make(center: 0, step: 1, limits: -2...2, maximumCount: maximum, rawMode: raw, live: live, exposureMode: exposure))
        }
    }
    func testUnorderedBracketCallbacksReturnRequestOrderWithExactBytes() throws {
        let photos = try [jpeg(20), jpeg(100), jpeg(220)]
        var delivery = PhotoSeriesDelivery(format: .jpeg, biases: [-1, 0, 1])
        for sequence in [3, 1] { try delivery.receive(photos[sequence - 1].data, isRaw: false, sequence: sequence, bracketBias: Double(sequence - 2)) }
        XCTAssertThrowsError(try delivery.result())
        try delivery.receive(photos[1].data, isRaw: false, sequence: 2, bracketBias: 0)
        let result = try delivery.result()
        XCTAssertEqual(result.photos.map(\.data), photos.map(\.data))
        XCTAssertEqual(result.requestedBiases, [-1, 0, 1])
    }
    func testDuplicateInvalidSequenceBiasAndRawCannotYieldSuccessfulPartialSeries() throws {
        let bytes = try jpeg(100).data
        for (sequence, bias, raw) in [(0, 0.0, false), (4, 0, false), (1, 1, false), (1, -1, true)] {
            var delivery = PhotoSeriesDelivery(format: .jpeg, biases: [-1, 0, 1])
            XCTAssertThrowsError(try delivery.receive(bytes, isRaw: raw, sequence: sequence, bracketBias: bias))
            XCTAssertThrowsError(try delivery.result())
        }
        var duplicate = PhotoSeriesDelivery(format: .jpeg, biases: [-1, 0, 1])
        try duplicate.receive(bytes, isRaw: false, sequence: 1, bracketBias: -1)
        XCTAssertThrowsError(try duplicate.receive(bytes, isRaw: false, sequence: 1, bracketBias: -1))
        XCTAssertThrowsError(try duplicate.result())
        var invalid = PhotoSeriesDelivery(format: .jpeg, biases: [])
        XCTAssertThrowsError(try invalid.receive(bytes, isRaw: false, sequence: 1, bracketBias: nil))
    }
    func testSeriesStoragePreservesAllOriginalsAndRequestedExposureManifest() throws {
        let root = try folder()
        let series = CapturedSeries(photos: try [jpeg(20), jpeg(100), jpeg(220)], requestedBiases: [-1, 0, 1])
        let urls = try CaptureSeriesStore.write(series, documents: root)
        XCTAssertEqual(urls.count, 3)
        for i in 0..<3 { XCTAssertEqual(try Data(contentsOf: urls[i]), series.photos[i].data) }
        let manifests = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("BracketGroups"), includingPropertiesForKeys: nil)
        let manifest = try JSONDecoder().decode(CaptureSeriesManifest.self, from: Data(contentsOf: XCTUnwrap(manifests.first)))
        XCTAssertEqual(manifest.frames.map(\.filename), urls.map(\.lastPathComponent))
        XCTAssertEqual(manifest.frames.map(\.requestedEV), [-1, 0, 1])
        XCTAssertEqual(manifest.frames.map(\.sha256), series.photos.map { LUTPhotoEditor.hash($0.data) })
    }
    func testManifestFailureRollsBackOnlyNewOriginals() throws {
        let root = try folder(), originals = root.appendingPathComponent("Originals")
        try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
        let prior = originals.appendingPathComponent("prior.jpg")
        try Data([42]).write(to: prior)
        try Data([1]).write(to: root.appendingPathComponent("BracketGroups"))
        let series = CapturedSeries(photos: try [jpeg(20), jpeg(100), jpeg(220)], requestedBiases: [-1, 0, 1])
        XCTAssertThrowsError(try CaptureSeriesStore.write(series, documents: root))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: originals.path), ["prior.jpg"])
        XCTAssertEqual(try Data(contentsOf: prior), Data([42]))
    }
    func testStoppedSessionRejectsBracketBeforeHardwareAccess() async {
        let service = CameraService { _ in }
        do { _ = try await service.captureSeries(format: .jpeg, bracketStep: 1); XCTFail("Expected stopped capture rejection") }
        catch { guard case CameraError.interrupted = error else { return XCTFail("Unexpected error: \(error)") } }
    }
}
