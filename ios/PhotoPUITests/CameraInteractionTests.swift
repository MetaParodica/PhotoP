import XCTest
import UIKit

final class CameraInteractionTests: XCTestCase {
    @MainActor func testScopeChoicesKeepSDRContractWithoutFabricatingSimulatorSamples() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-review"]
        app.launch()
        XCTAssertTrue(app.buttons["camera.monitor"].waitForExistence(timeout: 10))
        app.buttons["camera.monitor"].tap()
        XCTAssertTrue(app.staticTexts["SDR 프리뷰 분석 · LUT 적용 전"].waitForExistence(timeout: 5))
        for id in ["waveform", "parade", "vectorscope", "falseColor"] {
            let toggle = app.switches["camera.monitor." + id]
            XCTAssertTrue(toggle.waitForExistence(timeout: 3))
            toggle.tap()
            XCTAssertEqual(toggle.value as? String, "1")
        }
        XCTAssertFalse(app.descendants(matching: .any)["camera.monitor.readouts"].exists)
        XCTAssertFalse(app.buttons["camera.shutter"].isEnabled)
    }
    @MainActor func testDepthLibraryOpensFromBottomPanelWithoutInventingCameraSupport() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-review", "--review-depth"]
        app.launch()
        let panel = app.otherElements["camera.panel.aperture"]
        XCTAssertTrue(panel.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["camera.shutter"].isEnabled)
        let library = app.buttons["camera.depth.library"]
        reveal(library, in: panel)
        library.tap()
        XCTAssertTrue(app.navigationBars["심도 보관함"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["저장된 심도 사진이 없습니다."].waitForExistence(timeout: 5))
        app.buttons["닫기"].tap()
        XCTAssertTrue(app.buttons["camera.shutter"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["camera.shutter"].isEnabled)
    }
    @MainActor func testAIRecommendationsAreHiddenWhileManualGuidesRemain() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-review"]
        app.launch()
        XCTAssertTrue(app.buttons["camera.guide"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["camera.ai"].exists)
        app.buttons["camera.guide"].tap()
        app.buttons["camera.card.settings"].tap()
        XCTAssertTrue(app.otherElements["camera.panel.guide"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["camera.guide.grid.thirds"].exists)
        XCTAssertFalse(app.switches["camera.ai.toggle"].exists)
        XCTAssertFalse(app.buttons["구도 라이브러리"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["camera.ai.status"].exists)
        XCTAssertFalse(app.buttons["camera.shutter"].isEnabled)
        XCTAssertFalse(app.buttons["camera.coach.zoom"].exists)
    }
    @MainActor func testDepthQuickPanelShowsPrimaryControlsBeforeAdvancedOptions() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-review", "--review-depth"]
        app.launch()
        let panel = app.otherElements["camera.panel.aperture"]
        XCTAssertTrue(panel.waitForExistence(timeout: 10))
        let toggle = app.switches["camera.depth.toggle"]
        XCTAssertTrue(toggle.isHittable)
        XCTAssertFalse(toggle.isEnabled)
        let stop = app.buttons["camera.depth.stop.14"]
        XCTAssertTrue(stop.exists)
        XCTAssertFalse(stop.isEnabled)
        XCTAssertLessThan(toggle.frame.minY, stop.frame.minY)
        XCTAssertFalse(app.descendants(matching: .any)["camera.depth.source"].exists)
        XCTAssertFalse(app.switches["camera.depth.live"].exists)
        XCTAssertFalse(app.buttons["camera.shutter"].isEnabled)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "PhotoP-depth-quick-panel"; shot.lifetime = .keepAlways; add(shot)
    }
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
        // XCTest scrolls this nested choice into view before synthesizing its
        // tap. Checking a custom scroll helper first can oscillate past it.
        person.tap()
        XCTAssertTrue(person.isSelected)
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

    @MainActor func testBoxedViewfinderDoesNotOverlapSettingsInBothOrientations() {
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
            let before = finder.frame
            app.buttons["camera.monitor"].tap()
            let panel = app.descendants(matching: .any)["camera.panel.monitor"]
            XCTAssertTrue(panel.waitForExistence(timeout: 3))
            XCTAssertFalse(finder.frame.intersects(dock.frame))
            XCTAssertFalse(finder.frame.intersects(panel.frame))
            XCTAssertTrue(app.frame.contains(finder.frame.insetBy(dx: 1, dy: 1)))
            XCTAssertTrue(app.frame.contains(dock.frame.insetBy(dx: 1, dy: 1)))
            if orientation == .portrait {
                XCTAssertEqual(finder.frame.width, before.width, accuracy: 1)
                XCTAssertLessThan(finder.frame.height, before.height)
            } else {
                XCTAssertEqual(finder.frame.width, before.width, accuracy: 1)
                XCTAssertEqual(finder.frame.height, before.height, accuracy: 1)
            }
            XCTAssertTrue(app.buttons["camera.shutter"].isHittable)
            XCTAssertFalse(app.buttons["디지털 줌"].exists)
            app.buttons["camera.panel.close"].tap()
        }
    }

    @MainActor func testDepthIsAvailableFromProApertureControlNotASeparateMode() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-review"]
        app.launch()
        XCTAssertFalse(app.buttons["camera.mode.depth"].exists)
        app.buttons["PRO"].tap()
        let rail = app.buttons["camera.tool.aperture"]
        // PRO has a horizontally scrollable control rail on narrow devices.
        for _ in 0..<4 where !rail.isHittable { app.descendants(matching: .any)["camera.controls.rail"].swipeLeft() }
        XCTAssertTrue(rail.waitForExistence(timeout: 3)); rail.tap()
        XCTAssertTrue(app.descendants(matching: .any)["camera.panel.aperture"].waitForExistence(timeout: 3))
        let toggle = app.switches["camera.depth.toggle"]
        XCTAssertTrue(toggle.exists); XCTAssertFalse(toggle.isEnabled, "No simulated depth capability may be invented")
        app.buttons["camera.panel.close"].tap()
        XCTAssertTrue(app.buttons["camera.shutter"].waitForExistence(timeout: 5))
    }

    @MainActor func testLongExposureDurationIsFirstAndSupportsDirectEntry() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-review"]; app.launch()
        app.buttons["LONG"].tap()
        let duration = app.buttons["camera.tool.longExposure"]
        XCTAssertTrue(duration.waitForExistence(timeout: 3))
        XCTAssertLessThan(duration.frame.minX, app.buttons["camera.tool.iso"].frame.minX)
        XCTAssertEqual(duration.value as? String, "4 s")
        duration.tap()
        let field = app.textFields["camera.long.duration.input"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        app.buttons["camera.long.duration.clear"].tap()
        field.typeText("12")
        if app.buttons["완료"].exists { app.buttons["완료"].tap() }
        app.buttons["camera.panel.close"].tap()
        XCTAssertEqual(app.buttons["camera.tool.longExposure"].value as? String, "12 s")
        XCTAssertFalse(app.buttons["camera.shutter"].isEnabled)
    }

    @MainActor private func reveal(_ element: XCUIElement, in panel: XCUIElement) {
        let scroll = panel.descendants(matching: .scrollView).matching(identifier: panel.identifier.replacingOccurrences(of: "camera.panel.", with: "camera.panel.scroll.")).firstMatch
        for _ in 0..<8 {
            if element.isHittable { return }
            // A full swipe can pass a short choice row and then keep moving
            // away from it. Use the target's current position and short drags
            // at the vertical panel edge, outside nested horizontal choices.
            let container = scroll.exists ? scroll : panel
            let viewport = container.frame.intersection(panel.frame)
            let below = element.frame.midY > viewport.midY
            let start = container.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: below ? 0.82 : 0.25))
            let end = container.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: below ? 0.42 : 0.65))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(element.isHittable, "Control must be reachable in its bottom panel: \(element.identifier)")
    }
}
