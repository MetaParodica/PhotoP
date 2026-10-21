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
}
