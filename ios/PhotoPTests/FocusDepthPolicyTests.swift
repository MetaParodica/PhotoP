import XCTest
#if canImport(PhotoP)
@testable import PhotoP
#else
@testable import PhotoPCameraPolicies
@testable import PhotoPImagePolicies
#endif

final class FocusDepthPolicyTests: XCTestCase {
    func testDistantFocusKeepsSmallNearForegroundOutsidePercentileRange() throws {
        var depth = [Float](repeating: 0.05, count: 10000) // 20 m focus.
        for i in 0..<100 { depth[i] = 1 } // 1% close foreground, at 1 m.
        let field = try XCTUnwrap(SoftwareDepthField(width: 100, height: 100, inverseDepth: depth, units: .inverseMetres))
        let bounds = try XCTUnwrap(field.bounds)
        let r = try XCTUnwrap(SoftwareDepthPolicy.radius(inverse: 1, focus: 0.05,
            span: Double(bounds.upper - bounds.lower), absolute: true, aperture: 2.8, longEdge: 4032))
        XCTAssertLessThan(r, -30)
        XCTAssertGreaterThan(try XCTUnwrap(SoftwareDepthPolicy.blurCoordinate(radius: r, longEdge: 4032)), 0.8)
        depth[0] = 100
        let outlier = try XCTUnwrap(SoftwareDepthField(width: 100, height: 100, inverseDepth: depth, units: .inverseMetres))
        XCTAssertEqual(outlier.bounds?.upper, 1)
    }
    func testSingleDepthSpikeCannotEnableBlurInAnOtherwiseFlatScene() throws {
        var depth = [Float](repeating: 1, count: 10000); depth[0] = 100
        let field = try XCTUnwrap(SoftwareDepthField(width: 100, height: 100, inverseDepth: depth, units: .relativeInverse))
        XCTAssertNil(field.bounds)
    }
    func testCircleOfConfusionLayeringResolvesNearFocusAndMaintainsBudget() throws {
        for quality in [8, 16] {
            let centers = SoftwareDepthPolicy.layerCenters(qualityPairs: quality)
            XCTAssertEqual(centers.count, quality + 1)
            XCTAssertEqual(centers.first, 0); XCTAssertEqual(centers.last, 1)
            let middle = centers.count / 2
            XCTAssertEqual(centers[middle], 0.5)
            XCTAssertLessThan(centers[middle + 1] - 0.5, centers.last! - centers[centers.count - 2])
            for (a, b) in zip(centers, centers.dropFirst()) { XCTAssertLessThan(a, b) }
        }
        XCTAssertEqual(SoftwareDepthPolicy.blurCoordinate(radius: 0, longEdge: 4032), 0.5)
        XCTAssertEqual(SoftwareDepthPolicy.blurCoordinate(radius: 48, longEdge: 4032), 0)
        XCTAssertEqual(SoftwareDepthPolicy.blurCoordinate(radius: -48, longEdge: 4032), 1)
        XCTAssertNil(SoftwareDepthPolicy.blurCoordinate(radius: .nan, longEdge: 4032))
    }
    func testMiddleGroundBlurAtDistantFocusDoesNotDependOnOtherSceneDepths() throws {
        func coordinate(span: Double, aperture: Double, edge: Int) throws -> Float {
            let r = try XCTUnwrap(SoftwareDepthPolicy.radius(inverse: 0.2, focus: 0.05, span: span,
                absolute: true, aperture: aperture, longEdge: edge)) // 5 m foreground, 20 m focus.
            return try XCTUnwrap(SoftwareDepthPolicy.blurCoordinate(radius: r, longEdge: edge))
        }
        let normal = try coordinate(span: 0.15, aperture: 2.8, edge: 4032)
        XCTAssertGreaterThan(normal, 0.55)
        XCTAssertEqual(normal, try coordinate(span: 10, aperture: 2.8, edge: 4032), accuracy: 0.000001)
        XCTAssertEqual(normal, try coordinate(span: 0.15, aperture: 2.8, edge: 8064), accuracy: 0.000001)
        XCTAssertGreaterThan(normal, try coordinate(span: 0.15, aperture: 8, edge: 4032))
    }
    func testOrdinaryTouchPreservesManualAndExposureLocks() {
        let action = FocusTouchPolicy.actions(scope: .both, focusSupported: true, exposureSupported: true,
            focusLocked: true, exposureLocked: true, explicitAFOn: false)
        XCTAssertFalse(action.focus); XCTAssertFalse(action.exposure)
    }
    func testAFOnOverridesFocusOnly() {
        let action = FocusTouchPolicy.actions(scope: .focus, focusSupported: true, exposureSupported: true,
            focusLocked: true, exposureLocked: true, explicitAFOn: true)
        XCTAssertTrue(action.focus); XCTAssertFalse(action.exposure)
    }
    func testExposureOnlyNeverMovesLens() {
        let action = FocusTouchPolicy.actions(scope: .exposure, focusSupported: true, exposureSupported: true,
            focusLocked: false, exposureLocked: false, explicitAFOn: false)
        XCTAssertFalse(action.focus); XCTAssertTrue(action.exposure)
    }
    func testUnsupportedFocusDoesNotInventAnAction() {
        let action = FocusTouchPolicy.actions(scope: .focus, focusSupported: false, exposureSupported: true,
            focusLocked: false, exposureLocked: false, explicitAFOn: true)
        XCTAssertFalse(action.focus); XCTAssertFalse(action.exposure)
    }
    func testAreaClampsAtAllCornersAndHonorsHardwareMinimum() throws {
        for x in [0.0, 1.0] { for y in [0.0, 1.0] {
            let rect = try XCTUnwrap(FocusArea.small.rect(x: x, y: y, minimumWidth: 0.2, minimumHeight: 0.3))
            XCTAssertEqual(rect.width, 0.2); XCTAssertEqual(rect.height, 0.3)
            XCTAssertGreaterThanOrEqual(rect.minX, 0); XCTAssertLessThanOrEqual(rect.maxX, 1)
            XCTAssertGreaterThanOrEqual(rect.minY, 0); XCTAssertLessThanOrEqual(rect.maxY, 1)
        } }
        XCTAssertNil(FocusArea.small.rect(x: .nan, y: 0, minimumWidth: 0.1, minimumHeight: 0.1))
        XCTAssertNil(FocusArea.small.rect(x: 0, y: 0, minimumWidth: 1.1, minimumHeight: 0.1))
    }
    func testTrackingAndSettledAreNotSharpnessGuarantees() {
        XCTAssertEqual(FocusPhase.resolve(manual: true, locked: true, adjusting: false, tracking: false), .manual)
        XCTAssertEqual(FocusPhase.resolve(manual: false, locked: false, adjusting: true, tracking: true), .tracking)
        XCTAssertEqual(FocusPhase.resolve(manual: false, locked: false, adjusting: false, tracking: false), .settledEstimate)
        XCTAssertFalse(CaptureWorkflowPolicy.depthAllowed(pro: true, long: false, video: false, raw: false, bracket: false, tracking: true))
        XCTAssertTrue(CaptureWorkflowPolicy.depthAllowed(pro: true, long: false, video: false, raw: false, bracket: false, tracking: false))
    }
    func testDepthFieldRejectsInvalidShapeAndAllInvalid() {
        XCTAssertNil(SoftwareDepthField(width: 3, height: 3, inverseDepth: [1], units: .relativeInverse))
        XCTAssertNil(SoftwareDepthField(width: 3, height: 3, inverseDepth: .init(repeating: .nan, count: 9), units: .relativeInverse))
    }
    func testInvalidDepthIsNotTreatedAsInfinity() throws {
        let field = try XCTUnwrap(SoftwareDepthField(width: 3, height: 3, inverseDepth: [0, .nan, -.infinity, -1, 1, 2, 3, 4, 5], units: .relativeInverse))
        XCTAssertEqual(Array(field.inverseDepth.prefix(4)), [0, 0, 0, 0])
        XCTAssertEqual(field.focusValue(x: 0.5, y: 0.5), 3)
        XCTAssertNil(field.focusValue(x: .nan, y: 0.5))
    }
    func testUniformDepthFailsConservatively() throws {
        let field = try XCTUnwrap(SoftwareDepthField(width: 3, height: 3, inverseDepth: .init(repeating: 2, count: 9), units: .inverseMetres))
        XCTAssertNil(field.bounds)
    }
    func testSignedCircleOfConfusionSeparatesNearAndFarAndKeepsPlaneSharp() throws {
        func radius(_ d: Double) throws -> Double {
            try XCTUnwrap(SoftwareDepthPolicy.radius(inverse: d, focus: 0.5, span: 1, absolute: true, aperture: 2.8, longEdge: 4000))
        }
        XCTAssertLessThan(try radius(1), 0); XCTAssertGreaterThan(try radius(0.2), 0)
        XCTAssertEqual(try radius(0.5), 0, accuracy: 0.00001)
    }
    func testApertureAndResolutionScalingUseRadiusNotDiameter() throws {
        func r(_ aperture: Double, _ edge: Int) throws -> Double {
            try XCTUnwrap(SoftwareDepthPolicy.radius(inverse: 0.4, focus: 0.5, span: 1, absolute: true, aperture: aperture, longEdge: edge))
        }
        XCTAssertEqual(try r(2.8, 2000), try r(5.6, 4000), accuracy: 0.00001)
        let lensFactor: Double = (0.05 * 0.05 * 2.0) / (2.8 * 1.95)
        let expected: Double = lensFactor * 0.1 * 4000.0 / 0.036 / 2.0
        XCTAssertEqual(try r(2.8, 4000), expected, accuracy: 0.00001)
    }
    func testRelativeDepthHasSeparateContractAndBoundedBlur() throws {
        let radius = try XCTUnwrap(SoftwareDepthPolicy.radius(inverse: 100, focus: 1, span: 1, absolute: false, aperture: 1.4, longEdge: 4000))
        XCTAssertEqual(radius, -48 * 4000 / 4032, accuracy: 0.0001)
        XCTAssertNil(SoftwareDepthPolicy.radius(inverse: .nan, focus: 1, span: 1, absolute: false, aperture: 2.8, longEdge: 4000))
        XCTAssertNil(SoftwareDepthPolicy.radius(inverse: 1, focus: 1, span: 0, absolute: false, aperture: 2.8, longEdge: 4000))
    }
    func testNaturalBudgetNeverSilentlyDownscales() {
        XCTAssertTrue(SoftwareDepthPolicy.supports(width: 4032, height: 3024))
        XCTAssertTrue(SoftwareDepthPolicy.supports(width: 8064, height: 6048))
        XCTAssertFalse(SoftwareDepthPolicy.supports(width: 8192, height: 8192))
        XCTAssertFalse(SoftwareDepthPolicy.supports(width: Int.max, height: 3))
        XCTAssertFalse(SoftwareDepthPolicy.supports(width: -1, height: 100))
    }
    func testPortraitModelGeometryKeepsAspectAndCropsPadding() throws {
        let portrait = try XCTUnwrap(DepthModelGeometry(sourceWidth: 3024, sourceHeight: 4032))
        XCTAssertEqual(portrait.width, 294); XCTAssertEqual(portrait.height, 392)
        XCTAssertEqual(portrait.x, 112); XCTAssertEqual(portrait.y, 0)
        XCTAssertEqual(Double(portrait.width) / Double(portrait.height), 0.75)
    }
    func testWideModelGeometryIsBoundedAndRejectsExtremeAspect() throws {
        let wide = try XCTUnwrap(DepthModelGeometry(sourceWidth: 4032, sourceHeight: 2268))
        XCTAssertEqual(wide.width, 518)
        XCTAssertLessThan(wide.height, 392); XCTAssertGreaterThan(wide.y, 0)
        XCTAssertLessThanOrEqual(wide.x + wide.width, 518); XCTAssertLessThanOrEqual(wide.y + wide.height, 392)
        XCTAssertNil(DepthModelGeometry(sourceWidth: 8192, sourceHeight: 1))
        XCTAssertNil(DepthModelGeometry(sourceWidth: -1, sourceHeight: 10))
    }
}
