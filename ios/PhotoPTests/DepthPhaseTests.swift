import XCTest
#if canImport(PhotoP)
@testable import PhotoP
#else
@testable import PhotoPImagePolicies
#endif

final class DepthPhaseTests: XCTestCase {
    func testLensPSFConservesDCAndIsCentered() {
        for p in DepthLensProfile.allCases {
            let taps = DepthLensKernel.taps(profile: p, aperture: 8)
            XCTAssertEqual(taps.reduce(0) { $0 + $1.weight }, 1, accuracy: 0.000001)
            XCTAssertEqual(taps.reduce(0) { $0 + $1.x * $1.weight }, 0, accuracy: 0.000001)
            XCTAssertEqual(taps.reduce(0) { $0 + $1.y * $1.weight }, 0, accuracy: 0.000001)
            XCTAssertTrue(taps.allSatisfy { $0.x * $0.x + $0.y * $0.y <= 1.000001 })
        }
    }
    func testCPUReferencePreservesConstantImage() throws {
        let image = [SIMD3<Float>](repeating: SIMD3(0.2, 0.4, 0.8), count: 16 * 16)
        for p in DepthLensProfile.allCases {
            let blurred = try XCTUnwrap(DepthLensKernel.reference(image, width: 16, height: 16, radius: 5, profile: p))
            for c in blurred { XCTAssertEqual(c.x, 0.2, accuracy: 0.00001); XCTAssertEqual(c.y, 0.4, accuracy: 0.00001); XCTAssertEqual(c.z, 0.8, accuracy: 0.00001) }
        }
    }
    func testProfilesDifferBeyondColorAndKeepHighlightEnergy() throws {
        var image = [SIMD3<Float>](repeating: .zero, count: 33 * 33); image[16 * 33 + 16] = SIMD3(repeating: 1)
        let a = try XCTUnwrap(DepthLensKernel.reference(image, width: 33, height: 33, radius: 6, profile: .natural, aperture: 8))
        let b = try XCTUnwrap(DepthLensKernel.reference(image, width: 33, height: 33, radius: 6, profile: .portrait, aperture: 8))
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(a.reduce(Float(0)) { $0 + $1.x }, 1, accuracy: 0.0001)
        XCTAssertEqual(b.reduce(Float(0)) { $0 + $1.x }, 1, accuracy: 0.0001)
    }
    func testFusionCalibratesMetricScaleAndOnlyFillsHoles() throws {
        let prediction = (0..<100).map { Float($0 + 1) / 100 }
        var measured = prediction.map { $0 * 2 + 0.5 }; measured[45] = 0
        let sensor = try XCTUnwrap(SoftwareDepthField(width: 10, height: 10, inverseDepth: measured, units: .inverseMetres))
        let ai = try XCTUnwrap(SoftwareDepthField(width: 10, height: 10, inverseDepth: prediction, units: .relativeInverse))
        let output = DepthFusionCore.fuse(measured: sensor, predicted: ai)
        XCTAssertNotNil(output.calibration); XCTAssertEqual(output.filled, 1); XCTAssertEqual(output.field.units, .inverseMetres)
        XCTAssertEqual(output.field.inverseDepth[45], prediction[45] * 2 + 0.5, accuracy: 0.0001)
        XCTAssertEqual(output.field.inverseDepth[20], measured[20])
    }
    func testUnrelatedOrUniformDepthCannotBecomeMetric() {
        XCTAssertNil(DepthFusionCore.calibrate(predicted: Array(repeating: 1, count: 100), measured: (0..<100).map(Float.init)))
        XCTAssertNil(DepthFusionCore.calibrate(predicted: (0..<100).map { Float($0 + 1) }, measured: (0..<100).map { Float(101 - $0) }))
    }
    func testForegroundColorUnmixAndTinyAlphaBounded() {
        let f = DepthMatteCore.unmix(image: SIMD3(0.5, 0.25, 0.25), background: SIMD3(0, 0.5, 0.5), alpha: 0.5)
        XCTAssertEqual(f, SIMD3(1, 0, 0))
        let tiny = DepthMatteCore.unmix(image: SIMD3(0.2, 0.3, 0.4), background: SIMD3(repeating: 1), alpha: 0.001)
        XCTAssertEqual(tiny, SIMD3(0.2, 0.3, 0.4))
    }
    func testMatteDoesNotInventAlphaOutsideBounds() throws {
        let alpha: [Float] = (0..<81).map { $0 % 9 < 4 ? 0 : 1 }
        let rgb = (0..<81).map { SIMD3<Float>(repeating: alpha[$0]) }
        let value = try XCTUnwrap(DepthMatteCore.refine(alpha: alpha, color: rgb, width: 9, height: 9))
        XCTAssertTrue(value.alpha.allSatisfy { $0 >= 0 && $0 <= 1 })
        XCTAssertEqual(value.alpha[4 * 9], 0); XCTAssertEqual(value.alpha[4 * 9 + 8], 1)
        XCTAssertNil(DepthMatteCore.refine(alpha: [.nan], color: [], width: 1, height: 1))
        let restored = try XCTUnwrap(DepthMatteSurface.decode(value.encoded(), width: 9, height: 9))
        XCTAssertEqual(restored.alpha, value.alpha); XCTAssertEqual(restored.foreground, value.foreground)
        XCTAssertNil(DepthMatteSurface.decode(Data(), width: 9, height: 9))
    }
    func testTemporalStateRejectsLateFramesMotionAndNewGeneration() throws {
        let field = try XCTUnwrap(SoftwareDepthField(width: 10, height: 10, inverseDepth: (0..<100).map { Float($0 + 1) }, units: .relativeInverse))
        var state = DepthTemporalState(); let luma = [Float](repeating: 0.5, count: 100)
        XCTAssertNotNil(state.update(field, luma: luma, time: 1, generation: 7))
        XCTAssertNotNil(state.current(luma: luma, time: 1.2, generation: 7))
        XCTAssertNil(state.current(luma: luma, time: 2, generation: 7))
        XCTAssertNil(state.current(luma: luma, time: 1.2, generation: 8))
        XCTAssertNil(state.current(luma: Array(repeating: 1, count: 100), time: 1.2, generation: 7))
        state.reset(); XCTAssertNil(state.current(luma: luma, time: 1.2, generation: 7))
    }
    func testMovingFreshDepthDoesNotBlendWithAnOldPlane() throws {
        var state = DepthTemporalState()
        let a = try XCTUnwrap(SoftwareDepthField(width: 10, height: 10, inverseDepth: Array(repeating: 1, count: 100), units: .inverseMetres))
        let b = try XCTUnwrap(SoftwareDepthField(width: 10, height: 10, inverseDepth: Array(repeating: 2, count: 100), units: .inverseMetres))
        _ = state.update(a, luma: Array(repeating: 0, count: 100), time: 1, generation: 1)
        let result = try XCTUnwrap(state.update(b, luma: Array(repeating: 1, count: 100), time: 1.1, generation: 1))
        XCTAssertEqual(result.inverseDepth, b.inverseDepth)
    }
}
