import XCTest
import ImageIO
import UniformTypeIdentifiers
import Metal
@testable import PhotoP

final class LUTPhotoEditorTests: XCTestCase {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func imageFile(in folder: URL, orientation: Int = 1) throws -> URL {
        let image = SDRImage(rgba: Data([255,0,0,255, 0,255,0,255, 0,0,255,255, 255,255,0,255, 255,0,255,255, 0,255,255,255]), width: 2, height: 3)
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try image.cgImage(), [kCGImagePropertyOrientation: orientation] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let url = folder.appendingPathComponent("original.png")
        try (data as Data).write(to: url)
        return url
    }
    private func identityCube() -> Data {
        var lines = ["TITLE \"Fixture\"", "LUT_3D_SIZE 2"]
        for b in 0...1 { for g in 0...1 { for r in 0...1 { lines.append("\(r) \(g) \(b)") } } }
        return Data(lines.joined(separator: "\n").utf8)
    }
    func testDecodeOrientationBakedOnceAndPreviewBound() throws {
        let root = try folder()
        let original = try imageFile(in: root, orientation: 6)
        let full = try SDRImage.decode(original)
        XCTAssertEqual(full.width, 3)
        XCTAssertEqual(full.height, 2)
        let preview = try SDRImage.decode(original, previewMaxDimension: 2)
        XCTAssertLessThanOrEqual(max(preview.width, preview.height), 2)
        let jpeg = try full.jpeg()
        let source = try XCTUnwrap(CGImageSourceCreateWithData(jpeg as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertEqual(properties[kCGImagePropertyOrientation] as? Int ?? 1, 1)
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 3)
        XCTAssertEqual(image.height, 2)
        XCTAssertEqual(image.colorSpace?.name, CGColorSpace.sRGB)
    }
    func testSRGBDecodePreservesChannelOrder() throws {
        let url = try imageFile(in: folder())
        let image = try SDRImage.decode(url)
        XCTAssertEqual(image.rgba, Data([255,0,0,255, 0,255,0,255, 0,0,255,255, 255,255,0,255, 255,0,255,255, 0,255,255,255]))
    }
    func testRejectsInvalidPixelDataAndUnreadableSource() throws {
        XCTAssertThrowsError(try SDRImage(rgba: Data(), width: Int.max, height: 2).cgImage())
        XCTAssertThrowsError(try SDRImage(rgba: Data(count: 3), width: 1, height: 1).cgImage())
        let url = try imageFile(in: folder())
        XCTAssertThrowsError(try SDRImage.decode(url, previewMaxDimension: 0))
        XCTAssertThrowsError(try SDRImage.decode(url.deletingLastPathComponent().appendingPathComponent("absent")))
    }
    func testStreamHashMatchesKnownSHA256() throws {
        let data = Data("abc".utf8)
        let url = try folder().appendingPathComponent("bytes")
        try data.write(to: url)
        XCTAssertEqual(try LUTPhotoEditor.hashFile(url), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(try LUTPhotoEditor.hashFile(url), LUTPhotoEditor.hash(data))
    }
    func testEndToEndExportKeepsOriginalAndReproductionAssets() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal GPU unavailable") }
        let root = try folder()
        let originals = root.appendingPathComponent("Originals")
        try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
        let url = try imageFile(in: originals, orientation: 6)
        let before = try Data(contentsOf: url)
        let cube = identityCube()
        let cubeURL = root.appendingPathComponent("identity.cube")
        try cube.write(to: cubeURL)
        let editor = LUTPhotoEditor(original: url)
        _ = try await editor.loadOriginal()
        let title = try await editor.importCube(cubeURL)
        XCTAssertEqual(title, "Fixture")
        let preview = try await editor.renderPreview(intensity: 0.5)
        let output = try await editor.export(intensity: 0.5)
        XCTAssertNotEqual(output, url)
        XCTAssertEqual(try Data(contentsOf: url), before)
        let editFolder = output.deletingLastPathComponent()
        XCTAssertEqual(try Data(contentsOf: editFolder.appendingPathComponent("look.cube")), cube)
        let recipe = try JSONDecoder().decode(ImageProcessingRecipe.self, from: Data(contentsOf: editFolder.appendingPathComponent("recipe.json")))
        XCTAssertEqual(recipe.originalSHA256, LUTPhotoEditor.hash(before))
        XCTAssertEqual(recipe.lutSHA256, LUTPhotoEditor.hash(cube))
        XCTAssertEqual(recipe.intensity, 0.5)
        XCTAssertEqual(recipe.outputColorSpace, "sRGB")
        let final = try SDRImage.decode(output)
        XCTAssertEqual(final.width, preview.width)
        XCTAssertEqual(final.height, preview.height)
        // JPEG is lossy; compare the exact encoder output from the preview for this small fixture.
        XCTAssertEqual(try Data(contentsOf: output), try preview.jpeg())
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Edits").path).contains { $0.hasPrefix(".pending-") })
    }
    func testMissingLUTAndInvalidImportDoNotExport() async throws {
        let root = try folder()
        let url = try imageFile(in: root)
        let editor = LUTPhotoEditor(original: url)
        _ = try await editor.loadOriginal()
        let bad = root.appendingPathComponent("bad.cube")
        try Data("LUT_3D_SIZE 2\n0 0 0".utf8).write(to: bad)
        do { _ = try await editor.importCube(bad); XCTFail("Expected parser rejection") } catch { XCTAssertTrue(error is CubeLUTError) }
        do { _ = try await editor.export(intensity: 1); XCTFail("Expected missing LUT rejection") } catch { XCTAssertTrue(error is ImageEditingError) }
    }
    func testBundleFailureRemovesPartialFolder() throws {
        let root = try folder()
        let recipe = ImageProcessingRecipe(version: 1, originalFilename: "original", originalSHA256: "hash", lutSHA256: "hash", lutTitle: nil, intensity: .nan,
                                            workingColorSpace: "sRGB", lutInputColorSpace: "sRGB", lutOutputColorSpace: "sRGB", outputColorSpace: "sRGB", pipeline: "test")
        XCTAssertThrowsError(try LUTPhotoEditor.writeBundle(jpeg: Data([1]), cube: identityCube(), recipe: recipe, in: root))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }
    func testImportRejectsInvalidUTF8AndOversizedFiles() async throws {
        let root = try folder()
        let editor = LUTPhotoEditor(original: try imageFile(in: root))
        let url = root.appendingPathComponent("input.cube")
        for data in [Data([0xff, 0xfe]), Data(repeating: 32, count: CubeLUT.maximumFileBytes + 1)] {
            try data.write(to: url)
            do { _ = try await editor.importCube(url); XCTFail("Expected bounded UTF-8 import rejection") }
            catch { XCTAssertTrue(error is ImageEditingError) }
        }
    }

}
