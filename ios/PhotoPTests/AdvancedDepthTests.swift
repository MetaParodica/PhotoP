import XCTest
#if canImport(PhotoP)
@testable import PhotoP
#else
@testable import PhotoPImagePolicies
#endif

final class AdvancedDepthTests: XCTestCase {
    func testSpatialPSFIsSharedAndBoundedAtEdges() {
        for profile in DepthLensProfile.allCases {
            let taps = DepthLensKernel.taps(profile: profile, aperture: 8)
            var edgeMoment = 0.0, centerMoment = 0.0
            for t in taps {
                let o = DepthLensKernel.offset(t, x: 0, y: 0, width: 101, height: 101, profile: profile)
                XCTAssertLessThanOrEqual(o.x * o.x + o.y * o.y, 1.000001)
                edgeMoment += (o.x * o.x + o.y * o.y) * t.weight
                centerMoment += (t.x * t.x + t.y * t.y) * t.weight
            }
            if profile.catEye > 0 { XCTAssertLessThan(edgeMoment, centerMoment) }
            else { XCTAssertEqual(edgeMoment, centerMoment, accuracy: 1e-10) }
        }
    }
    func testVirtualFocalLengthChangesCoCWithoutChangingFocusOrLimits() throws {
        for profile in DepthLensProfile.allCases {
            let r = try XCTUnwrap(SoftwareDepthPolicy.radius(inverse: 0.2, focus: 0.5, span: 1,
                absolute: true, aperture: 2.8, longEdge: 4032, focalLengthMM: profile.focalLengthMM))
            XCTAssertGreaterThan(r, 0); XCTAssertLessThanOrEqual(r, 48)
            XCTAssertEqual(SoftwareDepthPolicy.radius(inverse: 0.5, focus: 0.5, span: 1,
                absolute: true, aperture: 2.8, longEdge: 4032, focalLengthMM: profile.focalLengthMM), 0)
        }
        XCTAssertEqual(DepthLensProfile.legacy.map(\.rawValue), ["natural", "portrait", "classic"])
        XCTAssertEqual(DepthLensProfile.allCases.count, 9)
    }
}
