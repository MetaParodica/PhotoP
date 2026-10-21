import CoreGraphics
import XCTest
@testable import PhotoP

final class PhotoShootingTests: XCTestCase {
    func testFlashIsOnlyRequestedForSupportedProcessedSingleCaptures() {
        let all: [FlashSetting] = [.off, .auto, .on]
        XCTAssertEqual(PhotoFlashPolicy.resolve(.on, supported: all, raw: .processed, bracket: false), .on)
        XCTAssertEqual(PhotoFlashPolicy.resolve(.auto, supported: all, raw: .processed, bracket: true), .off)
        XCTAssertEqual(PhotoFlashPolicy.resolve(.on, supported: all, raw: .bayer, bracket: false), .off)
        XCTAssertEqual(PhotoFlashPolicy.resolve(.on, supported: [.off, .auto], raw: .processed, bracket: false), .off)
        XCTAssertEqual(PhotoFlashPolicy.next(after: .off, supported: all), .auto)
        XCTAssertEqual(PhotoFlashPolicy.next(after: .on, supported: all), .off)
        XCTAssertEqual(PhotoFlashPolicy.next(after: .off, supported: [.off]), .off, "No flash hardware must not cycle to a fake mode")
        XCTAssertEqual(PhotoFlashPolicy.next(after: .off, supported: [.off, .on]), .on)
    }

    func testSelfTimerAndFramingCycle() {
        XCTAssertEqual(SelfTimer.off.next, .three); XCTAssertEqual(SelfTimer.three.next, .ten); XCTAssertEqual(SelfTimer.ten.next, .off)
        XCTAssertEqual(FramingAspect.native.next, .square); XCTAssertEqual(FramingAspect.wide.next, .native)
    }

    func testFramingRectsStayInsideImageAndKeepAspect() {
        let image = CGRect(x: 0, y: 0, width: 300, height: 400)
        XCTAssertEqual(FramingAspect.native.rect(in: image), image)
        let square = FramingAspect.square.rect(in: image)
        XCTAssertEqual(square, CGRect(x: 0, y: 50, width: 300, height: 300))
        let wide = FramingAspect.wide.rect(in: image)
        XCTAssertEqual(wide.height, 400); XCTAssertEqual(wide.width, 225, accuracy: 0.001)
        XCTAssertEqual(wide.midX, 150, accuracy: 0.001)
        XCTAssertTrue(image.contains(wide)); XCTAssertEqual(FramingAspect.square.rect(in: .zero), .zero)
    }

    func testZoomClampsToDeviceAndDigitalCeiling() {
        XCTAssertEqual(ZoomPolicy.clamp(0.5, maxAvailable: 10), 1)
        XCTAssertEqual(ZoomPolicy.clamp(8, maxAvailable: 10), ZoomPolicy.digitalCeiling)
        XCTAssertEqual(ZoomPolicy.clamp(3, maxAvailable: 2), 2)
        XCTAssertEqual(ZoomPolicy.clamp(.nan, maxAvailable: 4), 1)
        XCTAssertEqual(ZoomPolicy.range(maxAvailable: .infinity), 1...1)
        XCTAssertEqual(ZoomPolicy.range(maxAvailable: 0.5), 1...1)
    }

    func testLensEquivalentComesFromFieldOfView() throws {
        // A lens with half the tangent of the wide field of view reads as 2x.
        let wide = 70.0
        let tele = 2 * atan(tan(wide * .pi / 360) / 2) * 180 / .pi
        XCTAssertEqual(try XCTUnwrap(ZoomPolicy.equivalent(fieldOfView: tele, wideFieldOfView: wide)), 2)
        XCTAssertEqual(try XCTUnwrap(ZoomPolicy.equivalent(fieldOfView: wide, wideFieldOfView: wide)), 1)
        let ultra = 2 * atan(tan(wide * .pi / 360) * 2) * 180 / .pi
        XCTAssertEqual(try XCTUnwrap(ZoomPolicy.equivalent(fieldOfView: ultra, wideFieldOfView: wide)), 0.5)
        XCTAssertNil(ZoomPolicy.equivalent(fieldOfView: 0, wideFieldOfView: wide))
        XCTAssertNil(ZoomPolicy.equivalent(fieldOfView: 60, wideFieldOfView: 180))
        XCTAssertEqual(ZoomPolicy.label(0.5), "0.5×"); XCTAssertEqual(ZoomPolicy.label(1), "1×"); XCTAssertEqual(ZoomPolicy.label(2.04), "2×")
    }

    func testRawIsBlockedWithDigitalZoom() {
        XCTAssertNil(ZoomPolicy.rawReason(zoom: 1, raw: .bayer))
        XCTAssertNotNil(ZoomPolicy.rawReason(zoom: 2, raw: .appleProRAW))
        XCTAssertNil(ZoomPolicy.rawReason(zoom: 3, raw: .processed))
    }

