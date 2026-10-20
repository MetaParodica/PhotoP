import XCTest
@testable import PhotoP

final class CameraSettingsTests: XCTestCase {
    private let caps = CameraCapabilities(lensID: "test", iso: 32...1600, shutterSeconds: 0.0001...1,
                                          exposureBias: -2...2, manualExposure: true, manualFocus: true,
                                          manualWhiteBalance: true)

    func testManualExposureRejectsOutOfRangeAndNonFiniteValues() {
        var settings = CameraSettings()
        settings.exposure.manual = true
        for iso in [0, 1601, Double.nan, Double.infinity] {
            settings.exposure.iso = iso
            XCTAssertThrowsError(try CameraSettingsValidator.validate(settings, for: caps))
        }
        settings.exposure.iso = 100
        settings.exposure.shutterSeconds = 2
        XCTAssertThrowsError(try CameraSettingsValidator.validate(settings, for: caps))
    }

    func testBoundaryValuesAreAccepted() throws {
        var settings = CameraSettings()
        settings.exposure.manual = true
        settings.exposure.iso = 32
        settings.exposure.shutterSeconds = 1
        settings.focus.manual = true
        settings.focus.lensPosition = 1
        try CameraSettingsValidator.validate(settings, for: caps)
    }

    func testUnsupportedControlsAreRejected() {
        let limited = CameraCapabilities(lensID: "fixed", iso: 32...1600, shutterSeconds: 0.0001...1,
                                         exposureBias: -2...2, manualExposure: false, manualFocus: false,
                                         manualWhiteBalance: false)
        var settings = CameraSettings()
        settings.focus.manual = true
        XCTAssertThrowsError(try CameraSettingsValidator.validate(settings, for: limited))
        settings.focus.manual = false
        settings.whiteBalance.manual = true
        XCTAssertThrowsError(try CameraSettingsValidator.validate(settings, for: limited))
        settings.whiteBalance.manual = false
        settings.exposure.manual = true
        XCTAssertThrowsError(try CameraSettingsValidator.validate(settings, for: limited))
    }

    func testAutomaticExposureRejectsInvalidBias() {
        var settings = CameraSettings()
        settings.exposure.ev = 3
        XCTAssertThrowsError(try CameraSettingsValidator.validate(settings, for: caps))
    }

    func testManualFocusAndWhiteBalanceValidateRanges() {
        var settings = CameraSettings()
        settings.focus.manual = true
        settings.focus.lensPosition = -0.1
        XCTAssertThrowsError(try CameraSettingsValidator.validate(settings, for: caps))
        settings.focus = FocusSettings()
        settings.whiteBalance.manual = true
        settings.whiteBalance.kelvin = 10001
        XCTAssertThrowsError(try CameraSettingsValidator.validate(settings, for: caps))
    }
}
