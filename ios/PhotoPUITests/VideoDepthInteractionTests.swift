import XCTest

final class VideoDepthInteractionTests: XCTestCase {
    @MainActor func testVideoDepthEditorUsesRealStoredMovieAndSelectableTracking() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-review", "--review-video-depth-editor"]
        app.launch(); defer { app.terminate() }
        let target = app.descendants(matching: .any)["video.depth.target"]
        let render = app.buttons["video.depth.render"]
        XCTAssertTrue(render.waitForExistence(timeout: 25))
        XCTAssertTrue(target.waitForExistence(timeout: 25))
        XCTAssertTrue(render.isEnabled, "The source thumbnail must be ready before rendering")
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
        // The initial progress message also mentions the original. Wait for an
        // actual terminal outcome, then bring the control back into the viewport.
        let finished = NSPredicate { _, _ in
            message.exists && (message.label.contains("취소했습니다.") || message.label.contains("유효한 프레임이 없습니다."))
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: finished, object: nil)], timeout: 60), .completed)
        for _ in 0..<3 where !render.isHittable { app.swipeUp() }
        for _ in 0..<4 where !render.isHittable { app.swipeDown() }
        XCTAssertTrue(render.isHittable)
        XCTAssertTrue(render.isEnabled)
        XCTAssertTrue(message.label.contains("원본"))
    }
    @MainActor func testTimelineKeyframesAndActualDepthFramePreview() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-review", "--review-video-depth-editor"]
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)["video.depth.target"].waitForExistence(timeout: 25))
        let disclosure = app.buttons["시간별 초점·f값 전환"]
        for _ in 0..<4 where !disclosure.isHittable { app.swipeUp() }
        disclosure.tap()
        let toggle = app.switches["video.depth.timeline"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5)); toggle.tap()
        let slider = app.sliders["video.depth.time"]
        reveal(slider,in: app)
        slider.adjust(toNormalizedSliderPosition: 0.7)
        let timeValue = app.staticTexts["video.depth.timeValue"]
        let sought = XCTNSPredicateExpectation(predicate: NSPredicate(format: "NOT label BEGINSWITH %@","현재 0.00초"),object: timeValue)
        XCTAssertEqual(XCTWaiter.wait(for: [sought],timeout: 3),.completed,"The scrubber must actually leave the initial frame")
        let set = app.buttons["video.depth.setKeyframe"]
        reveal(set,in: app); set.tap()
        let count = app.staticTexts["video.depth.keyframeCount"]
        let added = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@","키프레임 2개"),object: count)
        XCTAssertEqual(XCTWaiter.wait(for: [added],timeout: 3),.completed)
        XCTAssertEqual(count.label,"키프레임 2개")
        let preview = app.buttons["video.depth.preview"]
        reveal(preview,in: app); preview.tap()
        let message = app.staticTexts["video.depth.message"]
        let complete = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@","전환 미리보기"),object: message)
        XCTAssertEqual(XCTWaiter.wait(for: [complete],timeout: 45),.completed)
        let remove = app.buttons["삭제"].firstMatch
        reveal(remove,in: app); remove.tap()
        XCTAssertEqual(app.staticTexts["video.depth.keyframeCount"].label,"키프레임 1개")
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "video-focus-timeline"; attachment.lifetime = .keepAlways; add(attachment)
    }

    @MainActor private func reveal(_ element: XCUIElement,in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        let scroll = app.scrollViews.firstMatch
        // A partly clipped slider can report hittable while its thumb is under
        // the home indicator. Put the entire control inside the content viewport.
        for _ in 0..<6 {
            let viewport = scroll.frame.insetBy(dx: 0,dy: 32)
            let top = max(viewport.minY,app.navigationBars.firstMatch.frame.maxY+12)
            let bottom = min(viewport.maxY,app.frame.maxY-40)
            let frame = element.frame
            if frame.minY >= top, frame.maxY <= bottom, element.isHittable { return }
            if frame.maxY > bottom { scroll.swipeUp() } else { scroll.swipeDown() }
        }
        XCTFail("Control is not fully visible: \(element.identifier) \(element.frame)")
    }

}