    func testFullBodyGuideLeavesHeadroomAndPutsFeetNearBottom() throws {
        let guide = PersonGuide(framing: .full, position: .center)
        let p = try XCTUnwrap(guide.placements().first)
        XCTAssertEqual(p.top, 0.06, accuracy: 0.001)
        XCTAssertEqual(p.top + PersonGuide.ankleY * p.scale, 0.95, accuracy: 0.001)
        XCTAssertEqual(p.centerX, 0.5)
        // Shoulders are roughly a quarter of body height in a 3:4 frame.
        let shoulderToHeight = (p.shoulderWidth * 3) / (p.scale * 4)
        XCTAssertGreaterThan(shoulderToHeight, 0.18); XCTAssertLessThan(shoulderToHeight, 0.3)
        XCTAssertTrue(PersonGuide().placements().isEmpty)
    }

    func testCroppedFramingsPlaceEyesInUpperPartAndHonourPosition() throws {
        for framing in [PersonFraming.waist, .chest, .face] {
            let p = try XCTUnwrap(PersonGuide(framing: framing, position: .left).placements().first)
            XCTAssertEqual(p.top + framing.cut * p.scale, 1, accuracy: 0.001, "\(framing) must cut at the frame bottom")
            XCTAssertLessThan(p.eyeY, 0.45, "\(framing) eyes should sit in the upper part")
            XCTAssertEqual(p.centerX, 1.0 / 3, accuracy: 0.001)
            XCTAssertFalse(framing.tip.isEmpty)
        }
    }

    func testGroupsSpreadAroundChosenPositionInsideFrame() {
        let pair = PersonGuide(framing: .full, position: .center, people: 2).placements()
        XCTAssertEqual(pair.count, 2)
        XCTAssertEqual((pair[0].centerX + pair[1].centerX) / 2, 0.5, accuracy: 0.001)
        XCTAssertLessThan(pair[0].centerX, pair[1].centerX)
        let crowd = PersonGuide(framing: .full, position: .right, people: 5).placements()
        XCTAssertEqual(crowd.count, 3)
        XCTAssertTrue(crowd.allSatisfy { $0.centerX >= 0.1 && $0.centerX <= 0.9 })
    }

    func testFeedbackComparesDetectedShouldersWithTarget() throws {
        let guide = PersonGuide(framing: .full, position: .center)
        let target = try XCTUnwrap(guide.placements().first)
        let half = target.shoulderWidth / 2
        // Vision coordinates: bottom-left origin.
        func body(x: CGFloat, width: CGFloat, noseY: CGFloat) -> [String: CGPoint] {
            ["ls": .init(x: x - width / 2, y: 0.8), "rs": .init(x: x + width / 2, y: 0.8), "nose": .init(x: x, y: 1 - noseY)]
        }
        XCTAssertEqual(guide.feedback(body: body(x: 0.5, width: 2 * half, noseY: target.noseY)), "가이드와 맞습니다. 촬영하세요.")
        XCTAssertEqual(guide.feedback(body: body(x: 0.3, width: 2 * half, noseY: target.noseY)), "인물을 화면 오른쪽으로 옮기세요.")
        XCTAssertEqual(guide.feedback(body: body(x: 0.7, width: 2 * half, noseY: target.noseY)), "인물을 화면 왼쪽으로 옮기세요.")
        XCTAssertEqual(guide.feedback(body: body(x: 0.5, width: half, noseY: target.noseY)), "인물을 더 크게: 가까이 가거나 줌을 올리세요.")
        XCTAssertEqual(guide.feedback(body: body(x: 0.5, width: 3 * half, noseY: target.noseY)), "인물을 더 작게: 한 걸음 뒤로 가거나 줌을 낮추세요.")
        XCTAssertEqual(guide.feedback(body: body(x: 0.5, width: 2 * half, noseY: target.noseY + 0.2)), "인물을 화면 위쪽으로 옮기세요.")
        XCTAssertNil(guide.feedback(body: ["nose": .init(x: 0.5, y: 0.5)]))
        XCTAssertNil(PersonGuide().feedback(body: body(x: 0.5, width: 0.2, noseY: 0.1)))
    }

    func testCloseUpFeedbackIgnoresShouldersOutsideFrame() throws {
        let guide = PersonGuide(framing: .face, position: .center)
        let target = try XCTUnwrap(guide.placements().first)
        XCTAssertGreaterThan(target.shoulderWidth, 0.9)
        let body: [String: CGPoint] = ["ls": .init(x: 0.1, y: 0.2), "rs": .init(x: 0.9, y: 0.2), "nose": .init(x: 0.5, y: 1 - target.noseY)]
        XCTAssertEqual(guide.feedback(body: body), "가이드와 맞습니다. 촬영하세요.")
    }
}
