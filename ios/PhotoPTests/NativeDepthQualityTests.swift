import XCTest
import CoreImage
import CoreVideo
import ImageIO
import Metal
import UniformTypeIdentifiers
@testable import PhotoP

final class NativeDepthQualityTests: XCTestCase {
    private func fixture(vertical: Bool = false) throws -> (CIImage, SoftwareDepthField) {
        let w = 256, h = 192, fw = 16, fh = 12
        var pixels = [UInt8](repeating: 255,count: w*h*4)
        for y in 0..<h { for x in 0..<w {
            let near = vertical ? y < 102 : x < 134
            pixels[(y*w+x)*4] = near ? 230 : 20
            pixels[(y*w+x)*4+1] = near ? 20 : 230
            pixels[(y*w+x)*4+2] = 30
        } }
        let color = CIImage(cgImage: try SDRImage(rgba: Data(pixels),width: w,height: h).cgImage())
        let info = NativeDepthMetadata(mapWidth: fw,mapHeight: fh,quality: .high,filtered: true,
            absoluteAccuracy: true,originalPixelFormat: kCVPixelFormatType_DepthFloat32,
            appliedEXIFOrientation: 1,hasCameraCalibration: false)
        let values: [Float] = (0..<(fw*fh)).map { i in (vertical ? i/fw < fh/2 : i%fw < fw/2) ? 1 : 0.2 }
        let field = try XCTUnwrap(SoftwareDepthField(width: fw,height: fh,inverseDepth: values,units: .inverseMetres,nativeMetadata: info))
        return (color,field)
    }

