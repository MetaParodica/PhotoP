import XCTest
@testable import PhotoP

final class PointMeteringTests: XCTestCase {
    func testNormalizedPointAcceptsEdgesAndRejectsOutsideOrNonFinite() throws {
        _ = try CameraMeteringPoint(x: 0, y: 1)
        _ = try CameraMeteringPoint(x: 1, y: 0)
        for value in [-0.001, 1.001, .nan, .infinity] {
            XCTAssertThrowsError(try CameraMeteringPoint(x: value, y: 0.5))
            XCTAssertThrowsError(try CameraMeteringPoint(x: 0.5, y: value))
        }
    }

    func testManualOrLockedControlsAreNeverOverwrittenByTouch() {
        let focusLocked = PointMeteringPolicy.actions(focusSupported: true, exposureSupported: true,
                                                      focusLocked: true, exposureLocked: false)
        XCTAssertEqual(focusLocked, PointMeteringActions(focus: false, exposure: true))
        let exposureLocked = PointMeteringPolicy.actions(focusSupported: true, exposureSupported: true,
                                                         focusLocked: false, exposureLocked: true)
        XCTAssertEqual(exposureLocked, PointMeteringActions(focus: true, exposure: false))
        XCTAssertTrue(PointMeteringPolicy.actions(focusSupported: true, exposureSupported: true,
                                                  focusLocked: true, exposureLocked: true).isEmpty)
    }

    func testUnsupportedPointControlsAreExcluded() {
        XCTAssertTrue(PointMeteringPolicy.actions(focusSupported: false, exposureSupported: false,
                                                  focusLocked: false, exposureLocked: false).isEmpty)
        XCTAssertEqual(PointMeteringPolicy.actions(focusSupported: false, exposureSupported: true,
                                                    focusLocked: false, exposureLocked: false),
                       PointMeteringActions(focus: false, exposure: true))
    }

    func testLocksRequireCapabilityAndCannotConflictWithManualRequests() throws {
        var caps = CameraCapabilities(lensID: "test", iso: 32...1600, shutterSeconds: 0.0001...1,
                                      exposureBias: -2...2, manualExposure: true, manualFocus: true,
                                      manualWhiteBalance: true)
        var settings = CameraSettings()
        settings.exposure.locked = true
        XCTAssertThrowsError(try CameraSettingsValidator.validate(settings, for: caps))
        caps.exposureLock = true
        try CameraSettingsValidator.validate(settings, for: caps)
        settings.exposure.manual = true
        XCTAssertThrowsError(try CameraSettingsValidator.validate(settings, for: caps))
        settings = CameraSettings()
        settings.focus.locked = true
        XCTAssertThrowsError(try CameraSettingsValidator.validate(settings, for: caps))
        caps.focusLock = true
        try CameraSettingsValidator.validate(settings, for: caps)
        settings.focus.manual = true
        XCTAssertThrowsError(try CameraSettingsValidator.validate(settings, for: caps))
        settings = CameraSettings()
        settings.whiteBalance.locked = true
        XCTAssertThrowsError(try CameraSettingsValidator.validate(settings, for: caps))
        caps.whiteBalanceLock = true
        try CameraSettingsValidator.validate(settings, for: caps)
        settings.whiteBalance.manual = true
        XCTAssertThrowsError(try CameraSettingsValidator.validate(settings, for: caps))
    }
}
