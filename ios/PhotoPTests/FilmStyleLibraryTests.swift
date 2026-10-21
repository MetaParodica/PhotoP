import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import PhotoP

final class FilmStyleLibraryTests: XCTestCase {
    func testTwelveUniqueOriginalProfilesWithReproducibleRightsAndHashes() throws {
        XCTAssertEqual(FilmStyle.all.count, 12)
        var hashes = Set<String>()
        for style in FilmStyle.all {
            let imported = try style.imported(), p = try XCTUnwrap(imported.provenance)
            XCTAssertEqual(imported.data, try style.imported().data)
            XCTAssertEqual(p.renderLUTSHA256, LUTPhotoEditor.hash(imported.data))
            XCTAssertEqual(p.sourceSHA256, p.renderLUTSHA256)
            XCTAssertTrue(p.commercialUseAllowed && p.redistributionAllowed)
            XCTAssertEqual(p.kind, "original-procedural")
            XCTAssertEqual(p.license, "PhotoP-Style-Permission-1")
            XCTAssertEqual(p.inputColorSpace, "sRGB"); XCTAssertEqual(p.outputColorSpace, "sRGB")
            hashes.insert(p.renderLUTSHA256)
        }
        XCTAssertEqual(hashes.count, 12)
    }
    func testChartInterpolationBoundsAndGrayMonotonicity() throws {
        for style in FilmStyle.all {
            let lut = try style.imported().lut
            for patch in FilmStyle.chart {
                let actual = try lut.sample(patch), expected = style.color(patch)
                for c in 0..<3 { XCTAssertTrue(actual[c].isFinite); XCTAssertTrue((0...1).contains(actual[c])); XCTAssertEqual(actual[c], expected[c], accuracy: 0.015) }
                if style.monochrome { XCTAssertEqual(actual.x, actual.y, accuracy: 0.000001); XCTAssertEqual(actual.y, actual.z, accuracy: 0.000001) }
            }
            var previous = SIMD3<Double>(repeating: -1)
            for i in 0...100 {
                let value = style.color(.init(repeating: Double(i) / 100))
                for c in 0..<3 { XCTAssertGreaterThanOrEqual(value[c], previous[c]) }
                previous = value
            }
        }
    }
    func testSearchAndCategory() {
        XCTAssertEqual(FilmStyle.search("portrait", category: "전체").map(\.id), ["amber-portrait"])
        XCTAssertEqual(FilmStyle.search("", category: "흑백").count, 2)
        XCTAssertTrue(FilmStyle.search("portrait", category: "풍경").isEmpty)
        XCTAssertEqual(FilmStyle.search("피부", category: "전체").count, 1)
    }
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }; return url
    }
    func testPresetPersistsEntireLookAcrossRestartWithoutDeduplicatingCube() async throws {
        let root = try folder(), library = FilterPresetLibrary(folder: root), imported = try FilmStyle.all[0].imported()
        let settings = ProcessingLookSettings(intensity: 0.42, grain: .init(amount: 0.3, seed: 99), finish: .init(fade: 0.2, vignette: 0.3, bloom: 0.4, halation: 0.5))
        try await library.save(imported, settings: settings, name: "My portrait")
        try await library.save(imported, settings: .init(intensity: 0.2), name: "Second")
        let restarted = FilterPresetLibrary(folder: root), entries = try await restarted.entries()
        XCTAssertEqual(entries.count, 2)
        let first = try XCTUnwrap(entries.first { $0.name == "My portrait" })
        let loaded = try await restarted.load(first.id)
        XCTAssertEqual(loaded.data, imported.data); XCTAssertEqual(loaded.preset, settings); XCTAssertEqual(loaded.provenance, imported.provenance)
        try await restarted.remove(first.id)
        let remaining = try await restarted.entries(); XCTAssertEqual(remaining.count, 1)
    }
    func testPresetTamperAndInvalidSettingsRejected() async throws {
        let root = try folder(), library = FilterPresetLibrary(folder: root), imported = try FilmStyle.all[0].imported()
        do { try await library.save(imported, settings: .init(intensity: -1), name: "bad"); XCTFail("Invalid intensity") } catch { }
        do { try await library.save(imported, settings: .init(), name: " "); XCTFail("Empty name") } catch { }
        try await library.save(imported, settings: .init(), name: "valid")
        let entries = try await library.entries(), id = try XCTUnwrap(entries.first?.id)
        try Data("changed".utf8).write(to: root.appendingPathComponent(id).appendingPathComponent("look.cube"))
        do { _ = try await library.load(id); XCTFail("Tampered cube") } catch { }
        do { _ = try await library.load("../outside"); XCTFail("Traversal") } catch { }
    }
    func testPresetVersionAndProvenanceMismatchRejected() async throws {
        let root = try folder(), library = FilterPresetLibrary(folder: root), imported = try FilmStyle.all[0].imported()
        try await library.save(imported, settings: .init(), name: "valid")
        let entries = try await library.entries(), id = try XCTUnwrap(entries.first?.id)
        let file = root.appendingPathComponent(id).appendingPathComponent("preset.json")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        json["version"] = 99
        try JSONSerialization.data(withJSONObject: json).write(to: file)
        do { _ = try await library.load(id); XCTFail("Unsupported version") } catch { }
        json["version"] = 1
        var provenance = try XCTUnwrap(json["provenance"] as? [String: Any]); provenance["renderLUTSHA256"] = "wrong"; json["provenance"] = provenance
        try JSONSerialization.data(withJSONObject: json).write(to: file)
        do { _ = try await library.load(id); XCTFail("Provenance hash mismatch") } catch { }
    }
    private func png(_ image: SDRImage, orientation: Int = 1) throws -> Data {
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try image.cgImage(), [kCGImagePropertyOrientation: orientation] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination)); return data as Data
    }
    func testHaldIdentityAndSwappedChannelsUseRedFastestOrder() throws {
        for swap in [false, true] {
            var bytes = [UInt8]()
            for b in 0..<4 { for g in 0..<4 { for r in 0..<4 {
                bytes.append(contentsOf: [UInt8((swap ? b : r) * 85), UInt8(g * 85), UInt8((swap ? r : b) * 85), 255])
            } } }
            let data = try png(SDRImage(rgba: Data(bytes), width: 8, height: 8))
            let cube = try HaldLUT.convert(data), lut = try CubeLUT.parse(String(decoding: cube, as: UTF8.self))
            let sample = try lut.sample(.init(0.2, 0.4, 0.7))
            XCTAssertEqual(sample.x, swap ? 0.7 : 0.2, accuracy: 0.00001); XCTAssertEqual(sample.y, 0.4, accuracy: 0.00001)
            XCTAssertEqual(sample.z, swap ? 0.2 : 0.7, accuracy: 0.00001)
            XCTAssertTrue(String(decoding: cube, as: UTF8.self).contains(LUTPhotoEditor.hash(data)))
        }
    }
    func testHaldRejectsNonTableRotatedTransparentAndOversizedInputs() throws {
        XCTAssertThrowsError(try HaldLUT.convert(Data("not png".utf8)))
        XCTAssertThrowsError(try HaldLUT.convert(Data(count: 8 * 1024 * 1024 + 1)))
        let white = SDRImage(rgba: Data(repeating: 255, count: 8 * 8 * 4), width: 8, height: 8)
        XCTAssertThrowsError(try HaldLUT.convert(png(white, orientation: 6)))
        XCTAssertThrowsError(try HaldLUT.convert(png(.init(rgba: Data(repeating: 255, count: 4 * 4 * 4), width: 4, height: 4))))
        var rgba = white.rgba; rgba[3] = 0
        XCTAssertThrowsError(try HaldLUT.convert(png(.init(rgba: rgba, width: 8, height: 8))))
    }
}
