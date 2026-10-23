import Foundation

struct LUTFavorite: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let version: Int
    let inputColorSpace: String
    let outputColorSpace: String
    var provenance: LUTProvenance? = nil
    var settings: ProcessingLookSettings? = nil
    var lutSHA256: String? = nil
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
        let hash = LUTPhotoEditor.hash(imported.data)
        try imported.preset?.validate()
        let id = try Self.identifier(hash: hash, settings: imported.preset, provenance: imported.provenance)
        if let p = imported.provenance {
            guard p.renderLUTSHA256 == hash, p.inputColorSpace == "sRGB", p.outputColorSpace == "sRGB" else { throw CameraError.invalidPhotoData }
        }
        let destination = try directory(id)
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try load(id)
            var entry = try metadata(id)
            if entry.provenance == nil, let provenance = imported.provenance {
                entry.provenance = provenance
                try JSONEncoder().encode(entry).write(to: destination.appendingPathComponent("profile.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
            return entry
        }
        let entry = LUTFavorite(id: id, name: imported.displayName, version: imported.preset == nil ? 1 : 2,
            inputColorSpace: "sRGB", outputColorSpace: "sRGB", provenance: imported.provenance,
            settings: imported.preset, lutSHA256: imported.preset == nil ? nil : hash)
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
        let hash = LUTPhotoEditor.hash(imported.data)
        guard hash == (entry.version == 1 ? id : entry.lutSHA256) else { throw ImageEditingError.invalid("저장된 LUT 파일이 변경됐습니다.") }
        if let p = entry.provenance {
            guard p.renderLUTSHA256 == hash, p.inputColorSpace == "sRGB", p.outputColorSpace == "sRGB" else { throw CameraError.invalidPhotoData }
        }
        var settings = entry.settings
        // Repair known legacy spatial favorites whose identity cube was stored
        // without finish parameters. Only exact built-in ID + bytes qualify.
        if entry.version == 1, let p = entry.provenance, p.kind == "original-spatial-effects",
           let spatial = ProceduralLook.all.first(where: { p.identifier == "photop.spatial.\($0.id).v1" }),
           try spatial.imported().data == imported.data { settings = spatial.settings }
        return ImportedLUT(data: imported.data, lut: imported.lut, displayName: entry.name, preset: settings, provenance: entry.provenance)
    }

    func remove(_ id: String) throws { try FileManager.default.removeItem(at: directory(id)) }

    private func metadata(_ id: String) throws -> LUTFavorite {
        let url = try directory(id).appendingPathComponent("profile.json")
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 64 * 1024 + 1) ?? Data()
        guard data.count <= 64 * 1024 else { throw ImageEditingError.invalid("LUT 메타데이터가 너무 큽니다.") }
        let entry = try JSONDecoder().decode(LUTFavorite.self, from: data)
        guard entry.id == id, [1, 2].contains(entry.version), entry.inputColorSpace == "sRGB", entry.outputColorSpace == "sRGB"
        else { throw ImageEditingError.invalid("지원하지 않는 LUT 즐겨찾기 프로파일입니다.") }
        if entry.version == 1 {
            guard entry.settings == nil, entry.lutSHA256 == nil else { throw ImageEditingError.invalid("구형 즐겨찾기의 설정 형식이 다릅니다.") }
        } else {
            guard let settings = entry.settings, let hash = entry.lutSHA256, Self.validID(hash) else { throw ImageEditingError.invalid("즐겨찾기 설정이 누락됐습니다.") }
            try settings.validate()
            guard try Self.identifier(hash: hash, settings: settings, provenance: entry.provenance) == id else { throw ImageEditingError.invalid("즐겨찾기 설정이 변경됐습니다.") }
        }
        return entry
    }
    private static func identifier(hash: String, settings: ProcessingLookSettings?, provenance: LUTProvenance?) throws -> String {
        guard let settings else { return hash }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return LUTPhotoEditor.hash(Data((hash + ":" + (provenance?.identifier ?? "") + ":").utf8) + (try encoder.encode(settings)))
    }
    private func directory(_ id: String) throws -> URL {
        guard Self.validID(id) else { throw ImageEditingError.invalid("LUT 식별자가 유효하지 않습니다.") }
        return folder.appendingPathComponent(id, isDirectory: true)
    }
    private static func validID(_ id: String) -> Bool { id.utf8.count == 64 && id.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }
}
