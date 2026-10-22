import XCTest
import UIKit

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
        XCTAssertTrue(app.buttons["camera.card.settings"].waitForExistence(timeout: 3))
        app.buttons["camera.card.settings"].tap()
        XCTAssertTrue(app.otherElements["camera.panel.guide"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["camera.panel.close"].isHittable)
        XCTAssertTrue(app.staticTexts["구도선"].exists)
        let thirds = app.buttons["camera.guide.grid.thirds"]
        XCTAssertTrue(thirds.isSelected)
        app.buttons["camera.guide.grid.off"].tap()
        XCTAssertTrue(app.buttons["camera.guide.grid.off"].isSelected)
        thirds.tap()
        XCTAssertTrue(thirds.isSelected)
        XCTAssertTrue(shutter.exists)
        let guide = XCTAttachment(screenshot: app.screenshot()); guide.name = "PhotoP-inline-guide"; guide.lifetime = .keepAlways; add(guide)
        app.buttons["camera.panel.close"].tap()
        // AUTO keeps only EV on the rail; the look control is a separate button.
        XCTAssertFalse(app.buttons["camera.tool.iso"].exists)
        XCTAssertTrue(app.buttons["camera.tool.ev"].exists)
        XCTAssertTrue(app.buttons["camera.tool.looks"].exists)
        app.buttons["PRO"].tap()
        XCTAssertTrue(app.buttons["PRO"].isSelected)
        XCTAssertFalse(app.otherElements["camera.panel.iso"].exists, "Changing mode must not open a settings tab")
        app.buttons["camera.tool.iso"].tap()
        XCTAssertTrue(app.staticTexts["카메라를 연결하면 이 렌즈가 지원하는 제어 범위가 표시됩니다."].waitForExistence(timeout: 3))
        app.buttons["camera.panel.close"].tap()
        XCTAssertTrue(app.buttons["camera.tool.iso"].exists)
        XCTAssertTrue(app.buttons["camera.tool.whiteBalance"].exists)
        app.buttons["camera.format"].tap()
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
    @MainActor func testVideoModeDoesNotOpenSettingsOrInventHardwareCapabilities() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-review"]
        app.launch()
        app.buttons["camera.mode.video"].tap()
        XCTAssertFalse(app.otherElements["camera.panel.video"].exists, "Mode selection cannot open settings automatically")
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
        XCTAssertTrue(app.buttons["camera.card.settings"].waitForExistence(timeout: 3))
        app.buttons["camera.card.settings"].tap()
        XCTAssertTrue(app.otherElements["camera.panel.guide"].waitForExistence(timeout: 3))
        let person = app.buttons["camera.guide.person.full"]
        XCTAssertTrue(person.waitForExistence(timeout: 3))
        reveal(person, in: app.otherElements["camera.panel.guide"])
        person.tap()
        XCTAssertTrue(app.segmentedControls["camera.guide.person.position"].waitForExistence(timeout: 3))
        reveal(app.segmentedControls["camera.guide.person.position"], in: app.otherElements["camera.panel.guide"])
        app.segmentedControls["camera.guide.person.position"].buttons["왼쪽 1/3"].tap()
        app.buttons["camera.panel.close"].tap()
        let overlay = app.descendants(matching: .any)["camera.person.guide"]
        XCTAssertTrue(overlay.waitForExistence(timeout: 3))
        XCTAssertEqual(overlay.label, "인물 위치 가이드: 전신, 왼쪽 1/3")
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "PhotoP-person-guide"; capture.lifetime = .keepAlways; add(capture)
    }

    @MainActor func testBottomCardsSelectCompositionGuidesAndLooks() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-review"]
        app.launch()
        app.buttons["camera.guide"].tap()
        // The first preset follows the three utility cards and is visible without scrolling.
        let triangle = app.buttons["camera.card.portrait-two-thirds"]
        XCTAssertTrue(triangle.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["camera.card.off"].isSelected)
        XCTAssertFalse(app.buttons["AUTO"].exists, "Cards replace the mode row while the drawer is open")
        triangle.tap()
        XCTAssertTrue(triangle.isSelected)
        let overlay = app.descendants(matching: .any)["camera.composition.preset"]
        XCTAssertTrue(overlay.waitForExistence(timeout: 3))
        XCTAssertTrue(overlay.label.contains("인물 2/3"))
        let composition = XCTAttachment(screenshot: app.screenshot())
        composition.name = "PhotoP-composition-cards"; composition.lifetime = .keepAlways; add(composition)
        app.buttons["camera.drawer.close"].tap()
        XCTAssertTrue(app.buttons["AUTO"].waitForExistence(timeout: 3))
        XCTAssertTrue(overlay.exists, "Closing the drawer keeps the chosen guide")
        app.buttons["camera.tool.looks"].tap()
        XCTAssertTrue(app.buttons["camera.card.original"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["camera.card.original"].isSelected)
        XCTAssertTrue(app.buttons["camera.card.amber-portrait"].exists)
        let looks = XCTAttachment(screenshot: app.screenshot())
        looks.name = "PhotoP-look-cards"; looks.lifetime = .keepAlways; add(looks)
    }

    @MainActor func testControlsStayBelowViewfinderInBothOrientations() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-review"]
        app.launch()
        defer { XCUIDevice.shared.orientation = .portrait }
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft, .landscapeRight] {
            XCUIDevice.shared.orientation = orientation
            let finder = app.descendants(matching: .any)["camera.viewfinder"]
            let dock = app.descendants(matching: .any)["camera.dock"]
            XCTAssertTrue(finder.waitForExistence(timeout: 5))
            XCTAssertTrue(dock.exists)
            app.buttons["camera.monitor"].tap()
            let panel = app.descendants(matching: .any)["camera.panel.monitor"]
            XCTAssertTrue(panel.waitForExistence(timeout: 3))
            XCTAssertGreaterThanOrEqual(panel.frame.minY, finder.frame.maxY - 1)
            XCTAssertTrue(app.buttons["camera.shutter"].isHittable)
            XCTAssertFalse(app.buttons["디지털 줌"].exists)
            app.buttons["camera.panel.close"].tap()
        }
    }

    @MainActor func testDepthModeExplainsUnavailableHardwareOnSimulator() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-review"]
        app.launch()
        app.buttons["camera.mode.depth"].tap()
        XCTAssertTrue(app.staticTexts["LiDAR 지원 기기가 필요합니다"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["camera.depth.capture"].exists)
        app.buttons["닫기"].tap()
        XCTAssertTrue(app.buttons["camera.shutter"].waitForExistence(timeout: 5))
    }

    @MainActor private func reveal(_ element: XCUIElement, in panel: XCUIElement) {
        for _ in 0..<8 {
            if element.isHittable { return }
            let start = panel.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.9))
            let end = panel.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.35))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(element.isHittable)
    }
}
