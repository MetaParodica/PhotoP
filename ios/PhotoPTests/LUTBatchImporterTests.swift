import XCTest
@testable import PhotoP

final class LUTBatchImporterTests: XCTestCase {
    private func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }; return url
    }
    func testMixedBatchReportsPartialSuccessAndPersistsOriginalLUTBytes() async throws {
        let root = try temporary(), valid = root.appendingPathComponent("curve.cube"), bad = root.appendingPathComponent("bad.cube")
        let bytes = Data("LUT_1D_SIZE 2\n0 0 0\n1 1 1".utf8)
        try bytes.write(to: valid); try Data("not a LUT".utf8).write(to: bad)
        let folder = root.appendingPathComponent("presets"), library = FilterPresetLibrary(folder: folder)
        let report = try await LUTBatchImporter.run([valid, bad], confirmedSRGB: true, library: library)
        XCTAssertEqual(report.imported, 1); XCTAssertEqual(report.failures.count, 1); XCTAssertTrue(report.failures[0].contains("bad.cube"))
        let restarted = FilterPresetLibrary(folder: folder), entries = try await restarted.entries()
        let entry = try XCTUnwrap(entries.first), loaded = try await restarted.load(entry.id)
        XCTAssertEqual(loaded.data, bytes); XCTAssertTrue(loaded.lut.isOneDimensional)
        XCTAssertEqual(try Data(contentsOf: valid), bytes)
    }
    func testUnconfirmedEmptyAndOversizedSelectionsWriteNothing() async throws {
        let root = try temporary(), library = FilterPresetLibrary(folder: root.appendingPathComponent("presets")), url = root.appendingPathComponent("unused.cube")
        for (urls, confirmed) in [([url], false), ([], true), (Array(repeating: url, count: 33), true)] {
            do { _ = try await LUTBatchImporter.run(urls, confirmedSRGB: confirmed, library: library); XCTFail("Expected input gate") } catch { }
        }
        let entries = try await library.entries(); XCTAssertTrue(entries.isEmpty)
    }
}
