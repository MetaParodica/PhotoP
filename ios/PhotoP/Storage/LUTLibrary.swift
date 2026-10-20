import Foundation

struct LUTFavorite: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let version: Int
    let inputColorSpace: String
    let outputColorSpace: String
}

// User-imported files only. This directory is never an app bundle asset source.
actor LUTLibrary {
    static let shared = LUTLibrary(folder: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("UserLUTFavorites", isDirectory: true))
    private let folder: URL
    init(folder: URL) { self.folder = folder }

    func favorites() throws -> [LUTFavorite] {
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { Self.validID($0.lastPathComponent) }
            .map { try metadata($0.lastPathComponent) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    @discardableResult
    func save(_ imported: ImportedLUT) throws -> LUTFavorite {
        let id = LUTPhotoEditor.hash(imported.data)
        let destination = try directory(id)
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try load(id)
            return try metadata(id)
        }
        let entry = LUTFavorite(id: id, name: imported.displayName, version: 1, inputColorSpace: "sRGB", outputColorSpace: "sRGB")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let temporary = folder.appendingPathComponent(".pending-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
        do {
            let options: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            try imported.data.write(to: temporary.appendingPathComponent("look.cube"), options: options)
            try JSONEncoder().encode(entry).write(to: temporary.appendingPathComponent("profile.json"), options: options)
            try FileManager.default.moveItem(at: temporary, to: destination)
            return entry
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    func load(_ id: String) throws -> ImportedLUT {
        let entry = try metadata(id)
        let imported = try ImportedLUT.read(directory(id).appendingPathComponent("look.cube"))
        guard LUTPhotoEditor.hash(imported.data) == id else { throw ImageEditingError.invalid("저장된 LUT 파일이 변경됐습니다.") }
        return ImportedLUT(data: imported.data, lut: imported.lut, displayName: entry.name)
    }

    func remove(_ id: String) throws { try FileManager.default.removeItem(at: directory(id)) }

    private func metadata(_ id: String) throws -> LUTFavorite {
        let url = try directory(id).appendingPathComponent("profile.json")
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 64 * 1024 + 1) ?? Data()
        guard data.count <= 64 * 1024 else { throw ImageEditingError.invalid("LUT 메타데이터가 너무 큽니다.") }
        let entry = try JSONDecoder().decode(LUTFavorite.self, from: data)
        guard entry.id == id, entry.version == 1, entry.inputColorSpace == "sRGB", entry.outputColorSpace == "sRGB"
        else { throw ImageEditingError.invalid("지원하지 않는 LUT 즐겨찾기 프로파일입니다.") }
        return entry
    }
    private func directory(_ id: String) throws -> URL {
        guard Self.validID(id) else { throw ImageEditingError.invalid("LUT 식별자가 유효하지 않습니다.") }
        return folder.appendingPathComponent(id, isDirectory: true)
    }
    private static func validID(_ id: String) -> Bool { id.utf8.count == 64 && id.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }
}
