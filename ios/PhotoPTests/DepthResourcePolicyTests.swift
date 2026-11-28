import XCTest
#if canImport(PhotoP)
@testable import PhotoP
#else
@testable import PhotoPImagePolicies
#endif

final class DepthResourcePolicyTests: XCTestCase {
    private func metadata() -> NativeDepthMetadata {
        .init(mapWidth: 3, mapHeight: 3, quality: .high, filtered: true, absoluteAccuracy: true,
              originalPixelFormat: 0x66646570, appliedEXIFOrientation: 6, hasCameraCalibration: true,
              intrinsicMatrix: [100, 0, 0, 0, 100, 0, 1, 1, 1],
              intrinsicReferenceWidth: 3, intrinsicReferenceHeight: 3)
    }

    func testNativePhotoDoesNotAutomaticallyStartAIPreviewButExplicitAIStillDoes() {
        XCTAssertFalse(PhotoDepthPolicy.startsAIPreview(source: .automatic, nativeAvailable: true))
        XCTAssertFalse(PhotoDepthPolicy.startsAIPreview(source: .measured, nativeAvailable: true))
        XCTAssertFalse(PhotoDepthPolicy.startsAIPreview(source: .measured, nativeAvailable: false))
        XCTAssertTrue(PhotoDepthPolicy.startsAIPreview(source: .ai, nativeAvailable: true))
        XCTAssertTrue(PhotoDepthPolicy.startsAIPreview(source: .ai, nativeAvailable: false))
        XCTAssertTrue(PhotoDepthPolicy.startsAIPreview(source: .automatic, nativeAvailable: false))
    }

    func testNativeHolesNeverAuthorizeImplicitAIAndMissingDepthKeepsFallback() {
        XCTAssertFalse(PhotoDepthPolicy.infersDepth(source: .automatic, nativePresent: true))
        XCTAssertFalse(PhotoDepthPolicy.infersDepth(source: .measured, nativePresent: false))
        XCTAssertTrue(PhotoDepthPolicy.infersDepth(source: .automatic, nativePresent: false))
        XCTAssertTrue(PhotoDepthPolicy.infersDepth(source: .ai, nativePresent: false))
        XCTAssertTrue(PhotoDepthPolicy.infersDepth(source: .ai, nativePresent: true))
    }

    func testDepthPreviewBoundsRepeatedWorkAndSuspendsAtCriticalPressure() {
        let normal = DepthPreviewWorkload(thermalLevel: 0, lowPower: false)
        let low = DepthPreviewWorkload(thermalLevel: 0, lowPower: true)
        let serious = DepthPreviewWorkload(thermalLevel: 2, lowPower: false)
        XCTAssertEqual(normal, DepthPreviewWorkload(thermalLevel: 1, lowPower: false))
        XCTAssertLessThanOrEqual(normal.maximumDimension, 720)
        XCTAssertLessThanOrEqual(normal.framesPerSecond, 30)
        XCTAssertGreaterThanOrEqual(normal.analysisInterval, 0.5)
        XCTAssertLessThanOrEqual(low.maximumDimension, normal.maximumDimension)
        XCTAssertLessThan(low.framesPerSecond, normal.framesPerSecond)
        XCTAssertGreaterThanOrEqual(low.analysisInterval, normal.analysisInterval)
        XCTAssertLessThan(serious.framesPerSecond, normal.framesPerSecond)
        // A stationary subject must not periodically lose depth solely because
        // the configured analysis interval exceeds the field's expiry.
        for budget in [normal, low, serious] { XCTAssertLessThan(budget.analysisInterval, 0.75) }
        for level in [3, 4, -1] {
            let stopped = DepthPreviewWorkload(thermalLevel: level, lowPower: false)
            XCTAssertFalse(stopped.allowsDepth)
            XCTAssertFalse(stopped.analysisInterval.isFinite)
        }
    }

    func testNativeMetadataSurvivesCodingResizeInvalidationAndManualCorrection() throws {
        let info = metadata()
        XCTAssertTrue(info.valid)
        XCTAssertEqual(try JSONDecoder().decode(NativeDepthMetadata.self, from: JSONEncoder().encode(info)), info)
        let field = try XCTUnwrap(SoftwareDepthField(width: 3, height: 3,
            inverseDepth: [1, 1, 1, 1, 2, 2, 2, 2, 2], units: .inverseMetres, nativeMetadata: info))
        XCTAssertEqual(DepthGrid.resized(field, width: 6, height: 6)?.nativeMetadata, info)
        XCTAssertEqual(field.invalidating(where: { $0 == 0 })?.nativeMetadata, info)
        XCTAssertEqual(field.replacingDepthPreservingBounds([2, 2, 2, 2, 2, 1, 1, 1, 1])?.nativeMetadata, info)
        // The summary describes the original attachment, not the resized grid.
        XCTAssertEqual(DepthGrid.resized(field, width: 6, height: 6)?.nativeMetadata?.mapWidth, 3)
    }

    func testInvalidCalibrationAndUnitMismatchAreRejected() throws {
        let info = metadata()
        XCTAssertNil(SoftwareDepthField(width: 3, height: 3, inverseDepth: .init(repeating: 1, count: 9),
            units: .relativeInverse, nativeMetadata: info))
        var broken = info; broken.intrinsicMatrix = [1, 2]
        XCTAssertFalse(broken.valid)
        broken = info; broken.intrinsicMatrix = [Float](repeating: .nan, count: 9)
        XCTAssertFalse(broken.valid)
        broken = info; broken.intrinsicReferenceWidth = .infinity
        XCTAssertFalse(broken.valid)
        broken = info; broken.intrinsicMatrix = nil
        XCTAssertFalse(broken.valid)
        let invalidOrientation = NativeDepthMetadata(mapWidth: 3, mapHeight: 3, quality: .unknown,
            filtered: false, absoluteAccuracy: false, originalPixelFormat: 0,
            appliedEXIFOrientation: 9, hasCameraCalibration: false)
        XCTAssertFalse(invalidOrientation.valid)
        XCTAssertNil(SoftwareDepthField(width: 3, height: 3, inverseDepth: .init(repeating: 1, count: 9),
            units: .relativeInverse, nativeMetadata: invalidOrientation))
    }

    func testOlderDepthWithoutMetadataRemainsReadable() throws {
        let field = try XCTUnwrap(SoftwareDepthField(width: 3, height: 3,
            inverseDepth: .init(repeating: 1, count: 9), units: .relativeInverse))
        XCTAssertNil(field.nativeMetadata)
    }
}
