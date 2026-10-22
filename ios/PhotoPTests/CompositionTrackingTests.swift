import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(PhotoPCompositionCore)
@testable import PhotoPCompositionCore
#else
@testable import PhotoP
#endif

final class CompositionTrackingTests: XCTestCase {
    private func person(_ x: CGFloat = 0.2, _ y: CGFloat = 0.2, width: CGFloat = 0.2,
                        height: CGFloat = 0.5, face: CGPoint? = nil) -> DetectedPerson {
        DetectedPerson(bounds: CGRect(x: x, y: y, width: width, height: height), faceCenter: face, confidence: 0.9)
    }
    private func snapshot(_ time: Double, _ people: [DetectedPerson], epoch: UInt64 = 1) -> CompositionSnapshot {
        CompositionSnapshot(generatedAt: time, width: 480, height: 640, bodies: [], polygons: [], advice: "fixture",
                            epoch: epoch, people: people)
    }

    func testSingleAndMultiplePeopleGetUniqueIDs() {
        var tracker = CompositionSubjectTracker()
        let one = tracker.update([person()], at: 1)
        XCTAssertEqual(one.count, 1)
        let multiple = tracker.update([person(), person(0.65)], at: 1.2)
        XCTAssertEqual(multiple.count, 2)
        XCTAssertEqual(Set(multiple.map(\.id)).count, 2)
        XCTAssertEqual(one.first?.id, multiple.first?.id)
    }

    func testReorderedDetectionsAndSmallMotionKeepIdentityAndSmoothJitter() throws {
        var tracker = CompositionSubjectTracker()
        let first = tracker.update([person(), person(0.65)], at: 1)
        let next = tracker.update([person(0.64), person(0.21)], at: 1.2)
        XCTAssertEqual(first.map(\.id), next.map(\.id))
        let x = try XCTUnwrap(next.first?.bounds.minX)
        XCTAssertGreaterThan(x, 0.2); XCTAssertLessThan(x, 0.21)
        XCTAssertEqual(next.last?.bounds.minX ?? 0, 0.6435, accuracy: 0.0001)
    }

    func testMissingPersonDoesNotLeaveAGhostAndCanRecoverBriefOcclusion() {
        var tracker = CompositionSubjectTracker()
        let first = tracker.update([person()], at: 1)
        XCTAssertTrue(tracker.update([], at: 1.2).isEmpty)
        XCTAssertEqual(tracker.update([person(0.22)], at: 1.4).first?.id, first.first?.id)
        XCTAssertNotEqual(tracker.update([person(0.22)], at: 2.4).first?.id, first.first?.id)
    }

    func testFastMotionIsNotSmoothedIntoOldLocation() throws {
        var tracker = CompositionSubjectTracker()
        let first = tracker.update([person()], at: 1)
        let moved = try XCTUnwrap(tracker.update([person(0.3)], at: 1.2).first)
        XCTAssertEqual(first.first?.id, moved.id)
        XCTAssertEqual(moved.bounds.minX, 0.29, accuracy: 0.0001)
        let far = tracker.update([person(0.7)], at: 1.4)
        XCTAssertNotEqual(far.first?.id, moved.id)
        XCTAssertEqual(far.first?.bounds.minX, 0.7)
    }

    func testInvalidDetectionsAndDuplicateTimesAreRejected() {
        var tracker = CompositionSubjectTracker()
        let bad = DetectedPerson(bounds: .zero, faceCenter: nil, confidence: 1)
        let weak = DetectedPerson(bounds: person().bounds, faceCenter: nil, confidence: 0.1)
        let outsideFace = person(face: CGPoint(x: 0.9, y: 0.9))
        XCTAssertTrue(tracker.update([bad, weak, outsideFace, person(.nan)], at: 1).isEmpty)
        XCTAssertTrue(tracker.update([person()], at: .nan).isEmpty)
        XCTAssertTrue(tracker.update([person()], at: 1).isEmpty)
        XCTAssertTrue(tracker.update([person()], at: 0.9).isEmpty)
        XCTAssertEqual(tracker.update([person()], at: 1.2).count, 1)
    }

    func testTapSelectsSmallestContainingSubjectNotNearestUnrelatedOne() {
        var tracker = CompositionSubjectTracker()
        let subjects = tracker.update([person(0.1, 0.1, width: 0.7, height: 0.8), person()], at: 1)
        XCTAssertEqual(CompositionSubjectTracker.subject(at: CGPoint(x: 0.3, y: 0.3), in: subjects), subjects.last?.id)
        XCTAssertNil(CompositionSubjectTracker.subject(at: CGPoint(x: 0.95, y: 0.95), in: subjects))
    }

