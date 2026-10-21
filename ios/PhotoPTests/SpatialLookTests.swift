import XCTest
import Metal
@testable import PhotoP

final class SpatialLookTests: XCTestCase {
    private func identity() throws -> CubeLUT { try XCTUnwrap(ProceduralLook.all.first).imported().lut }
    private func opaqueDot(width: Int, height: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) { bytes[i * 4 + 3] = 255 }
        let center = ((height / 2) * width + width / 2) * 4
        for c in 0..<3 { bytes[center + c] = 255 }
        return Data(bytes)
    }
    func testOldV3FinishDecodesWithNewEffectsNeutralAndNewSettingsRoundTrip() throws {
        let old = Data(#"{"fade":0.2,"vignette":0.3,"bloom":0.4,"halation":0.5}"#.utf8)
        let decoded = try JSONDecoder().decode(FilmFinishSettings.self, from: old)
        XCTAssertEqual(decoded, .init(fade: 0.2, vignette: 0.3, bloom: 0.4, halation: 0.5))
        XCTAssertEqual(decoded.softFocus, 0); XCTAssertEqual(decoded.chromaticAberration, 0); XCTAssertEqual(decoded.streak, 0)
        let settings = FilmFinishSettings(softFocus: 0.8, chromaticAberration: 0.4, streak: 0.6)
        XCTAssertEqual(try JSONDecoder().decode(FilmFinishSettings.self, from: JSONEncoder().encode(settings)), settings)
        for invalid in [FilmFinishSettings(softFocus: .nan), FilmFinishSettings(chromaticAberration: -1), FilmFinishSettings(streak: 2)] {
            XCTAssertThrowsError(try invalid.validate())
        }
        XCTAssertThrowsError(try JSONDecoder().decode(FilmFinishSettings.self, from: Data("{}".utf8)))
    }
    func testSoftFocusSpreadsDetailWithoutColorLUTAndPreservesAlpha() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal unavailable") }
        let renderer = try MetalLUTRenderer(lut: identity()), source = opaqueDot(width: 5, height: 5)
        let output = try await renderer.render(source, width: 5, height: 5, intensity: 0, effects: .init(softFocus: 1))
        XCTAssertEqual(Double(output[(2 * 5 + 1) * 4]), 18, accuracy: 1)
        XCTAssertEqual(Double(output[(2 * 5 + 2) * 4]), 108, accuracy: 1)
        for i in 0..<25 { XCTAssertEqual(output[i * 4 + 3], 255) }
        let transparent = try await renderer.render(Data([0, 0, 0, 0]), width: 1, height: 1, intensity: 0, effects: .init(softFocus: 1, chromaticAberration: 1, streak: 1))
        XCTAssertEqual(transparent, Data([0, 0, 0, 0]))
    }
    func testBrightStreakIsHorizontalAndDoesNotSpreadVertically() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal unavailable") }
        let renderer = try MetalLUTRenderer(lut: identity()), source = opaqueDot(width: 17, height: 5)
        let output = try await renderer.render(source, width: 17, height: 5, intensity: 0, effects: .init(streak: 1))
        XCTAssertEqual(Double(output[(2 * 17 + 7) * 4]), 13, accuracy: 1)
        XCTAssertEqual(output[(1 * 17 + 8) * 4], 0)
        XCTAssertEqual(output[(2 * 17 + 8) * 4], 255)
    }
    func testRadialChromaticSeparationUsesIndependentChannelsAndZeroIsExact() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal unavailable") }
        let renderer = try MetalLUTRenderer(lut: identity())
        var bytes: [UInt8] = []
        for x in 0..<257 { let v: UInt8 = x < 64 ? 255 : 0; bytes.append(contentsOf: [v, v, v, 255]) }
        let source = Data(bytes)
        let neutral = try await renderer.render(source, width: 257, height: 1, intensity: 0, effects: .init())
        XCTAssertEqual(neutral, source)
        let output = try await renderer.render(source, width: 257, height: 1, intensity: 0, effects: .init(chromaticAberration: 1))
        XCTAssertEqual(Array(output[(63 * 4)..<(63 * 4 + 4)]), [255, 255, 0, 255])
    }
    func testEightSpatialPresetsUseIdentityColorAndSaveFullSettings() async throws {
        XCTAssertEqual(ProceduralLook.all.count, 8)
        XCTAssertEqual(Set(ProceduralLook.all.map(\.id)).count, 8)
        for style in ProceduralLook.all {
            let imported = try style.imported()
            XCTAssertEqual(imported.preset?.intensity, 0)
            XCTAssertTrue(imported.preset?.finish.enabled == true)
            let input = SIMD3(0.21, 0.54, 0.87), output = try imported.lut.sample(input)
            for c in 0..<3 { XCTAssertEqual(output[c], input[c], accuracy: 1e-12) }
            try style.settings.validate()
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let style = try XCTUnwrap(ProceduralLook.all.first { $0.id == "dream-glass" })
        let presets = FilterPresetLibrary(folder: folder)
        try await presets.save(style.imported(), settings: style.settings, name: style.name)
        let entries = try await presets.entries(), id = try XCTUnwrap(entries.first?.id)
        let loaded = try await FilterPresetLibrary(folder: folder).load(id)
        XCTAssertEqual(loaded.preset, style.settings)
        XCTAssertEqual(loaded.provenance?.kind, "original-spatial-effects")
    }
    func testSpatialRecipeExportPreservesOriginalAndReopensEffects() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal unavailable") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), originals = root.appendingPathComponent("Originals")
        try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = originals.appendingPathComponent("original.jpg")
        let data = try SDRImage(rgba: opaqueDot(width: 17, height: 5), width: 17, height: 5).jpeg()
        try data.write(to: original)
        let imported = try XCTUnwrap(ProceduralLook.all.first { $0.id == "night-streak" }).imported()
        let editor = LUTPhotoEditor(original: original)
        _ = try await editor.loadOriginal(); _ = try await editor.useLUT(imported)
        let settings = try XCTUnwrap(imported.preset)
        let result = try await editor.export(intensity: settings.intensity, grain: settings.grain, effects: settings.finish)
        let saved = try await SavedEditStore(documents: root).open(result.deletingLastPathComponent().lastPathComponent)
        XCTAssertEqual(saved.recipe.finish, settings.finish)
        XCTAssertEqual(saved.imported.provenance, imported.provenance)
        XCTAssertEqual(try Data(contentsOf: original), data)
    }
}
