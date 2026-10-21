import Foundation

struct CompanyFilmStyle: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let brand: String
    let category: String
    let role: String
    let file: String
    let source: String
    let sourceRevision: String
    let sha256: String
    let nativeInput: String
    let nativeOutput: String
    let rightsStatus: String
    let official: Bool
    let previewColors: [[Double]]
    var canApply: Bool { (nativeInput == "srgb-assumed" && nativeOutput == "srgb-assumed") || (nativeInput == "vlog-vgamut" && nativeOutput == "rec709-gamma24-assumed") }
}
enum CompanyFilmLibrary {
    private struct Manifest: Decodable { let schemaVersion: Int; let assets: [CompanyFilmStyle] }
    static func root() throws -> URL {
        guard let url = Bundle.main.url(forResource: "company-luts", withExtension: nil) else { throw CameraError.invalidPhotoData }
        return url
    }
    static func entries(in root: URL) throws -> [CompanyFilmStyle] {
        let handle = try FileHandle(forReadingFrom: root.appendingPathComponent("manifest.json")); defer { try? handle.close() }
        let data = try handle.read(upToCount: 256 * 1024 + 1) ?? Data()
        guard data.count <= 256 * 1024 else { throw CameraError.invalidPhotoData }
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        guard manifest.schemaVersion == 1, manifest.assets.count <= 100, Set(manifest.assets.map(\.id)).count == manifest.assets.count else { throw CameraError.invalidPhotoData }
        for e in manifest.assets {
            guard !e.official, e.rightsStatus == "unverified", e.sha256.count == 64,
                  e.sha256.allSatisfy({ "0123456789abcdef".contains($0) }),
                  ["creative", "technical"].contains(e.role), !e.source.isEmpty,
                  e.previewColors.count == FilmStyle.chart.count,
                  e.previewColors.allSatisfy({ $0.count == 3 && $0.allSatisfy { $0.isFinite && (0...1).contains($0) } }) else { throw CameraError.invalidPhotoData }
            _ = try original(e, in: root)
        }
        return manifest.assets
    }
    static func original(_ entry: CompanyFilmStyle, in root: URL) throws -> URL {
        let base = root.standardizedFileURL.resolvingSymlinksInPath(), file = entry.file
        let url = base.appendingPathComponent(file).standardizedFileURL
        guard !file.hasPrefix("/"), !file.split(separator: "/").contains(".."),
              url.path.hasPrefix(base.path + "/"), url.resolvingSymlinksInPath() == url else { throw CameraError.invalidPhotoData }
        return url
    }
}
actor CompanyLookCompiler {
    static let shared = CompanyLookCompiler(folder: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("CompiledCompanyLooks"))
    private let folder: URL
    private struct Record: Codable { let version: String; let sourceSHA256: String; let renderSHA256: String }
    init(folder: URL) { self.folder = folder }
    func load(_ entry: CompanyFilmStyle, in root: URL) throws -> ImportedLUT {
        guard entry.canApply else { throw ImageEditingError.invalid("이 기술 변환의 출력 프로파일이 확인되지 않아 원본만 제공합니다.") }
        let raw = try ImportedLUT.read(CompanyFilmLibrary.original(entry, in: root))
        guard LUTPhotoEditor.hash(raw.data) == entry.sha256 else { throw ImageEditingError.invalid("외부 LUT 원본 해시가 다릅니다.") }
        let data: Data, lut: CubeLUT
        if entry.nativeInput == "srgb-assumed" { data = raw.data; lut = raw.lut }
        else {
            let key = entry.sha256 + "-" + SDRVendorAdapter.version
            let file = folder.appendingPathComponent(key + ".cube"), record = folder.appendingPathComponent(key + ".json")
            if let cached = try? cached(file: file, record: record, source: entry.sha256) { data = cached.data; lut = cached.lut }
            else {
                data = try SDRVendorAdapter.bake(raw.lut, sourceSHA256: entry.sha256)
                lut = try CubeLUT.parse(String(decoding: data, as: UTF8.self))
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let options: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
                try data.write(to: file, options: options)
                try JSONEncoder().encode(Record(version: SDRVendorAdapter.version, sourceSHA256: entry.sha256, renderSHA256: LUTPhotoEditor.hash(data))).write(to: record, options: options)
            }
        }
        let note = "Unofficial third-party derivative; rights unverified; \(entry.nativeInput) → \(entry.nativeOutput); PhotoP SDR adaptation; not camera/sensor emulation"
        let provenance = LUTProvenance(identifier: entry.id, name: entry.name, creator: "Third-party source / \(entry.brand)", source: entry.source,
            kind: "unofficial-derivative/rights-unverified", license: "UNVERIFIED", commercialUseAllowed: false, redistributionAllowed: false,
            inputColorSpace: "sRGB", outputColorSpace: "sRGB", requiredCredit: "Source: \(entry.source) · \(note)",
            sourceSHA256: entry.sha256, renderLUTSHA256: LUTPhotoEditor.hash(data), minimumIntensity: 0, maximumIntensity: 1, previewDescription: note)
        return ImportedLUT(data: data, lut: lut, displayName: entry.name + " · SDR 파생", preset: .init(), provenance: provenance)
    }
    private func cached(file: URL, record: URL, source: String) throws -> ImportedLUT {
        let handle = try FileHandle(forReadingFrom: record); defer { try? handle.close() }
        let metadata = try handle.read(upToCount: 4097) ?? Data()
        guard metadata.count <= 4096 else { throw CameraError.invalidPhotoData }
        let entry = try JSONDecoder().decode(Record.self, from: metadata)
        let imported = try ImportedLUT.read(file)
        guard entry.version == SDRVendorAdapter.version, entry.sourceSHA256 == source, LUTPhotoEditor.hash(imported.data) == entry.renderSHA256 else { throw CameraError.invalidPhotoData }
        return imported
    }
}
