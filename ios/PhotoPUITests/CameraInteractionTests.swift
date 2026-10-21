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
        // AUTO keeps only EV on the rail; the look control is a separate button.
        XCTAssertFalse(app.buttons["camera.tool.iso"].exists)
        XCTAssertTrue(app.buttons["camera.tool.ev"].exists)
        XCTAssertTrue(app.buttons["camera.tool.looks"].exists)
        app.buttons["PRO"].tap()
        XCTAssertTrue(app.buttons["PRO"].isSelected)
        XCTAssertTrue(app.staticTexts["카메라를 연결하면 이 렌즈가 지원하는 제어 범위가 표시됩니다."].waitForExistence(timeout: 3))
        app.buttons["camera.panel.close"].tap()
        XCTAssertTrue(app.buttons["camera.tool.iso"].exists)
        XCTAssertTrue(app.buttons["camera.tool.whiteBalance"].exists)
        app.buttons["camera.format"].tap()
        app.buttons["상세 설정 · 해상도 · 브래킷"].tap()
        XCTAssertTrue(app.otherElements["camera.panel.format"].waitForExistence(timeout: 3))
        app.buttons["camera.panel.close"].tap()
        let framing = app.buttons["camera.framing"]
        XCTAssertEqual(framing.value as? String, "4:3")
        framing.tap()
        XCTAssertEqual(framing.value as? String, "1:1")
        app.buttons["camera.timer"].tap()
        XCTAssertEqual(app.buttons["camera.shutter"].label, "3초 후 사진 촬영")
        XCTAssertFalse(app.buttons["camera.flash"].isEnabled, "Without a camera no flash mode may be offered")
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
        XCTAssertFalse(app.buttons["camera.mode.video"].isSelected, "Opening a panel cannot advertise an unconfigured video mode")
        XCTAssertTrue(app.buttons["AUTO"].isSelected)
        XCTAssertFalse(app.buttons["camera.shutter"].isEnabled)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "PhotoP-video-panel"; capture.lifetime = .keepAlways; add(capture)
    }

    @MainActor func testVideoLibraryOpensFromCameraAndReturns() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-review"]
        app.launch()
        let gallery = app.buttons["사진과 편집 기록"]
        XCTAssertTrue(gallery.waitForExistence(timeout: 10))
        gallery.tap()
        XCTAssertTrue(app.staticTexts["아직 촬영한 사진이 없습니다."].waitForExistence(timeout: 5))
        app.buttons["영상 보관함"].tap()
        XCTAssertTrue(app.navigationBars["영상 보관함"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["보관한 영상이 없습니다."].waitForExistence(timeout: 5))
        app.buttons["닫기"].tap()
        XCTAssertTrue(app.buttons["camera.shutter"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["camera.shutter"].isEnabled)
    }

    @MainActor func testPersonGuideCanBeChosenOnCamera() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-review"]
        app.launch()
        app.buttons["camera.guide"].tap()
        XCTAssertTrue(app.otherElements["camera.panel.guide"].waitForExistence(timeout: 3))
        let person = app.buttons["camera.guide.person"]
        XCTAssertTrue(person.waitForExistence(timeout: 3))
        person.tap(); app.buttons["전신"].tap()
        XCTAssertTrue(app.segmentedControls["camera.guide.person.position"].waitForExistence(timeout: 3))
        app.segmentedControls["camera.guide.person.position"].buttons["왼쪽 1/3"].tap()
        XCTAssertTrue(app.staticTexts[PersonFramingCopy.full].exists)
        app.buttons["camera.panel.close"].tap()
        let overlay = app.descendants(matching: .any)["camera.person.guide"]
        XCTAssertTrue(overlay.waitForExistence(timeout: 3))
        XCTAssertEqual(overlay.label, "인물 위치 가이드: 전신, 왼쪽 1/3")
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "PhotoP-person-guide"; capture.lifetime = .keepAlways; add(capture)
    }
}

private enum PersonFramingCopy {
    static let full = "발끝을 화면 아래 끝에 맞추고 카메라를 허리 높이로 낮추면 다리가 길어 보입니다."
}
