import XCTest
#if canImport(PhotoP)
@testable import PhotoP
#else
@testable import PhotoPImagePolicies
#endif

final class NativeDepthQualityPolicyTests: XCTestCase {
    private func base() throws -> SoftwareDepthField {
        let info = NativeDepthMetadata(mapWidth: 5, mapHeight: 5, quality: .high, filtered: true,
            absoluteAccuracy: true, originalPixelFormat: 0x66646570, appliedEXIFOrientation: 1, hasCameraCalibration: false)
        let values: [Float] = (0..<25).map { $0 % 5 == 2 ? 2 : 0.2 }
        return try XCTUnwrap(SoftwareDepthField(width: 5, height: 5, inverseDepth: values, units: .inverseMetres, nativeMetadata: info))
    }

    func testAllEXIFTransformsUseKnownCoordinatesAndRoundTrip() throws {
        let expected: [(Double,Double)] = [(0.2,0.3),(0.8,0.3),(0.8,0.7),(0.2,0.7),
            (0.3,0.2),(0.7,0.2),(0.7,0.8),(0.3,0.8)]
        for o in UInt32(1)...8 {
            let g = DepthGeometry(colorWidth: 4000, colorHeight: 3000, depthWidth: 400, depthHeight: 300, orientation: o)
            let p = try XCTUnwrap(g.oriented(x: 0.2,y: 0.3))
            XCTAssertEqual(Double(p.x), expected[Int(o)-1].0, accuracy: 1e-8)
            XCTAssertEqual(Double(p.y), expected[Int(o)-1].1, accuracy: 1e-8)
            let original = try XCTUnwrap(g.original(x: Double(p.x),y: Double(p.y)))
            XCTAssertEqual(Double(original.x),0.2,accuracy: 1e-8); XCTAssertEqual(Double(original.y),0.3,accuracy: 1e-8)
            XCTAssertEqual(g.orientedColorWidth, o >= 5 ? 3000 : 4000)
            XCTAssertTrue(g.matchesOrientedColor(width: g.orientedColorWidth,height: g.orientedColorHeight))
        }
    }

    func testCropMirrorAndOutsideCropAreExplicit() throws {
        let g = DepthGeometry(colorWidth: 400, colorHeight: 300, depthWidth: 40, depthHeight: 30, orientation: 1)
        let crop = CGRect(x: 0.25,y: 0.25,width: 0.5,height: 0.5)
        let p = try XCTUnwrap(g.display(x: 0.35,y: 0.5,crop: crop,mirrored: true))
        XCTAssertEqual(Double(p.x),0.8,accuracy: 1e-8); XCTAssertEqual(Double(p.y),0.5,accuracy: 1e-8)
        XCTAssertNil(g.display(x: 0.1,y: 0.5,crop: crop,mirrored: false))
        XCTAssertNil(g.display(x: .nan,y: 0.5,crop: crop,mirrored: false))
        XCTAssertNil(g.display(x: 0.5,y: 0.5,crop: .zero,mirrored: false))
    }

    func testMismatchedUnknownAndOversizedGeometryIsRejected() {
        XCTAssertFalse(DepthGeometry(colorWidth: 400, colorHeight: 300, depthWidth: 30, depthHeight: 40, orientation: 1).valid)
        XCTAssertFalse(DepthGeometry(colorWidth: 400, colorHeight: 300, depthWidth: 40, depthHeight: 30, orientation: 9).valid)
        XCTAssertFalse(DepthGeometry(colorWidth: Int.max, colorHeight: 300, depthWidth: 40, depthHeight: 30, orientation: 1).valid)
        XCTAssertNil(DepthRefinementPolicy.outputSize(colorWidth: Int.max,colorHeight: 300,depthWidth: 40,depthHeight: 30))
    }

    func testThinTouchedSurfaceWinsOverMajorityBackground() throws {
        let field = try base()
        // Center column has three supported local samples; background has six.
        XCTAssertEqual(field.focusValue(x: 0.5,y: 0.5),2)
        XCTAssertEqual(field.focusValue(x: 0.1,y: 0.5),0.2)
        var spike = field.inverseDepth; spike[12] = 100
        let changed = try XCTUnwrap(SoftwareDepthField(width: 5,height: 5,inverseDepth: spike,units: .inverseMetres))
        XCTAssertNotEqual(changed.focusValue(x: 0.5,y: 0.5),100)
        XCTAssertNil(field.focusValue(x: .nan,y: 0.5))
    }

    func testRelativeFocusClusterToleratesPositiveScaleAndOffset() throws {
        let source = try base()
        let relative = try XCTUnwrap(SoftwareDepthField(width: 5,height: 5,
            inverseDepth: source.inverseDepth.map { $0*7+100 },units: .relativeInverse))
        XCTAssertEqual(try XCTUnwrap(relative.focusValue(x: 0.5,y: 0.5)),114,accuracy: 0.0001)
    }

