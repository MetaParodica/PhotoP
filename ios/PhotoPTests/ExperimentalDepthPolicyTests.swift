import XCTest
#if canImport(PhotoP)
@testable import PhotoP
#else
@testable import PhotoPImagePolicies
#endif

final class ExperimentalDepthPolicyTests: XCTestCase {
    private func store() throws -> (ExperimentalDepthRuntime, UserDefaults) {
        let suite = "photop.tests.experiments." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return (ExperimentalDepthRuntime(defaults: defaults), defaults)
    }
    func testDefaultOffDoesNotMigrateOrResetBaselineDepthPreferences() throws {
        let (runtime, defaults) = try store()
        defaults.set(true, forKey: "camera.depth.enabled")
        defaults.set(1.4, forKey: "camera.depth.aperture")
        XCTAssertFalse(runtime.current.photoSubjectSelection)
        for mode in [ExperimentalDepthMode.photo, .savedVideo, .live] { XCTAssertNil(runtime.request(for: mode)) }
        runtime.setPhotoSelection(true); runtime.setPhotoSelection(false)
        XCTAssertTrue(defaults.bool(forKey: "camera.depth.enabled"))
        XCTAssertEqual(defaults.double(forKey: "camera.depth.aperture"), 1.4)
    }
    func testPhotoOptInPersistsAndCannotEnableVideoOrLive() throws {
        let (runtime, defaults) = try store()
        runtime.setPhotoSelection(true)
        XCTAssertNotNil(runtime.request(for: .photo))
        XCTAssertNil(runtime.request(for: .savedVideo)); XCTAssertNil(runtime.request(for: .live))
        XCTAssertTrue(ExperimentalDepthRuntime(defaults: defaults).current.photoSubjectSelection)
        defaults.set(Data("{\"version\":99,\"photoSubjectSelection\":true}".utf8), forKey: ExperimentalDepthRuntime.preferenceKey)
        XCTAssertFalse(ExperimentalDepthRuntime(defaults: defaults).current.photoSubjectSelection)
    }
    func testDisablingAndReenablingRejectsOldWorkAtPublication() throws {
        let (runtime, _) = try store(); runtime.setPhotoSelection(true)
        let old = try XCTUnwrap(runtime.request(for: .photo))
        runtime.setPhotoSelection(false); runtime.setPhotoSelection(true)
        XCTAssertFalse(old.isCurrent)
        var published = false
        XCTAssertFalse(old.publishIfCurrent { published = true }); XCTAssertFalse(published)
        let current = try XCTUnwrap(runtime.request(for: .photo))
        XCTAssertTrue(current.publishIfCurrent { published = true }); XCTAssertTrue(published)
    }
    func testMaskRequiresSelectedPointVisibleObjectFiniteOutputAndUsefulArea() throws {
        var logits = [Float](repeating: -8, count: 256 * 256)
        for y in 60..<120 { for x in 40..<100 { logits[y * 256 + x] = 8 } }
        func alpha(_ x: Double, _ y: Double, iou: Float = 0.9, score: Float = 1) -> [Float]? {
            ExperimentalPhotoMaskPolicy.alpha(logits: logits, width: 256, height: 256, x: x, y: y, predictedIoU: iou, objectScore: score)
        }
        let valid = try XCTUnwrap(alpha(0.25, 0.35))
        XCTAssertGreaterThan(valid[80 * 256 + 64], 0.99); XCTAssertLessThan(valid[8], 0.01)
        XCTAssertNil(alpha(0.8, 0.8)); XCTAssertNil(alpha(.nan, 0.3))
        XCTAssertNil(alpha(0.25, 0.35, iou: 0.49)); XCTAssertNil(alpha(0.25, 0.35, score: 0))
        logits[0] = .infinity; XCTAssertNil(alpha(0.25, 0.35))
        logits = Array(repeating: 8, count: 256 * 256); XCTAssertNil(alpha(0.25, 0.35))
    }
    func testProvenanceDoesNotCallFallbackAnAppliedModel() throws {
        var record = ExperimentalDepthRecord(outcome: .fallback, failure: .noSubject, focusX: 0.4, focusY: 0.6)
        XCTAssertTrue(record.valid)
        record.outcome = .applied; XCTAssertFalse(record.valid)
        record.failure = nil; record.predictedIoU = 0.9; record.objectScore = 5
        XCTAssertTrue(record.valid)
        XCTAssertEqual(record, try JSONDecoder().decode(ExperimentalDepthRecord.self, from: JSONEncoder().encode(record)))
        record.archiveSHA256 = "unknown"; XCTAssertFalse(record.valid)
    }
}
