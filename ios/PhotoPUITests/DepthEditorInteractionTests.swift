import XCTest
import UIKit

final class DepthEditorInteractionTests: XCTestCase {
    @MainActor func testPhotoExperimentPersistsAndReanalysisLeavesBaselineEditingAvailable() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-review", "--review-depth-editor"]
        app.launch(); defer { app.terminate() }
        func openExperiments() {
            XCTAssertTrue(app.sliders["editor.depth.aperture"].waitForExistence(timeout: 25))
            app.buttons["심도 교정·진단"].tap()
            let lab = app.buttons["실험실 · 추가 AI 기능"]
            reveal(lab, in: app); lab.tap()
        }
        XCTAssertTrue(app.sliders["editor.depth.aperture"].waitForExistence(timeout: 25))
        let originalValue = app.staticTexts["editor.depth.apertureValue"].label
        let selectedProfile = app.segmentedControls["editor.depth.profile"].buttons.matching(NSPredicate(format: "isSelected == true")).firstMatch
        XCTAssertTrue(selectedProfile.waitForExistence(timeout: 5))
        let originalProfile = selectedProfile.label
        openExperiments()
        let toggle = app.switches["experiments.depth.photoSelection"]
        reveal(toggle, in: app)
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.tap(); XCTAssertEqual(toggle.value as? String, "1")
        let portrait = app.switches["experiments.depth.portraitMatte"]
        reveal(portrait, in: app); XCTAssertEqual(portrait.value as? String, "0"); portrait.tap()
        app.terminate(); app.launch(); openExperiments(); reveal(toggle, in: app)
        XCTAssertEqual(toggle.value as? String, "1", "Only the new photo preference should persist")
        XCTAssertEqual(portrait.value as? String, "1")
        let analyse = app.buttons["editor.depth.reanalyse"]
        reveal(analyse, in: app); analyse.tap()
        let outcome = app.staticTexts["editor.depth.experimentResult"]
        XCTAssertTrue(outcome.waitForExistence(timeout: 90))
        XCTAssertTrue(outcome.label.contains("실험적 사진 정밀 선택 적용") || outcome.label.contains("정밀 선택은 기존 방식으로 처리"))
        reveal(portrait, in: app); portrait.tap(); XCTAssertEqual(portrait.value as? String, "0")
        reveal(toggle, in: app); toggle.tap(); XCTAssertEqual(toggle.value as? String, "0")
        XCTAssertTrue(app.sliders["editor.depth.aperture"].isEnabled)
        XCTAssertTrue(app.segmentedControls["editor.depth.profile"].isEnabled)
        XCTAssertTrue(app.switches["editor.depth.brush"].isEnabled)
        XCTAssertEqual(app.staticTexts["editor.depth.apertureValue"].label, originalValue)
        XCTAssertTrue(app.segmentedControls["editor.depth.profile"].buttons[originalProfile].isSelected)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "experimental-photo-selection-result"; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<8 {
            let top = app.navigationBars.firstMatch.frame.maxY + 4
            let bottom = app.windows.firstMatch.frame.maxY - 40
            if element.isHittable, element.frame.minY >= top, element.frame.maxY <= bottom { return }
            if element.frame.minY < top { scroll.swipeDown() } else { scroll.swipeUp() }
        }
        XCTAssertTrue(element.isHittable)
    }
    @MainActor func testSavingLocksApertureAndProfileUntilRealSaveCompletes() {
        checkSaveLock(cancel: false)
    }
    @MainActor func testCancellingSaveUnlocksApertureAndProfile() {
        checkSaveLock(cancel: true)
    }
    @MainActor func testCorrectionBrushUndoRedoAndDepthDiagnostic() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-review", "--review-depth-editor"]
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.sliders["editor.depth.aperture"].waitForExistence(timeout: 20))
        app.buttons["심도 교정·진단"].tap()
        let brush = app.switches["editor.depth.brush"]
        XCTAssertTrue(brush.waitForExistence(timeout: 5)); brush.tap()
        let canvas = app.descendants(matching: .any)["editor.depth.canvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 15))
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.55,dy: 0.5)).press(forDuration: 0.15,
            thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.7,dy: 0.5)))
        let count = app.staticTexts["editor.depth.strokeCount"]
        let undo = app.buttons["editor.depth.undo"], redo = app.buttons["editor.depth.redo"]
        let controls = app.scrollViews.firstMatch
        for _ in 0..<4 where !undo.isHittable { controls.swipeUp() }
        XCTAssertEqual(count.label,"교정 1개"); XCTAssertTrue(undo.isEnabled)
        undo.tap(); XCTAssertEqual(count.label,"교정 0개"); XCTAssertTrue(redo.isEnabled)
        redo.tap(); XCTAssertEqual(count.label,"교정 1개")
        for _ in 0..<4 where !brush.isHittable { controls.swipeDown() }
        brush.tap()
        let diagnostic = app.buttons["editor.depth.diagnostic"]
        diagnostic.tap(); app.buttons["깊이 지도"].tap()
        XCTAssertTrue(canvas.exists)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "depth-correction-diagnostic"; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor private func checkSaveLock(cancel: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-review", "--review-depth-editor"]
        app.launch()
        defer { app.terminate() }
        let aperture = app.sliders["editor.depth.aperture"]
        XCTAssertTrue(aperture.waitForExistence(timeout: 20))
        aperture.adjust(toNormalizedSliderPosition: 0.35)
        let profile = app.segmentedControls["editor.depth.profile"]
        profile.buttons["Portrait"].tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"),object: profile.buttons["Portrait"])
        XCTAssertEqual(XCTWaiter.wait(for: [selected],timeout: 3),.completed)
        XCTAssertTrue(profile.buttons["Portrait"].isSelected)
        let value = app.staticTexts["editor.depth.apertureValue"].label
        app.buttons["editor.depth.save"].tap()
        let cancelSave = app.buttons["editor.depth.cancel"]
        XCTAssertTrue(cancelSave.waitForExistence(timeout: 5))
        XCTAssertFalse(aperture.isEnabled, "saving: aperture must be disabled")
        // Per-segment flags are independent of UISegmentedControl.isEnabled.
        // Assert the enclosing control, then physically try to change selection.
        XCTAssertFalse(profile.isEnabled, "saving: profile control must be disabled")
        XCTAssertFalse(app.switches["editor.depth.compare"].isEnabled, "saving: comparison must be disabled")
        // Physical touches exercise the disabled controls without XCTest refusing
        // the action because their accessibility state correctly says disabled.
        profile.buttons["Classic"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        aperture.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: aperture.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)))
        XCTAssertEqual(app.staticTexts["editor.depth.apertureValue"].label, value)
        XCTAssertTrue(profile.buttons["Portrait"].isSelected)
        XCTAssertFalse(profile.buttons["Classic"].isSelected, "disabled profile must ignore physical touch")
        if cancel { cancelSave.tap() }
        else { app.buttons["editor.review.releaseSave"].tap() }
        let message = app.staticTexts["editor.depth.message"]
        let expected = cancel ? "저장을 취소했습니다" : "새 심도 사진을 앱 보관함에 저장했습니다"
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", expected), object: message)
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 30), .completed)
        XCTAssertTrue(aperture.isEnabled)
        XCTAssertTrue(profile.isEnabled)
        XCTAssertEqual(app.staticTexts["editor.depth.apertureValue"].label, value)
        XCTAssertTrue(profile.buttons["Portrait"].isSelected)
    }
}
