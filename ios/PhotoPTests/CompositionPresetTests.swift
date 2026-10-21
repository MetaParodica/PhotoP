import CoreGraphics
import XCTest
@testable import PhotoP

final class CompositionPresetTests: XCTestCase {
    func testPresetsHaveUniqueIDsAndStayInsideFrame() {
        let ids = CompositionPreset.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertGreaterThanOrEqual(CompositionPreset.all.count, 10)
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        for preset in CompositionPreset.all {
            XCTAssertFalse(preset.title.isEmpty); XCTAssertFalse(preset.detail.isEmpty)
            XCTAssertFalse(preset.marks.isEmpty, preset.id)
            for mark in preset.marks {
                switch mark {
                case .zone(let rect): XCTAssertTrue(unit.contains(rect), "\(preset.id) zone")
                case .point(let center, let radius): XCTAssertTrue(unit.contains(center)); XCTAssertGreaterThan(radius, 0)
                case .line(let points, _): XCTAssertGreaterThanOrEqual(points.count, 2); XCTAssertTrue(points.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
                case .note(let text, let at, let target):
                    XCTAssertFalse(text.isEmpty); XCTAssertTrue(unit.contains(at))
                    if let target { XCTAssertTrue(unit.contains(target)) }
                }
            }
        }
        XCTAssertNil(CompositionPreset.preset("missing")); XCTAssertNil(CompositionPreset.preset(nil))
        XCTAssertEqual(CompositionPreset.preset("still-triangle")?.title, "삼각 구도")
    }

    func testOnlyPortraitPresetsExposeSubjectZone() {
        XCTAssertNotNil(CompositionPreset.preset("portrait-two-thirds")?.subject)
        XCTAssertNil(CompositionPreset.preset("still-triangle")?.subject)
        XCTAssertNil(CompositionPreset.preset("landscape-frame")?.subject)
    }

    func testSubjectFeedbackUsesJointBoundsAgainstZone() throws {
        let preset = try XCTUnwrap(CompositionPreset.preset("portrait-eye-line"))
        let zone = try XCTUnwrap(preset.subject)
        // Build a body whose bounds fill the zone; Vision coordinates use a bottom-left origin.
        func body(dx: CGFloat = 0, scale: CGFloat = 1, dy: CGFloat = 0) -> [String: CGPoint] {
            let height = zone.height * 0.85 * scale
            let top = zone.minY + zone.height * 0.08 * scale + dy
            let cx = zone.midX + dx
            return ["nose": .init(x: cx, y: 1 - top), "ls": .init(x: cx - 0.05, y: 1 - top - 0.1),
                    "rs": .init(x: cx + 0.05, y: 1 - top - 0.1), "la": .init(x: cx, y: 1 - top - height)]
        }
        XCTAssertEqual(preset.feedback(body: body()), "점선 영역과 맞습니다. 촬영하세요.")
        XCTAssertEqual(preset.feedback(body: body(dx: -0.2)), "인물을 점선 영역 오른쪽으로 옮기세요.")
        XCTAssertEqual(preset.feedback(body: body(dx: 0.2)), "인물을 점선 영역 왼쪽으로 옮기세요.")
        XCTAssertEqual(preset.feedback(body: body(scale: 0.4)), "인물을 더 크게: 가까이 가거나 줌을 올리세요.")
        XCTAssertEqual(preset.feedback(body: body(scale: 1.4, dy: -0.15)), "인물을 더 작게: 한 걸음 뒤로 가거나 줌을 낮추세요.")
        XCTAssertEqual(preset.feedback(body: body(dy: 0.15)), "인물을 화면 위쪽으로 옮기세요.")
        XCTAssertNil(preset.feedback(body: ["nose": .init(x: 0.5, y: 0.5)]))
        XCTAssertNil(CompositionPreset.preset("still-triangle")?.feedback(body: body()))
    }

    func testArrowStartsOutsideNoteAndEndsAtTarget() {
        let path = CompositionPresetOverlay.arrow(from: .init(x: 0, y: 0), to: .init(x: 100, y: 0), lines: 2)
        let bounds = path.boundingRect
        XCTAssertGreaterThanOrEqual(bounds.minX, 20, "Arrow must clear the note text")
        XCTAssertEqual(bounds.maxX, 100, accuracy: 0.5)
    }
}
