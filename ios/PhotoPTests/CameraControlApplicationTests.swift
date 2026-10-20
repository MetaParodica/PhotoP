import XCTest
import AVFoundation
@testable import PhotoP

final class CameraControlApplicationTests: XCTestCase {
    func testWaitsForAllControlsEvenWhenCallbacksAreOutOfOrder() throws {
        var application = CameraControlApplication()
        let id = try application.begin(steps: [.exposure, .focus, .whiteBalance])
        XCTAssertFalse(application.acknowledge(.whiteBalance, id: id))
        XCTAssertFalse(application.acknowledge(.exposure, id: id))
        XCTAssertTrue(application.isPending)
        XCTAssertTrue(application.acknowledge(.focus, id: id))
        XCTAssertFalse(application.isPending)
    }

    func testDuplicateCallbackCannotCompleteAnotherStep() throws {
        var application = CameraControlApplication()
        let id = try application.begin(steps: [.exposure, .focus])
        XCTAssertFalse(application.acknowledge(.exposure, id: id))
        XCTAssertFalse(application.acknowledge(.exposure, id: id))
        XCTAssertTrue(application.isPending)
        XCTAssertTrue(application.acknowledge(.focus, id: id))
        XCTAssertFalse(application.acknowledge(.focus, id: id))
    }

    func testInterruptionDiscardsCallbacksFromCancelledApplication() throws {
        var application = CameraControlApplication()
        let old = try application.begin(steps: [.exposure])
        XCTAssertTrue(application.cancel())
        let current = try application.begin(steps: [.focus])
        XCTAssertFalse(application.acknowledge(.exposure, id: old))
        XCTAssertTrue(application.isPending)
        XCTAssertTrue(application.acknowledge(.focus, id: current))
    }

    func testOldTimeoutCannotCancelNewApplication() throws {
        var application = CameraControlApplication()
        let old = try application.begin(steps: [.exposure])
        XCTAssertTrue(application.acknowledge(.exposure, id: old))
        let current = try application.begin(steps: [.exposure])
        XCTAssertFalse(application.cancel(id: old))
        XCTAssertTrue(application.isPending)
        XCTAssertTrue(application.cancel(id: current))
        XCTAssertFalse(application.isPending)
        XCTAssertFalse(application.acknowledge(.exposure, id: current))
    }

    func testOverlappingApplicationIsRejectedWithoutReplacingFirst() throws {
        var application = CameraControlApplication()
        let id = try application.begin(steps: [.exposure])
        XCTAssertThrowsError(try application.begin(steps: [.focus]))
        XCTAssertTrue(application.acknowledge(.exposure, id: id))
    }

    // Regression: .quality can override manual exposure in processed captures.
    func testCustomAndLockedExposureUseSpeedPolicy() {
        XCTAssertEqual(PhotoCapturePolicy.quality(for: .custom), .speed)
        XCTAssertEqual(PhotoCapturePolicy.quality(for: .locked), .speed)
    }

    func testAutomaticExposureRetainsQualityPolicy() {
        XCTAssertEqual(PhotoCapturePolicy.quality(for: .continuousAutoExposure), .quality)
        XCTAssertEqual(PhotoCapturePolicy.quality(for: .autoExpose), .quality)
        XCTAssertEqual(PhotoCapturePolicy.quality(for: nil), .quality)
    }
}
