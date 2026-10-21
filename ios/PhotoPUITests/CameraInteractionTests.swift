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
}