    func testGuidedDepthMovesEdgeTowardColorAndKeepsNativeConstantSurfaces() throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal unavailable") }
        let (color,field) = try fixture()
        let refined = try NativeDepthRefiner().refine(field,color: color)
        XCTAssertEqual(refined.width,256); XCTAssertEqual(refined.height,192)
        XCTAssertEqual(refined.nativeMetadata?.refinement?.methodID,NativeDepthRefinement.method)
        XCTAssertGreaterThan(refined.inverseDepth[96*256+131],0.7)
        XCTAssertEqual(refined.inverseDepth[96*256+32],1,accuracy: 0.00001)
        XCTAssertEqual(refined.inverseDepth[96*256+224],0.2,accuracy: 0.00001)
        XCTAssertEqual(refined.bounds?.lower,field.bounds?.lower); XCTAssertEqual(refined.bounds?.upper,field.bounds?.upper)
    }

    func testGuidanceAndReadbackHaveTopLeftRowsWithoutVerticalFlip() throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal unavailable") }
        let (color,field) = try fixture(vertical: true)
        let refined = try NativeDepthRefiner().refine(field,color: color)
        XCTAssertGreaterThan(refined.inverseDepth[99*256+128],0.7)
        XCTAssertEqual(refined.inverseDepth[24*256+128],1,accuracy: 0.00001)
        XCTAssertEqual(refined.inverseDepth[168*256+128],0.2,accuracy: 0.00001)
    }

    func testUniformColorCannotInventDepthBetweenTwoNativeSurfaces() throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal unavailable") }
        let (original,field) = try fixture()
        let color = CIImage(color: CIColor(red: 0.5,green: 0.5,blue: 0.5)).cropped(to: original.extent)
        let refined = try NativeDepthRefiner().refine(field,color: color)
        XCTAssertEqual(refined.inverseDepth[96*256+131],0.2,accuracy: 0.0001)
    }

    func testDerivedDepthAndScaleSurvivePhotoSaveReopenAndReedit() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal unavailable") }
        let (small,field) = try fixture()
        let color = small.transformed(by: CGAffineTransform(scaleX: 4,y: 4))
        let refined = try NativeDepthRefiner().refine(field,color: color)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let photo = root.appendingPathComponent("input.png")
        let context = CIContext()
        let cg = try XCTUnwrap(context.createCGImage(color,from: color.extent))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(photo as CFURL,UTType.png.identifier as CFString,1,nil))
        CGImageDestinationAddImage(destination,cg,nil); XCTAssertTrue(CGImageDestinationFinalize(destination))
        let original = try Data(contentsOf: photo)
        let result = try await CaptureResultProcessor.shared.render(original: photo,look: nil,aperture: 2.8,
            focus: CGPoint(x: 0.25,y: 0.5),documents: root,depthOverride: refined)
        let session = try await CaptureResultProcessor.shared.loadSession(result: result,original: photo,documents: root)
        XCTAssertEqual(session.field.nativeMetadata,refined.nativeMetadata)
        XCTAssertEqual(session.field.bounds?.upper,field.bounds?.upper)
        let preview = try await DepthPhotoEditor(session: session).preview(aperture: 4,focus: CGPoint(x: 0.25,y: 0.5),
            profile: .natural,original: false)
        XCTAssertEqual(preview.width,768); XCTAssertEqual(preview.height,576)
        XCTAssertEqual(session.field.width,1024); XCTAssertEqual(session.field.height,768)
        let again = try await CaptureResultProcessor.shared.reprocess(result: result,original: photo,aperture: 8,documents: root)
        let restored = try await CaptureResultProcessor.shared.loadSession(result: again,original: photo,documents: root)
        XCTAssertEqual(restored.field.inverseDepth,refined.inverseDepth)
        XCTAssertEqual(try Data(contentsOf: photo),original)
    }

    private func nativePhoto(orientation: UInt32) throws -> URL {
        let (color,_) = try fixture()
        let context = CIContext()
        let cg = try XCTUnwrap(context.createCGImage(color,from: color.extent))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".heic")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL,UTType.heic.identifier as CFString,1,nil))
        CGImageDestinationAddImage(destination,cg,[kCGImagePropertyOrientation: orientation] as CFDictionary)
        let distances: [Float] = (0..<(16*12)).map { $0%16 < 8 ? 1 : 5 }
        let data = distances.withUnsafeBytes { Data($0) }
        let metadata = try XCTUnwrap(CGImageMetadataCreateMutable())
        let description: [CFString:Any] = [
            kCGImagePropertyWidth:NSNumber(value: 16), kCGImagePropertyHeight:NSNumber(value: 12),
            kCGImagePropertyBytesPerRow:NSNumber(value: 64),
            kCGImagePropertyPixelFormat:NSNumber(value: kCVPixelFormatType_DepthFloat32)]
        let info: [CFString:Any] = [kCGImageAuxiliaryDataInfoData: data,
            kCGImageAuxiliaryDataInfoDataDescription: description,
            kCGImageAuxiliaryDataInfoMetadata:metadata]
        CGImageDestinationAddAuxiliaryDataInfo(destination,kCGImageAuxiliaryDataTypeDepth,info as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    func testNativeAttachmentReaderAppliesEightOrientationsExactlyOnce() throws {
        for orientation in UInt32(1)...8 {
            let url = try nativePhoto(orientation: orientation)
            let width = orientation >= 5 ? 192 : 256, height = orientation >= 5 ? 256 : 192
            let native = try XCTUnwrap(NativePhotoDepthReader.read(url,colorWidth: width,colorHeight: height))
            XCTAssertEqual(native.field.width,orientation >= 5 ? 12 : 16)
            XCTAssertEqual(native.field.height,orientation >= 5 ? 16 : 12)
            XCTAssertEqual(native.geometry.orientation,orientation)
            XCTAssertNotNil(native.field.nativeMetadata?.geometry)
            XCTAssertThrowsError(try NativePhotoDepthReader.read(url,colorWidth: width+1,colorHeight: height))
        }
    }

    func testPublicAppleReferenceReportsControlsAndUsesSameNativeInput() throws {
        let url = try nativePhoto(orientation: 1)
        let color = try XCTUnwrap(CIImage(contentsOf: url,options: [.applyOrientationProperty:true]))
        let native = try XCTUnwrap(NativePhotoDepthReader.read(url,colorWidth: 256,colorHeight: 192))
        let result = try NativeDepthReferenceRenderer.make(color: color,depth: native,aperture: 2.8,context: CIContext())
        // Some runtimes decline non-person reference inputs. This is reported
        // as unsupported, rather than substituted with our renderer.
        if let result {
            XCTAssertFalse(result.focusApplied)
            XCTAssertEqual(result.apertureApplied,result.supportedInputKeys.contains("inputAperture"))
            XCTAssertEqual(result.image.extent,color.extent)
        }
        XCTAssertThrowsError(try NativeDepthReferenceRenderer.make(color: color,depth: native,aperture: .nan,context: CIContext()))
    }
}
