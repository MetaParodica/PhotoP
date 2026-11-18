import XCTest
#if canImport(PhotoPImagePolicies)
@testable import PhotoPImagePolicies
#else
@testable import PhotoP
#endif

final class ExposureFusionPolicyTests: XCTestCase {
    private func pattern(_ w: Int = 48) -> [Float] {
        (0..<(w * w)).map { i in Float(0.12 + Double((i * 37 + i / w * 19) % 97) / 180) }
    }
    func testRegistrationNormalizesExposureAndFindsTranslation() throws {
        let w = 48, reference = pattern()
        var shifted = reference
        for y in 0..<w { for x in 0..<w {
            shifted[y * w + x] = reference[min(w - 1, max(0, y + 1)) * w + min(w - 1, max(0, x - 2))] * 0.65
        } }
        let result = try ExposureFusionPolicy().register(reference: reference, candidate: shifted, width: w, height: w)
        XCTAssertEqual(result.x, 2); XCTAssertEqual(result.y, -1)
        XCTAssertEqual(result.logExposureOffset, log2(0.65), accuracy: 0.0001)
        XCTAssertLessThan(result.residual, 0.0001)
    }
    func testMovingPatchIsRejectedAsSuspectedGhost() {
        let reference = pattern()
        var moving = reference
        for y in 12..<28 { for x in 12..<28 { moving[y * 48 + x] = 0.9 } }
        XCTAssertThrowsError(try ExposureFusionPolicy().register(reference: reference, candidate: moving, width: 48, height: 48)) {
            XCTAssertEqual($0 as? ExposureFusionFailure, .ghost)
        }
    }
    func testExcessResidualIsRejectedIndependentlyOfGhostGate() {
        let reference = pattern()
        let noisy = reference.enumerated().map { i, v in min(0.95, v + (i % 2 == 0 ? 0.06 : -0.06)) }
        var policy = ExposureFusionPolicy(); policy.maximumResidual = 0.001; policy.ghostThreshold = 10
        XCTAssertThrowsError(try policy.register(reference: reference, candidate: noisy, width: 48, height: 48)) {
            XCTAssertEqual($0 as? ExposureFusionFailure, .alignment)
        }
    }
    func testUniformClippedAndMalformedInputsCannotInventAlignment() {
        let policy = ExposureFusionPolicy(), reference = pattern()
        for candidate in [[Float](repeating: 1, count: 48 * 48), [Float](repeating: .nan, count: 48 * 48), []] {
            XCTAssertThrowsError(try policy.register(reference: reference, candidate: candidate, width: 48, height: 48))
        }
        XCTAssertThrowsError(try policy.register(reference: Array(repeating: 0.5, count: 48 * 48), candidate: reference, width: 48, height: 48))
    }
    func testOnlyFiniteOrderedThreeFrameBiasesAndValidWeightsAreAccepted() throws {
        let policy = ExposureFusionPolicy(); try policy.validateBiases([-1, 0, 1])
        for biases in [[], [0, 1], [0, 0, 1], [1, 0, -1], [-3, 0, 3], [-1, .nan, 1]] {
            XCTAssertThrowsError(try policy.validateBiases(biases))
        }
        var bad = policy; bad.weights.contrast = .infinity
        XCTAssertThrowsError(try bad.register(reference: pattern(), candidate: pattern(), width: 48, height: 48))
        bad = policy; bad.maximumGhostFraction = .nan
        XCTAssertThrowsError(try bad.register(reference: pattern(), candidate: pattern(), width: 48, height: 48))
    }
}
