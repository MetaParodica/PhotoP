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

    private func savedFixture() async throws -> (URL, URL, URL) {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal GPU unavailable") }
        let root = try folder(), originals = root.appendingPathComponent("Originals")
        try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
        let original = try imageFile(in: originals)
        let cube = root.appendingPathComponent("fixture.cube")
        try identityCube().write(to: cube)
        let editor = LUTPhotoEditor(original: original)
        _ = try await editor.loadOriginal()
        _ = try await editor.importCube(cube)
        let output = try await editor.export(intensity: 0.4, grain: GrainSettings(amount: 0.6, seed: 37))
        return (root, original, output)
    }
    private func changeRecipe(_ output: URL, _ change: (inout [String: Any]) -> Void) throws {
        let path = output.deletingLastPathComponent().appendingPathComponent("recipe.json")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
        change(&json)
        try JSONSerialization.data(withJSONObject: json).write(to: path)
    }
    func testReopenAfterRestartAndReexportMatchesPreviewWithoutChangingOriginal() async throws {
        let (root, original, output) = try await savedFixture()
        let before = try Data(contentsOf: original)
        let store = SavedEditStore(documents: root)
        let entries = try await store.list()
        XCTAssertEqual(entries.count, 1)
        let loaded = try await SavedEditStore(documents: root).open(entries[0].id)
        XCTAssertEqual(loaded.original, original.resolvingSymlinksInPath())
        XCTAssertEqual(loaded.recipe.grain, GrainSettings(amount: 0.6, seed: 37))
        let editor = LUTPhotoEditor(original: loaded.original)
        _ = try await editor.loadOriginal()
        _ = try await editor.useLUT(loaded.imported)
        let preview = try await editor.renderPreview(intensity: loaded.recipe.intensity, grain: loaded.recipe.grain!)
        XCTAssertEqual(try preview.jpeg(), try Data(contentsOf: output))
        let newOutput = try await editor.export(intensity: loaded.recipe.intensity, grain: loaded.recipe.grain!)
        XCTAssertNotEqual(output, newOutput)
        XCTAssertEqual(try Data(contentsOf: output), try Data(contentsOf: newOutput))
        XCTAssertEqual(try Data(contentsOf: original), before)
        let newEntries = try await store.list()
        XCTAssertEqual(newEntries.count, 2)
    }
    func testLegacyRecipeReopensWithZeroGrain() async throws {
        let (root, _, output) = try await savedFixture()
        try changeRecipe(output) { $0["version"] = 1; $0.removeValue(forKey: "grain"); $0.removeValue(forKey: "finish") }
        let loaded = try await SavedEditStore(documents: root).open(output.deletingLastPathComponent().lastPathComponent)
        XCTAssertNil(loaded.recipe.grain)
        XCTAssertEqual(loaded.recipe.intensity, 0.4)
    }
    func testReopenRejectsUnsupportedRecipeValuesAndTraversal() async throws {
        let (root, _, output) = try await savedFixture()
        let path = output.deletingLastPathComponent().appendingPathComponent("recipe.json")
        let valid = try Data(contentsOf: path)
        let store = SavedEditStore(documents: root)
        let id = output.deletingLastPathComponent().lastPathComponent
        let changes: [(inout [String: Any]) -> Void] = [
            { $0["version"] = 4 }, { $0["intensity"] = -1 },
            { $0["lutInputColorSpace"] = "Log" }, { $0["workingColorSpace"] = "linear" },
            { $0["originalFilename"] = "../original.png" }, { $0["originalFilename"] = ".." },
            { $0["grain"] = ["amount": 2, "seed": 1] }, { $0.removeValue(forKey: "grain") }
        ]
        for change in changes {
            try valid.write(to: path)
            try changeRecipe(output, change)
            do { _ = try await store.open(id); XCTFail("Expected invalid recipe rejection") } catch {}
        }
        do { _ = try await store.open("../Originals"); XCTFail("Expected ID rejection") } catch {}
        try Data(repeating: 32, count: 64 * 1024 + 1).write(to: path)
        do { _ = try await store.open(id); XCTFail("Expected size rejection") } catch {}
    }
    func testReopenRejectsChangedOriginalAndLUT() async throws {
        let (root, original, output) = try await savedFixture()
        let store = SavedEditStore(documents: root), id = output.deletingLastPathComponent().lastPathComponent
        let source = try Data(contentsOf: original)
        try Data("changed".utf8).write(to: original)
        do { _ = try await store.open(id); XCTFail("Expected original hash rejection") } catch {}
        try source.write(to: original)
        try (identityCube() + Data("\n# changed".utf8)).write(to: output.deletingLastPathComponent().appendingPathComponent("look.cube"))
        do { _ = try await store.open(id); XCTFail("Expected LUT hash rejection") } catch {}
    }
    func testReopenRejectsMissingOriginalAndSymlinks() async throws {
        let (root, original, output) = try await savedFixture()
        let store = SavedEditStore(documents: root), id = output.deletingLastPathComponent().lastPathComponent
        let source = try Data(contentsOf: original)
        try FileManager.default.removeItem(at: original)
        do { _ = try await store.open(id); XCTFail("Expected missing original rejection") } catch {}
        let elsewhere = root.appendingPathComponent("elsewhere.png")
        try source.write(to: elsewhere)
        try FileManager.default.createSymbolicLink(at: original, withDestinationURL: elsewhere)
        do { _ = try await store.open(id); XCTFail("Expected symlink rejection") } catch {}
    }
    func testHistoryIgnoresPendingAndNonIDFolders() async throws {
        let root = try folder()
        let store = SavedEditStore(documents: root)
        let empty = try await store.list()
        XCTAssertTrue(empty.isEmpty)
        let edits = root.appendingPathComponent("Edits")
        for name in [".pending-" + UUID().uuidString, "not-a-bundle"] {
            try FileManager.default.createDirectory(at: edits.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        let entries = try await store.list()
        XCTAssertTrue(entries.isEmpty)
    }

    func testFinishRecipeRestoresAllIndependentSettings() async throws {
        let (root, original, output) = try await savedFixture()
        let loaded = try await SavedEditStore(documents: root).open(output.deletingLastPathComponent().lastPathComponent)
        let editor = LUTPhotoEditor(original: original)
        _ = try await editor.loadOriginal(); _ = try await editor.useLUT(loaded.imported)
        let finish = FilmFinishSettings(fade: 0.2, vignette: 0.4, bloom: 0.5, halation: 0.6)
        let grain = GrainSettings(amount: 0.3, seed: 91)
        let exported = try await editor.export(intensity: 0.7, grain: grain, effects: finish)
        let reopened = try await SavedEditStore(documents: root).open(exported.deletingLastPathComponent().lastPathComponent)
        XCTAssertEqual(reopened.recipe.version, 3); XCTAssertEqual(reopened.recipe.finish, finish); XCTAssertEqual(reopened.recipe.grain, grain)
        let restored = LUTPhotoEditor(original: reopened.original)
        _ = try await restored.loadOriginal(); _ = try await restored.useLUT(reopened.imported)
        let image = try await restored.renderPreview(intensity: reopened.recipe.intensity, grain: reopened.recipe.grain!, effects: reopened.recipe.finish!)
        XCTAssertEqual(try image.jpeg(), try Data(contentsOf: exported))
    }
    func testLegacyVersionTwoRecipeHasNeutralFinish() async throws {
        let (root, _, output) = try await savedFixture()
        try changeRecipe(output) { $0["version"] = 2; $0.removeValue(forKey: "finish") }
        let reopened = try await SavedEditStore(documents: root).open(output.deletingLastPathComponent().lastPathComponent)
        XCTAssertNil(reopened.recipe.finish); XCTAssertEqual(reopened.recipe.grain?.seed, 37)
    }

}
