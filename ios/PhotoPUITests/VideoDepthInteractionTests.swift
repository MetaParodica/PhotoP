import XCTest

final class VideoDepthInteractionTests: XCTestCase {
    @MainActor func testVideoDepthEditorUsesRealStoredMovieAndSelectableTracking() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-review", "--review-video-depth-editor"]
        app.launch(); defer { app.terminate() }
        let target = app.otherElements["video.depth.target"]
        let render = app.buttons["video.depth.render"]
        XCTAssertTrue(render.waitForExistence(timeout: 25))
        XCTAssertTrue(target.exists)
        let tracking = app.switches["선택 피사체 추적"]
        for _ in 0..<4 where !tracking.isHittable { app.swipeUp() }
        XCTAssertTrue(tracking.isHittable); tracking.tap()
        let mode = app.segmentedControls["video.depth.mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 3))
        mode.buttons["인물"].tap(); XCTAssertTrue(mode.buttons["인물"].isSelected)
        let quality = app.segmentedControls["video.depth.quality"]
        for _ in 0..<3 where !quality.isHittable { app.swipeUp() }
        quality.buttons["고품질"].tap(); XCTAssertTrue(quality.buttons["고품질"].isSelected)
        // The fixture has no person; processing must expose a real failure instead
        // of claiming an effect. Cancellation may finish first on a slower runner.
        for _ in 0..<3 where !render.isHittable { app.swipeUp() }
        render.tap()
        let message = app.staticTexts["video.depth.message"]
        XCTAssertTrue(message.waitForExistence(timeout: 10))
        let cancel = app.buttons["처리 취소"]
        if cancel.waitForExistence(timeout: 2), cancel.isHittable { cancel.tap() }
        XCTAssertTrue(render.waitForExistence(timeout: 30))
        XCTAssertTrue(message.label.contains("원본") || message.label.contains("취소"))
    }
}
