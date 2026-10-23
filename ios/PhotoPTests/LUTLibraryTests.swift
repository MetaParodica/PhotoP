import XCTest
@testable import PhotoP

final class LUTLibraryTests: XCTestCase {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func fixture() throws -> ImportedLUT {
        var lines = ["TITLE \"Favorite\"", "LUT_3D_SIZE 2"]
        for b in 0...1 { for g in 0...1 { for r in 0...1 { lines.append("\(r) \(g) \(b)") } } }
        let text = lines.joined(separator: "\n")
        return ImportedLUT(data: Data(text.utf8), lut: try CubeLUT.parse(text), displayName: "Favorite")
    }
    func testSaveReloadAcrossStoreInstancesAndDeduplication() async throws {
        let root = try folder().appendingPathComponent("favorites")
        let library = LUTLibrary(folder: root)
        let initial = try await library.favorites()
        XCTAssertTrue(initial.isEmpty)
        let imported = try fixture()
        let first = try await library.save(imported)
        let duplicate = try await library.save(imported)
        XCTAssertEqual(first.id, duplicate.id)
        let restored = LUTLibrary(folder: root)
        let entries = try await restored.favorites()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.name, imported.displayName)
        let loaded = try await restored.load(first.id)
        XCTAssertEqual(loaded.data, imported.data)
        XCTAssertEqual(loaded.displayName, imported.displayName)
        XCTAssertEqual(loaded.lut.dimension, 2)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".pending-") })
    }
    func testTamperedCubeIsRejectedWithoutOverwritingIt() async throws {
        let root = try folder()
        let library = LUTLibrary(folder: root)
        let imported = try fixture()
        let entry = try await library.save(imported)
        let file = root.appendingPathComponent(entry.id).appendingPathComponent("look.cube")
        let changed = imported.data + Data("\n# changed".utf8)
        try changed.write(to: file)
        do { _ = try await library.load(entry.id); XCTFail("Expected hash mismatch") }
        catch { XCTAssertTrue(error is ImageEditingError) }
        do { _ = try await library.save(imported); XCTFail("Expected existing corrupt favorite rejection") }
        catch { XCTAssertTrue(error is ImageEditingError) }
        XCTAssertEqual(try Data(contentsOf: file), changed)
    }
    func testProfileMismatchIsRejected() async throws {
        let root = try folder()
        let library = LUTLibrary(folder: root)
        let entry = try await library.save(fixture())
        let unknown = LUTFavorite(id: entry.id, name: entry.name, version: 1, inputColorSpace: "Apple Log", outputColorSpace: "sRGB")
        try JSONEncoder().encode(unknown).write(to: root.appendingPathComponent(entry.id).appendingPathComponent("profile.json"))
        do { _ = try await library.load(entry.id); XCTFail("Expected unsupported profile rejection") }
        catch { XCTAssertTrue(error is ImageEditingError) }
    }
    func testIdentifierCannotEscapeLibrary() async throws {
        let root = try folder()
        let outside = root.appendingPathComponent("outside")
        try Data([1, 2, 3]).write(to: outside)
        let library = LUTLibrary(folder: root.appendingPathComponent("favorites"))
        for id in ["../outside", String(repeating: "G", count: 64), "", String(repeating: "a", count: 65)] {
            do { try await library.remove(id); XCTFail("Expected identifier rejection") }
            catch { XCTAssertTrue(error is ImageEditingError) }
            do { _ = try await library.load(id); XCTFail("Expected identifier rejection") }
            catch { XCTAssertTrue(error is ImageEditingError) }
        }
        XCTAssertEqual(try Data(contentsOf: outside), Data([1, 2, 3]))
    }
    func testRemoveDoesNotDeleteSourceImportBytes() async throws {
        let root = try folder()
        let library = LUTLibrary(folder: root.appendingPathComponent("favorites"))
        let imported = try fixture()
        let source = root.appendingPathComponent("source.cube")
        try imported.data.write(to: source)
        let entry = try await library.save(imported)
        try await library.remove(entry.id)
        let entries = try await library.favorites()
        XCTAssertTrue(entries.isEmpty)
        XCTAssertEqual(try Data(contentsOf: source), imported.data)
    }
    func testSaveFailurePropagatesAndKeepsExistingFile() async throws {
        let root = try folder()
        let blocked = root.appendingPathComponent("blocked")
        try Data([42]).write(to: blocked)
        let library = LUTLibrary(folder: blocked)
        do { _ = try await library.save(fixture()); XCTFail("Expected filesystem failure") } catch {}
        XCTAssertEqual(try Data(contentsOf: blocked), Data([42]))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["blocked"])
    }
    func testFavoriteRestoresExactStrengthGrainAndFinishAcrossRestart() async throws {
        let root = try folder(), library = LUTLibrary(folder: root)
        var imported = try fixture()
        let settings = ProcessingLookSettings(intensity: 0.3, grain: .init(amount: 0.4, seed: 77), finish: .init(vignette: 0.6, softFocus: 0.5))
        imported.preset = settings
        let entry = try await library.save(imported)
        XCTAssertEqual(entry.version, 2)
        let restored = try await LUTLibrary(folder: root).load(entry.id)
        XCTAssertEqual(restored.preset, settings)
        XCTAssertEqual(restored.data, imported.data)
    }
    func testIdentityCarriersWithDifferentSpatialSettingsDoNotCollide() async throws {
        let root = try folder(), library = LUTLibrary(folder: root)
        let first = try await library.save(ProceduralLook.all[0].imported())
        let second = try await library.save(ProceduralLook.all[1].imported())
        XCTAssertNotEqual(first.id, second.id)
        let loaded = try await library.load(second.id)
        XCTAssertEqual(loaded.preset, ProceduralLook.all[1].settings)
        let entries = try await library.favorites(); XCTAssertEqual(entries.count, 2)
    }
    func testLegacySpatialFavoriteRecoversOnlyKnownMatchingCarrier() async throws {
        let root = try folder(), look = try ProceduralLook.all[0].imported()
        let hash = LUTPhotoEditor.hash(look.data), directory = root.appendingPathComponent(hash)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        try look.data.write(to: directory.appendingPathComponent("look.cube"))
        let legacy = LUTFavorite(id: hash, name: look.displayName, version: 1, inputColorSpace: "sRGB", outputColorSpace: "sRGB", provenance: look.provenance)
        try JSONEncoder().encode(legacy).write(to: directory.appendingPathComponent("profile.json"))
        let loaded = try await LUTLibrary(folder: root).load(hash)
        XCTAssertEqual(loaded.preset, ProceduralLook.all[0].settings)
    }
    func testModifiedFavoriteSettingsAreRejectedWithoutOverwritingThem() async throws {
        let root = try folder(), library = LUTLibrary(folder: root)
        var look = try fixture(); look.preset = ProcessingLookSettings(intensity: 0.7)
        var entry = try await library.save(look)
        entry.settings?.intensity = 0
        let record = root.appendingPathComponent(entry.id).appendingPathComponent("profile.json")
        let changed = try JSONEncoder().encode(entry); try changed.write(to: record)
        do { _ = try await library.load(entry.id); XCTFail("Tampered effect settings accepted") } catch {}
        XCTAssertEqual(try Data(contentsOf: record), changed)
    }
}
