import XCTest
import ImageIO
import Metal
@testable import PhotoP

final class BundledFilmLibraryTests: XCTestCase {
    private func temporary() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }; return folder
    }
    func testBundledOriginalsRightsChartsAndCPUToGPUAgreement() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal unavailable") }
        let root = try BundledFilmLibrary.root(), entries = try BundledFilmLibrary.entries(in: root)
        XCTAssertEqual(entries.count, 5)
        var hashes = Set<String>()
        for entry in entries {
            XCTAssertThrowsError(try BundledFilmLibrary.load(entry, in: root, confirmedSRGB: false))
            let imported = try BundledFilmLibrary.load(entry, in: root, confirmedSRGB: true)
            XCTAssertEqual(imported.provenance?.sourceSHA256, entry.sha256)
            XCTAssertEqual(imported.provenance?.license, "CC-BY-4.0")
            XCTAssertTrue(imported.provenance?.kind.contains("assumed-sRGB") == true)
            XCTAssertEqual(imported.lut.dimension, 33); hashes.insert(entry.sha256)
            for i in FilmStyle.chart.indices {
                let sample = try imported.lut.sample(FilmStyle.chart[i])
                for c in 0..<3 { XCTAssertEqual(sample[c], entry.previewColors[i][c], accuracy: 1e-10) }
            }
            let renderer = try MetalLUTRenderer(lut: imported.lut)
            let bytes: [UInt8] = [80,140,200,255, 180,110,70,255]
            let actual = [UInt8](try await renderer.render(Data(bytes), width: 2, height: 1, intensity: 1))
            for pixel in 0..<2 {
                let offset = pixel * 4, input = SIMD3(Double(bytes[offset]), Double(bytes[offset+1]), Double(bytes[offset+2])) / 255
                let expected = try imported.lut.sample(input)
                for c in 0..<3 { XCTAssertEqual(Double(actual[offset+c]), (expected[c]*255).rounded(), accuracy: 1) }
            }
        }
        XCTAssertEqual(hashes.count, 5)
    }
    func testTamperedLUTLicenseAndProfileAssumptionsAreRejected() throws {
        let root = try temporary().appendingPathComponent("luts")
        try FileManager.default.copyItem(at: BundledFilmLibrary.root(), to: root)
        let entry = try XCTUnwrap(BundledFilmLibrary.entries(in: root).first)
        try Data("changed".utf8).write(to: root.appendingPathComponent(entry.file))
        XCTAssertThrowsError(try BundledFilmLibrary.load(entry, in: root, confirmedSRGB: true))
        try Data("changed license".utf8).write(to: root.appendingPathComponent(entry.licenseFile))
        XCTAssertThrowsError(try BundledFilmLibrary.load(entry, in: root, confirmedSRGB: true))
        let file = root.appendingPathComponent("manifest.json")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        var assets = try XCTUnwrap(json["assets"] as? [[String: Any]])
        assets[0]["requiresSRGBConfirmation"] = false; json["assets"] = assets
        try JSONSerialization.data(withJSONObject: json).write(to: file)
        XCTAssertThrowsError(try BundledFilmLibrary.entries(in: root))
        assets[0]["requiresSRGBConfirmation"] = true; assets[0]["file"] = "../outside.cube"; json["assets"] = assets
        try JSONSerialization.data(withJSONObject: json).write(to: file)
        XCTAssertThrowsError(try BundledFilmLibrary.entries(in: root))
    }
    func testFavoritesUpgradeAndPresetsPreserveAttributionAcrossRestart() async throws {
        let root = try temporary(), bundled = try BundledFilmLibrary.root()
        let entry = try XCTUnwrap(BundledFilmLibrary.entries(in: bundled).first)
        let imported = try BundledFilmLibrary.load(entry, in: bundled, confirmedSRGB: true)
        let folder = root.appendingPathComponent("favorites"), favorites = LUTLibrary(folder: folder)
        var uncredited = imported; uncredited.provenance = nil
        _ = try await favorites.save(uncredited)
        _ = try await favorites.save(imported)
        let restored = try await LUTLibrary(folder: folder).load(entry.sha256)
        XCTAssertEqual(restored.provenance, imported.provenance)
        XCTAssertNil(restored.preset)
        let presets = FilterPresetLibrary(folder: root.appendingPathComponent("presets"))
        try await presets.save(restored, settings: .init(intensity: 0.6), name: "Attributed")
        let entries = try await presets.entries(), id = try XCTUnwrap(entries.first?.id)
        let look = try await presets.load(id)
        XCTAssertEqual(look.provenance, imported.provenance)
        XCTAssertEqual(look.preset?.intensity, 0.6)
    }
    func testExportRetainsSourceAndEmbedsCreditInRecipeAndJPEGCaption() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal unavailable") }
        let root = try temporary(), originals = root.appendingPathComponent("Originals")
        try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
        let original = originals.appendingPathComponent("original.jpg")
        let bytes = try SDRImage(rgba: Data(repeating: 180, count: 4 * 4 * 4), width: 4, height: 4).jpeg()
        try bytes.write(to: original)
        let bundle = try BundledFilmLibrary.root(), entry = try XCTUnwrap(BundledFilmLibrary.entries(in: bundle).first)
        let imported = try BundledFilmLibrary.load(entry, in: bundle, confirmedSRGB: true)
        let editor = LUTPhotoEditor(original: original)
        _ = try await editor.loadOriginal(); _ = try await editor.useLUT(imported)
        let result = try await editor.export(intensity: 0.8)
        XCTAssertEqual(try Data(contentsOf: original), bytes)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(result as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let iptc = try XCTUnwrap(properties[kCGImagePropertyIPTCDictionary] as? [CFString: Any])
        let caption = try XCTUnwrap(iptc[kCGImagePropertyIPTCCaptionAbstract] as? String)
        XCTAssertTrue(caption.contains(entry.requiredCredit)); XCTAssertTrue(caption.contains(entry.source))
        let saved = try await SavedEditStore(documents: root).open(result.deletingLastPathComponent().lastPathComponent)
        XCTAssertEqual(saved.recipe.provenance, imported.provenance)
        XCTAssertEqual(saved.imported.provenance, imported.provenance)
    }
}
