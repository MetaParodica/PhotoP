import XCTest
#if canImport(PhotoPCameraPolicies)
@testable import PhotoPCameraPolicies
#else
@testable import PhotoP
#endif

final class CaptureWorkflowTests: XCTestCase {
    func testSelectedBracketAndRenderedPhotoRouteToTheirOwnOriginal() {
        let a = URL(fileURLWithPath: "/fixture/a.jpg"), b = URL(fileURLWithPath: "/fixture/b.jpg")
        let effect = URL(fileURLWithPath: "/fixture/effect.jpg")
        XCTAssertEqual(CaptureReviewRouting.original(for: b, originals: [a, b], renderedSources: [:]), b)
        XCTAssertEqual(CaptureReviewRouting.original(for: effect, originals: [a, b], renderedSources: [effect: b]), b)
        XCTAssertNil(CaptureReviewRouting.original(for: effect, originals: [a, b], renderedSources: [:]))
    }
    func testRawAndUnrelatedPhotosCannotBeImplicitlyOpenedInSDREditor() {
        let raw = URL(fileURLWithPath: "/fixture/raw.DNG"), unknown = URL(fileURLWithPath: "/fixture/unknown.jpg")
        XCTAssertNil(CaptureReviewRouting.original(for: raw, originals: [raw], renderedSources: [:]))
        XCTAssertNil(CaptureReviewRouting.original(for: unknown, originals: [raw], renderedSources: [:]))
    }
    func testLongDurationPrecedesEveryOtherControl() {
        for pro in [true, false] {
            let tools = CaptureWorkflowPolicy.controls(pro: pro, long: true, video: false)
            XCTAssertEqual(tools.first, .longExposure)
            XCTAssertEqual(Set(tools).count, tools.count)
            XCTAssertFalse(tools.contains(.aperture))
        }
    }
    func testApertureIsOnlyInProAndNeverInventsAVideoDepthMode() {
        XCTAssertTrue(CaptureWorkflowPolicy.controls(pro: true, long: false, video: false).contains(.aperture))
        XCTAssertEqual(CaptureWorkflowPolicy.controls(pro: false, long: false, video: false), [.ev])
        let video = CaptureWorkflowPolicy.controls(pro: true, long: true, video: true)
        XCTAssertFalse(video.contains(.aperture)); XCTAssertFalse(video.contains(.longExposure))
        XCTAssertEqual(video.last, .video)
        XCTAssertEqual(Set(CameraTool.allCases.map(\.id)).count, 12)
    }
    func testDurationAcceptsBoundedCustomSecondsAndLocaleDecimal() {
        XCTAssertEqual(CaptureWorkflowPolicy.duration(from: "1"), 1)
        XCTAssertEqual(CaptureWorkflowPolicy.duration(from: "300"), 300)
        XCTAssertEqual(CaptureWorkflowPolicy.duration(from: " 12.5\n"), 12.5)
        XCTAssertEqual(CaptureWorkflowPolicy.duration(from: "12,5"), 12.5)
        XCTAssertEqual(CaptureWorkflowPolicy.duration(from: "1.25"), 1.25)
    }
    func testInvalidDurationNeverReplacesThePreviousSetting() {
        for value in ["", " ", "abc", "nan", "inf", "-1", "0", "0.99", "300.1", "1,2,3"] {
            XCTAssertNil(CaptureWorkflowPolicy.duration(from: value), value)
        }
    }
    func testDurationReadoutReflectsCustomValue() {
        XCTAssertEqual(CaptureWorkflowPolicy.durationLabel(4), "4 s")
        XCTAssertEqual(CaptureWorkflowPolicy.durationLabel(12.5), "12.5 s")
        XCTAssertEqual(CaptureWorkflowPolicy.durationLabel(1.25), "1.25 s")
        XCTAssertEqual(CaptureWorkflowPolicy.durationLabel(.nan), "—")
    }
    func testDepthGatingRejectsEveryIncompatibleMode() {
        XCTAssertTrue(CaptureWorkflowPolicy.depthAllowed(pro: true, long: false, video: false, raw: false, bracket: false))
        XCTAssertFalse(CaptureWorkflowPolicy.depthAllowed(pro: false, long: false, video: false, raw: false, bracket: false))
        XCTAssertFalse(CaptureWorkflowPolicy.depthAllowed(pro: true, long: true, video: false, raw: false, bracket: false))
        XCTAssertFalse(CaptureWorkflowPolicy.depthAllowed(pro: true, long: false, video: true, raw: false, bracket: false))
        XCTAssertFalse(CaptureWorkflowPolicy.depthAllowed(pro: true, long: false, video: false, raw: true, bracket: false))
        XCTAssertFalse(CaptureWorkflowPolicy.depthAllowed(pro: true, long: false, video: false, raw: false, bracket: true))
    }
    func testDepthFocusUsesValidMedianNotNaNsOrIsolatedOutliers() {
        XCTAssertEqual(DepthBlurPolicy.focusDistance([1, 1.1, 1.2, 30, .nan, .infinity, 0]), 1.2)
        XCTAssertNil(DepthBlurPolicy.focusDistance([.nan, 1, 2, 0, -1]))
    }
    func testDepthMaskKeepsTheFocusPlaneAndInvalidDepthSharp() {
        XCTAssertEqual(DepthBlurPolicy.mask(depth: 2, focus: 2), 0)
        XCTAssertEqual(DepthBlurPolicy.mask(depth: 2.1, focus: 2), 0)
        XCTAssertGreaterThan(DepthBlurPolicy.mask(depth: 8, focus: 2), 200)
        XCTAssertGreaterThan(DepthBlurPolicy.mask(depth: 0.5, focus: 2), 200)
        XCTAssertEqual(DepthBlurPolicy.mask(depth: .nan, focus: 2), 0)
        XCTAssertEqual(DepthBlurPolicy.mask(depth: 0, focus: 2), 0)
        XCTAssertEqual(DepthBlurPolicy.mask(depth: 2, focus: .infinity), 0)
    }
    func testApertureOnlyControlsSoftwareBlurStrengthAndBounds() throws {
        let small = try XCTUnwrap(DepthBlurPolicy.radius(aperture: 1.4, longEdge: 4000))
        let large = try XCTUnwrap(DepthBlurPolicy.radius(aperture: 16, longEdge: 4000))
        XCTAssertGreaterThan(small, large)
        XCTAssertLessThanOrEqual(small, 80)
        XCTAssertNil(DepthBlurPolicy.radius(aperture: .nan, longEdge: 4000))
        XCTAssertNil(DepthBlurPolicy.radius(aperture: 1, longEdge: 4000))
        XCTAssertNil(DepthBlurPolicy.radius(aperture: 2.8, longEdge: 0))
    }
}
