import XCTest
import Metal
@testable import PhotoP

final class CompanyFilmLibraryTests: XCTestCase {
    private func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }; return url
    }
    private func identity() throws -> CubeLUT {
        var lines = ["LUT_3D_SIZE 2"]
        for b in 0...1 { for g in 0...1 { for r in 0...1 { lines.append("\(r) \(g) \(b)") } } }
        return try CubeLUT.parse(lines.joined(separator: "\n"))
    }
    func testPanasonicReferenceCodeValuesAndGamutWhite() {
        XCTAssertEqual(SDRVendorAdapter.encodeVLog(0), 0.125, accuracy: 1e-12)
        XCTAssertEqual(SDRVendorAdapter.encodeVLog(0.18), 0.423311448760136, accuracy: 1e-12)
        XCTAssertEqual(SDRVendorAdapter.encodeVLog(0.90), 0.5881674381544377, accuracy: 1e-10)
        let white = SDRVendorAdapter.input(.init(repeating: 1))
        for c in 0..<3 { XCTAssertEqual(white[c], SDRVendorAdapter.encodeVLog(1), accuracy: 0.000001) }
        for x in [0.0, 0.02, 0.18, 0.5, 1] { XCTAssertEqual(SDRVendorAdapter.encodeSRGB(SDRVendorAdapter.decodeSRGB(x)), x, accuracy: 1e-12) }
    }
    func testAllAcquiredOriginalsAndChartProfilesAreTracked() throws {
        let root = try CompanyFilmLibrary.root(), entries = try CompanyFilmLibrary.entries(in: root)
        XCTAssertEqual(entries.count, 25)
        XCTAssertEqual(entries.filter { $0.role == "creative" }.count, 22)
        XCTAssertEqual(entries.filter { $0.role == "technical" }.count, 3)
        XCTAssertEqual(entries.filter { !$0.canApply }.count, 1)
        for e in entries {
            XCTAssertFalse(e.official); XCTAssertEqual(e.rightsStatus, "unverified")
            let raw = try ImportedLUT.read(CompanyFilmLibrary.original(e, in: root))
            XCTAssertEqual(LUTPhotoEditor.hash(raw.data), e.sha256)
            if !e.canApply { continue }
            for i in FilmStyle.chart.indices {
                let color = e.nativeInput == "vlog-vgamut" ? try SDRVendorAdapter.sample(FilmStyle.chart[i], source: raw.lut) : try raw.lut.sample(FilmStyle.chart[i])
                for c in 0..<3 { XCTAssertEqual(min(max(color[c], 0), 1), e.previewColors[i][c], accuracy: 1e-8) }
            }
        }
    }
    func testBakedAdapterRetainsDeclaredDomainAndApproximatesOffGridValues() throws {
        let source = try identity()
        let bytes = try SDRVendorAdapter.bake(source, dimension: 33, sourceSHA256: String(repeating: "a", count: 64))
        let lut = try CubeLUT.parse(String(decoding: bytes, as: UTF8.self))
        XCTAssertEqual(lut.dimension, 33)
        XCTAssertTrue(String(decoding: bytes, as: UTF8.self).contains("display-referred approximation"))
        for i in 0..<101 {
            let input = SIMD3(Double(i * 37 % 101), Double(i * 53 % 101), Double(i * 71 % 101)) / 100
            let actual = try lut.sample(input), expected = try SDRVendorAdapter.sample(input, source: source)
            for c in 0..<3 { XCTAssertEqual(actual[c], expected[c], accuracy: 0.006) }
        }
        XCTAssertThrowsError(try SDRVendorAdapter.bake(source, dimension: 66, sourceSHA256: ""))
    }
    func testCompiled65CubeCacheSurvivesRestartAndRejectsCorruption() async throws {
        let root = try CompanyFilmLibrary.root()
        let entry = try XCTUnwrap(CompanyFilmLibrary.entries(in: root).first { $0.nativeInput == "vlog-vgamut" && $0.canApply })
        let folder = try temporary(), compiler = CompanyLookCompiler(folder: folder)
        let source = try Data(contentsOf: CompanyFilmLibrary.original(entry, in: root))
        let first = try await compiler.load(entry, in: root)
        XCTAssertEqual(first.lut.dimension, 65)
        XCTAssertNotEqual(first.provenance?.sourceSHA256, first.provenance?.renderLUTSHA256)
        let restored = try await CompanyLookCompiler(folder: folder).load(entry, in: root)
        XCTAssertEqual(first.data, restored.data)
        let cache = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).first { $0.pathExtension == "cube" })
        try Data("corrupt".utf8).write(to: cache)
        let regenerated = try await compiler.load(entry, in: root)
        XCTAssertEqual(first.data, regenerated.data)
        XCTAssertEqual(try Data(contentsOf: CompanyFilmLibrary.original(entry, in: root)), source)
        if MTLCreateSystemDefaultDevice() != nil {
            let renderer = try MetalLUTRenderer(lut: first.lut)
            let output = try await renderer.render(Data([64, 128, 192, 255]), width: 1, height: 1, intensity: 1)
            let expected = try first.lut.sample(SIMD3(64.0, 128, 192) / 255)
            for c in 0..<3 { XCTAssertEqual(Double(output[c]), (expected[c] * 255).rounded(), accuracy: 1) }
        }
    }
    func testUnknownOutputOriginalCanBeSharedButNotApplied() async throws {
        let root = try CompanyFilmLibrary.root(), entries = try CompanyFilmLibrary.entries(in: root)
        let entry = try XCTUnwrap(entries.first { !$0.canApply })
        XCTAssertTrue(FileManager.default.fileExists(atPath: try CompanyFilmLibrary.original(entry, in: root).path))
        do { _ = try await CompanyLookCompiler(folder: temporary()).load(entry, in: root); XCTFail("Unknown output applied") } catch {}
    }
    func testTamperedOriginalAndUnsafeManifestAreRejected() async throws {
        let root = try temporary().appendingPathComponent("company-luts")
        try FileManager.default.copyItem(at: CompanyFilmLibrary.root(), to: root)
        let entry = try XCTUnwrap(CompanyFilmLibrary.entries(in: root).first { $0.nativeInput == "srgb-assumed" })
        let compiler = CompanyLookCompiler(folder: root.appendingPathComponent("cache"))
        try Data("changed".utf8).write(to: CompanyFilmLibrary.original(entry, in: root))
        do { _ = try await compiler.load(entry, in: root); XCTFail("Changed source accepted") } catch {}
        let manifest = root.appendingPathComponent("manifest.json")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any])
        var entries = try XCTUnwrap(json["assets"] as? [[String: Any]])
        entries[0]["file"] = "../outside.cube"; json["assets"] = entries
        try JSONSerialization.data(withJSONObject: json).write(to: manifest)
        XCTAssertThrowsError(try CompanyFilmLibrary.entries(in: root))
    }
    func testRightsUnverifiedDisplayLookAndPresetKeepSourceProvenance() async throws {
        let root = try CompanyFilmLibrary.root(), entries = try CompanyFilmLibrary.entries(in: root), folder = try temporary()
        let entry = try XCTUnwrap(entries.first { $0.nativeInput == "srgb-assumed" })
        let imported = try await CompanyLookCompiler(folder: folder.appendingPathComponent("cache")).load(entry, in: root)
        XCTAssertEqual(LUTPhotoEditor.hash(imported.data), entry.sha256)
        XCTAssertEqual(imported.provenance?.license, "UNVERIFIED")
        let presets = FilterPresetLibrary(folder: folder.appendingPathComponent("presets"))
        try await presets.save(imported, settings: .init(intensity: 0.4), name: "External")
        let saved = try await presets.entries()
        let id = try XCTUnwrap(saved.first?.id)
        let loaded = try await presets.load(id)
        XCTAssertEqual(loaded.provenance, imported.provenance)
        XCTAssertEqual(loaded.preset?.intensity, 0.4)
    }
}
