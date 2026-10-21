import Foundation

struct FilterPreset: Codable, Identifiable, Sendable {
    let id: String
    let version: Int
    let name: String
    let lutSHA256: String
    let settings: ProcessingLookSettings
    let provenance: LUTProvenance?
}
actor FilterPresetLibrary {
    static let shared = FilterPresetLibrary(folder: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("FilterPresets"))
    private let folder: URL
    init(folder: URL) { self.folder = folder.standardizedFileURL.resolvingSymlinksInPath() }
    func entries() throws -> [FilterPreset] {
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { UUID(uuidString: $0.lastPathComponent) != nil }
            .map { try metadata($0.lastPathComponent) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    func save(_ imported: ImportedLUT, settings: ProcessingLookSettings, name: String) throws {
        try settings.validate()
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80 else { throw ImageEditingError.invalid("프리셋 이름은 1~80글자입니다.") }
        guard let text = String(data: imported.data, encoding: .utf8) else { throw CameraError.invalidPhotoData }
        _ = try CubeLUT.parse(text)
        let hash = LUTPhotoEditor.hash(imported.data)
        if let provenance = imported.provenance { guard provenance.renderLUTSHA256 == hash else { throw CameraError.invalidPhotoData } }
        let id = UUID().uuidString
        let preset = FilterPreset(id: id, version: 1, name: name, lutSHA256: hash, settings: settings, provenance: imported.provenance)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let temporary = folder.appendingPathComponent(".pending-" + id)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
        do {
            try imported.data.write(to: temporary.appendingPathComponent("look.cube"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try JSONEncoder().encode(preset).write(to: temporary.appendingPathComponent("preset.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try FileManager.default.moveItem(at: temporary, to: folder.appendingPathComponent(id))
        } catch { try? FileManager.default.removeItem(at: temporary); throw error }
    }
    func load(_ id: String) throws -> ImportedLUT {
        let preset = try metadata(id), directory = try directory(id)
        let url = directory.appendingPathComponent("look.cube")
        guard url.resolvingSymlinksInPath() == url else { throw CameraError.invalidPhotoData }
        let imported = try ImportedLUT.read(url)
        guard LUTPhotoEditor.hash(imported.data) == preset.lutSHA256 else { throw ImageEditingError.invalid("프리셋 LUT가 변경됐습니다.") }
        if let p = preset.provenance {
            guard p.renderLUTSHA256 == preset.lutSHA256, p.inputColorSpace == "sRGB", p.outputColorSpace == "sRGB" else { throw CameraError.invalidPhotoData }
        }
        return ImportedLUT(data: imported.data, lut: imported.lut, displayName: preset.name, preset: preset.settings, provenance: preset.provenance)
    }
    func remove(_ id: String) throws { try FileManager.default.removeItem(at: directory(id)) }
    private func directory(_ id: String) throws -> URL {
        guard UUID(uuidString: id) != nil else { throw CameraError.invalidPhotoData }
        let url = folder.appendingPathComponent(id)
        guard url.resolvingSymlinksInPath() == url else { throw CameraError.invalidPhotoData }
        return url
    }
    private func metadata(_ id: String) throws -> FilterPreset {
        let url = try directory(id).appendingPathComponent("preset.json")
        guard url.resolvingSymlinksInPath() == url else { throw CameraError.invalidPhotoData }
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let data = try handle.read(upToCount: 64 * 1024 + 1) ?? Data()
        guard data.count <= 64 * 1024 else { throw CameraError.invalidPhotoData }
        let preset = try JSONDecoder().decode(FilterPreset.self, from: data)
        guard preset.id == id, preset.version == 1 else { throw CameraError.invalidPhotoData }
        try preset.settings.validate()
        return preset
    }
}
