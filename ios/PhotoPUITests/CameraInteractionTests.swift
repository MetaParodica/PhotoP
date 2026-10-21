import XCTest

final class CameraInteractionTests: XCTestCase {
    @MainActor
    func testContextualControlsStayOnCameraAndKeepShutterVisible() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-review"]
        app.launch()
        let shutter = app.buttons["camera.shutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 10))
        XCTAssertFalse(shutter.isEnabled, "Simulator review must never advertise a working camera")
        app.buttons["camera.guide"].tap()
        XCTAssertTrue(app.otherElements["camera.panel.guide"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["camera.panel.close"].isHittable)
        XCTAssertTrue(app.staticTexts["구도선"].exists)
        let grid = app.buttons["camera.guide.grid"]
        XCTAssertEqual(grid.value as? String, "삼분할")
        grid.tap(); app.buttons["숨기기"].tap()
        XCTAssertEqual(grid.value as? String, "숨기기")
        grid.tap(); app.buttons["삼분할"].tap()
        XCTAssertEqual(grid.value as? String, "삼분할")
        XCTAssertTrue(shutter.exists)
        let guide = XCTAttachment(screenshot: app.screenshot()); guide.name = "PhotoP-inline-guide"; guide.lifetime = .keepAlways; add(guide)
        app.buttons["camera.panel.close"].tap()
        app.buttons["camera.tool.iso"].tap()
        XCTAssertTrue(app.staticTexts["카메라를 연결하면 이 렌즈가 지원하는 제어 범위가 표시됩니다."].waitForExistence(timeout: 3))
        app.buttons["camera.panel.close"].tap()
        app.buttons["camera.format"].tap()
        XCTAssertTrue(app.otherElements["camera.panel.format"].waitForExistence(timeout: 3))
        app.buttons["camera.panel.close"].tap()
        let camera = XCTAttachment(screenshot: app.screenshot()); camera.name = "PhotoP-camera"; camera.lifetime = .keepAlways; add(camera)
    }
    @MainActor func testVideoPanelDoesNotInventHardwareCapabilities() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-review"]
        app.launch()
        app.buttons["camera.mode.video"].tap()
        XCTAssertTrue(app.otherElements["camera.panel.video"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["SDR · 원본 색상 · 무음"].exists)
        XCTAssertTrue(app.staticTexts["카메라 연결 후 지원 해상도·FPS·코덱이 표시됩니다."].exists)
        XCTAssertFalse(app.segmentedControls["camera.video.resolution"].exists)
        XCTAssertFalse(app.buttons["camera.record"].exists)
        XCTAssertFalse(app.buttons["camera.shutter"].isEnabled)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "PhotoP-video-panel"; capture.lifetime = .keepAlways; add(capture)
    }

}