    func testUserSelectionSurvivesOrderAndDoesNotJumpToAnotherPersonWhenLost() throws {
        var engine = CompositionGuideEngine()
        let initial = try XCTUnwrap(engine.update(snapshot(1, [person(), person(0.65)]), target: .automatic, now: 1))
        let id = try XCTUnwrap(initial.0.subjects.last?.id)
        engine.select(id)
        let selected = try XCTUnwrap(engine.update(snapshot(1.2, [person(0.64), person()]), target: .automatic, now: 1.2))
        XCTAssertEqual(selected.0.selectedID, id)
        let missing = try XCTUnwrap(engine.update(snapshot(1.4, [person()]), target: .automatic, now: 1.4))
        XCTAssertEqual(missing.0.selectedID, id); XCTAssertNil(missing.0.subject)
        XCTAssertNil(missing.0.targetPoint); XCTAssertFalse(missing.0.aligned)
        XCTAssertTrue(missing.0.advice.contains("다시 탭"))
        engine.select(nil)
        let automatic = try XCTUnwrap(engine.update(snapshot(1.6, [person()]), target: .automatic, now: 1.6))
        XCTAssertNotEqual(automatic.0.selectedID, id); XCTAssertNotNil(automatic.0.subject)
    }

    func testAutomaticSubjectDoesNotSwitchDuringOneMissedDetection() throws {
        var engine = CompositionGuideEngine()
        let first = try XCTUnwrap(engine.update(snapshot(1, [person(), person(0.65, width: 0.1)]), target: .automatic, now: 1))
        let missing = try XCTUnwrap(engine.update(snapshot(1.2, [person(0.65, width: 0.1)]), target: .automatic, now: 1.2))
        XCTAssertEqual(missing.0.selectedID, first.0.selectedID); XCTAssertNil(missing.0.subject)
        let recovered = try XCTUnwrap(engine.update(snapshot(1.4, [person(), person(0.65, width: 0.1)]), target: .automatic, now: 1.4))
        XCTAssertEqual(recovered.0.subject?.id, first.0.selectedID)
    }

    func testChangingTargetRespectsExplicitSubjectSelection() throws {
        var engine = CompositionGuideEngine()
        let first = try XCTUnwrap(engine.update(snapshot(1, [person(), person(0.65)]), target: .left, now: 1))
        let id = try XCTUnwrap(first.0.subjects.last?.id)
        engine.select(id)
        let next = try XCTUnwrap(engine.update(snapshot(1.2, [person(), person(0.65)]), target: .right, now: 1.2))
        XCTAssertEqual(next.0.selectedID, id)
        XCTAssertEqual(next.0.targetPoint?.x ?? 0, 2.0 / 3, accuracy: 0.001)
        XCTAssertFalse(next.0.aligned)
    }

    func testTargetUsesFaceCenterAndOnlyDescribesScreenDirection() throws {
        var engine = CompositionGuideEngine()
        let p = person(0.55, 0.2, face: CGPoint(x: 0.65, y: 0.3))
        let result = try XCTUnwrap(engine.update(snapshot(1, [p]), target: .left, now: 1))
        let point = try XCTUnwrap(result.0.targetPoint)
        XCTAssertEqual(point.x, 1.0 / 3, accuracy: 0.001)
        XCTAssertEqual(point.y, 1.0 / 3, accuracy: 0.001)
        XCTAssertTrue(result.0.advice.contains("화면 속 얼굴 중심"))
        XCTAssertTrue(result.0.advice.contains("왼쪽"))
        XCTAssertFalse(result.0.advice.contains("카메라를"))
    }

    func testAutomaticTargetDoesNotOscillateAcrossCenter() throws {
        var engine = CompositionGuideEngine()
        let first = try XCTUnwrap(engine.update(snapshot(1, [person(0.39)]), target: .automatic, now: 1))
        let moved = try XCTUnwrap(engine.update(snapshot(1.2, [person(0.42)]), target: .automatic, now: 1.2))
        XCTAssertEqual(first.0.targetPoint?.x ?? 0, 1.0 / 3, accuracy: 0.001)
        XCTAssertEqual(moved.0.targetPoint?.x ?? 0, 1.0 / 3, accuracy: 0.001)
    }

    func testTargetBoxNeverCropsObservedFullBody() throws {
        var engine = CompositionGuideEngine()
        let frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        for i in 0..<3 {
            let height: CGFloat = i == 2 ? 0.99 : 0.9
            let p = person(0.01, 0.005, width: 0.98, height: height, face: CGPoint(x: 0.3, y: 0.1))
            let t = Double(i) + 1
            let result = try XCTUnwrap(engine.update(snapshot(t, [p]), target: .right, now: t))
            let box = try XCTUnwrap(result.0.targetBounds)
            XCTAssertTrue(frame.insetBy(dx: -0.0001, dy: -0.0001).contains(box))
            XCTAssertEqual(box.size, p.bounds.size)
            XCTAssertFalse(result.0.aligned)
            XCTAssertTrue(result.0.advice.contains("어렵습니다"))
        }
    }

