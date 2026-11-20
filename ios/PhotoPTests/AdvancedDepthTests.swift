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
    func testMatteColorLineImprovesKnownFractionalBoundaryAndKeepsSeeds() throws {
        let w = 17, h = 17, f = SIMD3<Float>(0.9, 0.15, 0.1), b = SIMD3<Float>(0.05, 0.4, 0.6)
        let truth: [Float] = (0..<(w*h)).map { i in min(1, max(0, Float(i % w - 6) / 4)) }
        let prior = truth.map { $0 > 0 && $0 < 1 ? $0 * 0.6 + 0.1 : $0 }
        let color = truth.map { f * $0 + b * (1 - $0) }
        let surface = try XCTUnwrap(DepthMatteCore.refine(alpha: prior, color: color, width: w, height: h))
        var before: Float = 0, after: Float = 0
        for i in truth.indices {
            if truth[i] == 0 || truth[i] == 1 { XCTAssertEqual(surface.alpha[i], truth[i]) }
            else { before += abs(prior[i] - truth[i]); after += abs(surface.alpha[i] - truth[i]) }
        }
        XCTAssertLessThan(after, before * 0.35, "Fractional RGB mixture ground truth, not a real-hair quality claim")
        print("SYNTHETIC matte boundary MAE before=\(before / Float(h*3)) after=\(after / Float(h*3))")
    }
    func testMatteDoesNotInventStructureWithoutContrastingSeeds() throws {
        let color = [SIMD3<Float>](repeating: SIMD3(repeating: 0.4), count: 81)
        let prior = [Float](repeating: 0.5, count: 81)
        let result = try XCTUnwrap(DepthMatteCore.refine(alpha: prior, color: color, width: 9, height: 9))
        XCTAssertEqual(result.alpha, prior)
    }

    func testRegisteredTemporalDepthReducesAlternatingNoiseAndRejectsCut() throws {
        let w = 16, h = 16, luma = [Float](repeating: 0.5, count: 256)
        let truth = (0..<256).map { Float($0 % w) / 20 + 0.2 }
        var state = DepthTemporalState(), before: Float = 0, after: Float = 0
        for frame in 0..<30 {
            let noisy = truth.enumerated().map { i, v in v + (i % 2 == frame % 2 ? 0.018 : -0.018) }
            let next = try XCTUnwrap(SoftwareDepthField(width: w, height: h, inverseDepth: noisy, units: .relativeInverse))
            if frame > 0 { XCTAssertTrue(state.alignHistory(backwardFlow: .init(repeating: .zero, count: 256), currentLuma: luma)) }
            let output = try XCTUnwrap(state.update(next, luma: luma, time: Double(frame)/30, generation: 1, requireRegistration: true))
            if frame > 3 { for i in truth.indices { before += abs(noisy[i]-truth[i]); after += abs(output.inverseDepth[i]-truth[i]) } }
        }
        XCTAssertLessThan(after, before * 0.8)
        print("SYNTHETIC temporal depth MAE ratio=\(after / before)")
        let cutLuma = [Float](repeating: 0.9, count: 256)
        XCTAssertFalse(state.alignHistory(backwardFlow: .init(repeating: .zero, count: 256), currentLuma: cutLuma))
        let cut = try XCTUnwrap(SoftwareDepthField(width: w, height: h, inverseDepth: truth, units: .relativeInverse))
        XCTAssertEqual(state.update(cut, luma: cutLuma, time: 1.1, generation: 1, requireRegistration: true)?.inverseDepth, truth)
    }
    func testRegistrationMustBeRenewedAndOcclusionIsNotAveraged() throws {
        let truth = (0..<100).map { Float($0) / 100 + 0.1 }
        let old = try XCTUnwrap(SoftwareDepthField(width: 10, height: 10, inverseDepth: truth, units: .inverseMetres))
        let new = try XCTUnwrap(SoftwareDepthField(width: 10, height: 10, inverseDepth: truth.map { $0 + 0.01 }, units: .inverseMetres))
        let luma = [Float](repeating: 0.5, count: 100)
        var state = DepthTemporalState()
        _ = state.update(old, luma: luma, time: 0, generation: 1, requireRegistration: true)
        XCTAssertEqual(state.update(new, luma: luma, time: 0.1, generation: 1, requireRegistration: true)?.inverseDepth, new.inverseDepth)
        XCTAssertTrue(state.alignHistory(backwardFlow: .init(repeating: .zero, count: 100), currentLuma: luma))
        var disocclusion = truth; disocclusion[45] = 3
        let next = try XCTUnwrap(SoftwareDepthField(width: 10, height: 10, inverseDepth: disocclusion, units: .inverseMetres))
        let output = try XCTUnwrap(state.update(next, luma: luma, time: 0.2, generation: 1, requireRegistration: true))
        XCTAssertEqual(output.inverseDepth[45], 3)
        XCTAssertEqual(state.update(new, luma: luma, time: 0.3, generation: 1, requireRegistration: true)?.inverseDepth, new.inverseDepth)
    }

}