    func testRefinementSizeIsBoundedAndNeverDownsamplesNativeData() throws {
        let p = try XCTUnwrap(DepthRefinementPolicy.outputSize(colorWidth: 8064,colorHeight: 6048,depthWidth: 768,depthHeight: 576))
        XCTAssertLessThanOrEqual(max(p.width,p.height),1536); XCTAssertLessThanOrEqual(p.width*p.height,2_097_152)
        XCTAssertNil(DepthRefinementPolicy.outputSize(colorWidth: 800,colorHeight: 600,depthWidth: 800,depthHeight: 600))
        let square = try XCTUnwrap(DepthRefinementPolicy.outputSize(colorWidth: 4000,colorHeight: 4000,depthWidth: 512,depthHeight: 512))
        XCTAssertLessThanOrEqual(square.width*square.height,2_097_152)
    }

    func testRefinementPreservesNativeScaleMetadataAndConstantSurfaceAnchors() throws {
        let field = try base()
        let out = try XCTUnwrap(DepthRefinementPolicy.constrained(base: field,
            candidate: [Float](repeating: 50,count: 100),width: 10,height: 10))
        XCTAssertEqual(out.inverseDepth[0],0.2) // no foreground in this local native neighborhood
        XCTAssertLessThanOrEqual(try XCTUnwrap(out.inverseDepth.max()),2)
        XCTAssertEqual(out.bounds?.lower,field.bounds?.lower); XCTAssertEqual(out.bounds?.upper,field.bounds?.upper)
        let info = try XCTUnwrap(out.nativeMetadata)
        XCTAssertEqual(info.mapWidth,5); XCTAssertEqual(info.refinement?.outputWidth,10)
        XCTAssertEqual(info.refinement?.methodID,NativeDepthRefinement.method)
        let restoredInfo = try JSONDecoder().decode(NativeDepthMetadata.self,from: JSONEncoder().encode(info))
        let restored = try XCTUnwrap(SoftwareDepthField(width: 10,height: 10,inverseDepth: out.inverseDepth,
            units: out.units,nativeMetadata: restoredInfo))
        XCTAssertEqual(restored.bounds?.upper,field.bounds?.upper)
        XCTAssertNil(DepthRefinementPolicy.constrained(base: out,candidate: .init(repeating: 1,count: 100),width: 10,height: 10))
    }

    func testMissingDepthStaysMissingAndNonfiniteCandidatesFallBack() throws {
        let source = try base(); var values = source.inverseDepth; values[0] = 0
        let field = try XCTUnwrap(SoftwareDepthField(width: 5,height: 5,inverseDepth: values,units: source.units,nativeMetadata: source.nativeMetadata))
        let out = try XCTUnwrap(DepthRefinementPolicy.constrained(base: field,
            candidate: .init(repeating: .nan,count: 100),width: 10,height: 10))
        XCTAssertEqual(out.inverseDepth[0],0); XCTAssertEqual(out.inverseDepth[11],0)
        XCTAssertEqual(out.inverseDepth[4],2)
        XCTAssertTrue(out.inverseDepth.allSatisfy { $0.isFinite && $0 >= 0 })
        XCTAssertNil(DepthRefinementPolicy.constrained(base: field,candidate: [1],width: 10,height: 10))
        XCTAssertNil(DepthRefinementPolicy.constrained(base: field,candidate: .init(repeating: 1,count: 100),width: 10,height: 10,isCancelled: { true }))
    }

    func testGeometryMetadataRejectsMismatchedMapAndKeepsLegacyOptionalFields() throws {
        var info = try XCTUnwrap(try base().nativeMetadata)
        info.geometry = .init(colorWidth: 400,colorHeight: 300,depthWidth: 40,depthHeight: 30,orientation: 1)
        XCTAssertFalse(info.valid)
        info.geometry = nil
        let restored = try JSONDecoder().decode(NativeDepthMetadata.self,from: JSONEncoder().encode(info))
        XCTAssertNil(restored.geometry); XCTAssertNil(restored.refinement); XCTAssertTrue(restored.valid)
    }

    func testDisplayGridKeepsOriginalScaleWhenSmallSurfaceIsNotSampled() throws {
        var values = [Float](repeating: 0.2,count: 10000)
        for i in 0..<10 { values[i] = 2 }
        let field = try XCTUnwrap(SoftwareDepthField(width: 100,height: 100,inverseDepth: values,units: .relativeInverse))
        let small = try XCTUnwrap(DepthGrid.resized(field,width: 3,height: 3))
        XCTAssertTrue(small.inverseDepth.allSatisfy { $0 == 0.2 })
        XCTAssertEqual(small.bounds?.lower,field.bounds?.lower)
        XCTAssertEqual(small.bounds?.upper,field.bounds?.upper)
    }
}