    func testStaleFutureOutOfOrderAndEpochChangesCannotReuseSelection() throws {
        var engine = CompositionGuideEngine()
        let first = try XCTUnwrap(engine.update(snapshot(1, [person()]), target: .left, now: 1))
        engine.select(try XCTUnwrap(first.0.selectedID))
        XCTAssertNil(engine.update(snapshot(1.2, [person()]), target: .left, now: 2))
        XCTAssertNil(engine.update(snapshot(3, [person()]), target: .left, now: 2))
        XCTAssertNil(engine.update(snapshot(0.8, [person()]), target: .left, now: 1))
        let rotated = try XCTUnwrap(engine.update(snapshot(1.4, [], epoch: 2), target: .left, now: 1.4))
        XCTAssertNil(rotated.0.selectedID); XCTAssertFalse(rotated.0.aligned)
        XCTAssertFalse(first.0.isFresh(at: 1.7)); XCTAssertFalse(first.0.isFresh(at: 0.9))
    }

    func testAlignmentRequiresStableHoldAndUsesHysteresis() {
        var alignment = CompositionAlignment()
        for time in [1.0, 1.2, 1.4] { XCTAssertFalse(alignment.update(error: 0.03, at: time)) }
        XCTAssertFalse(alignment.aligned)
        XCTAssertTrue(alignment.update(error: 0.03, at: 1.61)); XCTAssertTrue(alignment.aligned)
        XCTAssertFalse(alignment.update(error: 0.06, at: 1.8)); XCTAssertTrue(alignment.aligned)
        XCTAssertFalse(alignment.update(error: 0.08, at: 2)); XCTAssertFalse(alignment.aligned)
    }

    func testAlignmentDoesNotHapticRepeatedlyAndMissingFramesResetHold() {
        var alignment = CompositionAlignment()
        var pulses = 0
        for i in 0..<20 { if alignment.update(error: 0, at: 1 + Double(i) * 0.2) { pulses += 1 } }
        XCTAssertEqual(pulses, 1)
        XCTAssertFalse(alignment.update(error: nil, at: 5)); XCTAssertFalse(alignment.aligned)
        XCTAssertFalse(alignment.update(error: 0, at: 5.2))
        XCTAssertFalse(alignment.update(error: 0, at: 6.2), "A one second inference gap cannot complete the hold")
        XCTAssertFalse(alignment.aligned)
        XCTAssertFalse(alignment.update(error: .nan, at: 6.4))
    }

    func testHapticCooldownSurvivesSelectionReset() {
        var alignment = CompositionAlignment()
        var pulses = 0
        for i in 0..<5 { if alignment.update(error: 0, at: 1 + Double(i) * 0.2) { pulses += 1 } }
        XCTAssertEqual(pulses, 1)
        alignment.reset()
        for i in 0..<5 { if alignment.update(error: 0, at: 2 + Double(i) * 0.2) { pulses += 1 } }
        XCTAssertTrue(alignment.aligned); XCTAssertEqual(pulses, 1)
    }

    func testPortraitLandscapeFitFillAndDeliveredMirrorRoundTrip() throws {
        // Mirrored input is already reflected in the detected point; drawing and
        // hit-testing must not apply another mirror. Rotation is in the pixels.
        for source in [CGSize(width: 480, height: 640), CGSize(width: 640, height: 480)] {
            for viewport in [CGSize(width: 300, height: 400), CGSize(width: 700, height: 280)] {
                for fill in [true, false] {
                    let rect = GuideGeometry.imageRect(image: source, viewport: viewport, fill: fill)
                    for mirror in [true, false] {
                        let point = CGPoint(x: mirror ? 0.7 : 0.3, y: 0.4)
                        let displayed = GuideGeometry.point(point, in: rect, vision: false)
                        let restored = try XCTUnwrap(GuideGeometry.normalizedPoint(displayed, in: rect))
                        XCTAssertEqual(restored.x, point.x, accuracy: 0.0001)
                        XCTAssertEqual(restored.y, point.y, accuracy: 0.0001)
                    }
                }
            }
        }
        XCTAssertNil(GuideGeometry.normalizedPoint(.zero, in: CGRect(x: 20, y: 20, width: 100, height: 100)))
        XCTAssertNil(GuideGeometry.normalizedPoint(.zero, in: .zero))
    }

    #if !canImport(PhotoPCompositionCore)
    func testTrackingHasIndependentAdaptiveBudget() {
        XCTAssertEqual(PreviewBudget(thermal: .nominal, lowPower: false).compositionInterval, 0.2)
        XCTAssertEqual(PreviewBudget(thermal: .nominal, lowPower: true).compositionInterval, 0.4)
        XCTAssertEqual(PreviewBudget(thermal: .serious, lowPower: false).compositionInterval, 0.4)
        XCTAssertFalse(PreviewBudget(thermal: .critical, lowPower: false).compositionInterval.isFinite)
    }
    #endif
}
