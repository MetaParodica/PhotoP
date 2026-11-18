import XCTest

final class DepthEditorInteractionTests: XCTestCase {
    @MainActor func testSavingLocksApertureAndProfileUntilRealSaveCompletes() {
        checkSaveLock(cancel: false)
    }
    @MainActor func testCancellingSaveUnlocksApertureAndProfile() {
        checkSaveLock(cancel: true)
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
        XCTAssertTrue(profile.buttons["Portrait"].isSelected)
        let value = app.staticTexts["editor.depth.apertureValue"].label
        app.buttons["editor.depth.save"].tap()
        let cancelSave = app.buttons["editor.depth.cancel"]
        XCTAssertTrue(cancelSave.waitForExistence(timeout: 5))
        XCTAssertFalse(aperture.isEnabled)
        for button in profile.buttons.allElementsBoundByIndex { XCTAssertFalse(button.isEnabled) }
        XCTAssertFalse(app.switches["editor.depth.compare"].isEnabled)
        // Physical touches exercise the disabled controls without XCTest refusing
        // the action because their accessibility state correctly says disabled.
        profile.buttons["Classic"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        aperture.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: aperture.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)))
        XCTAssertEqual(app.staticTexts["editor.depth.apertureValue"].label, value)
        XCTAssertTrue(profile.buttons["Portrait"].isSelected)
        XCTAssertFalse(profile.buttons["Classic"].isSelected)
        if cancel { cancelSave.tap() }
        else { app.buttons["editor.review.releaseSave"].tap() }
        let message = app.staticTexts["editor.depth.message"]
        let expected = cancel ? "저장을 취소했습니다" : "새 심도 사진을 앱 보관함에 저장했습니다"
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", expected), object: message)
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 30), .completed)
        XCTAssertTrue(aperture.isEnabled)
        XCTAssertTrue(profile.buttons["Classic"].isEnabled)
        XCTAssertEqual(app.staticTexts["editor.depth.apertureValue"].label, value)
        XCTAssertTrue(profile.buttons["Portrait"].isSelected)
    }
}
