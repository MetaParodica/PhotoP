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
    let license: String?
    let commercialUseAllowed: Bool?
    let redistributionAllowed: Bool?
    let previewColors: [[Double]]
    var canApply: Bool { (nativeInput == "srgb-assumed" && nativeOutput == "srgb-assumed") || (nativeInput == "vlog-vgamut" && nativeOutput == "rec709-gamma24-assumed") }
    var rightsConfirmed: Bool { rightsStatus == "user-confirmed" && license == "USER-CONFIRMED-PERMISSION" && commercialUseAllowed == true && redistributionAllowed == true }
}
enum CompanyFilmLibrary {
    private struct Confirmation: Decodable {
        let confirmedBy: String
        let confirmedOn: String
        let basis: String
        var valid: Bool { confirmedBy == "project-owner" && confirmedOn == "2026-10-23" && !basis.isEmpty && basis.count <= 2000 }
    }
    private struct Manifest: Decodable { let schemaVersion: Int; let assets: [CompanyFilmStyle]; let rightsConfirmation: Confirmation? }
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
        if manifest.assets.contains(where: \.rightsConfirmed), manifest.rightsConfirmation?.valid != true { throw CameraError.invalidPhotoData }
        for e in manifest.assets {
            let legacyUnknown = e.rightsStatus == "unverified" && e.license == nil && e.commercialUseAllowed == nil && e.redistributionAllowed == nil
            guard !e.official, e.rightsConfirmed || legacyUnknown, e.sha256.count == 64,
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
    private struct Record: Codable { let version: String; let sourceSHA256: String; let renderSHA256: String; var runtimeSHA256: String? = nil }
    init(folder: URL) { self.folder = folder }
    func load(_ entry: CompanyFilmStyle, in root: URL) throws -> ImportedLUT {
        let span = ProcessingTrace.begin("Load company LUT")
        defer { ProcessingTrace.end("Load company LUT", span) }
        return try LUTTextEncoder.temporaryPool { try compile(entry, in: root) }
    }
    private func compile(_ entry: CompanyFilmStyle, in root: URL) throws -> ImportedLUT {
        guard entry.canApply else { throw ImageEditingError.invalid("이 기술 변환의 출력 프로파일이 확인되지 않아 원본만 제공합니다.") }
        let sourceData = try ImportedLUT.readData(CompanyFilmLibrary.original(entry, in: root))
        guard LUTPhotoEditor.hash(sourceData) == entry.sha256 else { throw ImageEditingError.invalid("외부 LUT 원본 해시가 다릅니다.") }
        let data: Data, lut: CubeLUT
        if entry.nativeInput == "srgb-assumed" { data = sourceData; lut = try nativeTable(sourceData, hash: entry.sha256) }
        else {
            let key = entry.sha256 + "-" + SDRVendorAdapter.version
            let file = folder.appendingPathComponent(key + ".cube"), record = folder.appendingPathComponent(key + ".json")
            let binary = folder.appendingPathComponent(key + ".lut64")
            if let cached = try? cached(file: file, record: record, binary: binary, source: entry.sha256) { data = cached.data; lut = cached.lut }
            else {
                let source = try CubeLUT.parse(String(decoding: sourceData, as: UTF8.self))
                data = try SDRVendorAdapter.bake(source, sourceSHA256: entry.sha256)
                lut = try CubeLUT.parse(String(decoding: data, as: UTF8.self))
                let runtime = try LUTBinaryCodec.encode(lut)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let options: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
                try data.write(to: file, options: options)
                try runtime.write(to: binary, options: options)
                try JSONEncoder().encode(Record(version: SDRVendorAdapter.version, sourceSHA256: entry.sha256, renderSHA256: LUTPhotoEditor.hash(data), runtimeSHA256: LUTPhotoEditor.hash(runtime))).write(to: record, options: options)
            }
        }
        let rights = entry.rightsConfirmed ? "permission confirmed by project owner, 2026-10-23; not an independent license audit" : "rights unverified"
        let note = "Unofficial third-party derivative; \(rights); \(entry.nativeInput) → \(entry.nativeOutput); PhotoP SDR adaptation; not camera/sensor emulation"
        let provenance = LUTProvenance(identifier: entry.id, name: entry.name, creator: "Third-party source / \(entry.brand)", source: entry.source,
            kind: entry.rightsConfirmed ? "unofficial-derivative/user-confirmed-permission" : "unofficial-derivative/rights-unverified",
            license: entry.license ?? "UNVERIFIED", commercialUseAllowed: entry.commercialUseAllowed ?? false, redistributionAllowed: entry.redistributionAllowed ?? false,
            inputColorSpace: "sRGB", outputColorSpace: "sRGB", requiredCredit: "Source: \(entry.source) · \(note)",
            sourceSHA256: entry.sha256, renderLUTSHA256: LUTPhotoEditor.hash(data), minimumIntensity: 0, maximumIntensity: 1, previewDescription: note)
        return ImportedLUT(data: data, lut: lut, displayName: entry.name + " · SDR 파생", preset: .init(), provenance: provenance)
    }
    private func readRecord(_ record: URL) throws -> Record {
        let handle = try FileHandle(forReadingFrom: record); defer { try? handle.close() }
        let metadata = try handle.read(upToCount: 4097) ?? Data()
        guard metadata.count <= 4096 else { throw CameraError.invalidPhotoData }
        return try JSONDecoder().decode(Record.self, from: metadata)
    }
    private func nativeTable(_ source: Data, hash: String) throws -> CubeLUT {
        let version = "srgb-passthrough-v1", key = hash + "-native"
        let binary = folder.appendingPathComponent(key + ".lut64"), record = folder.appendingPathComponent(key + ".json")
        if let entry = try? readRecord(record), entry.version == version,
           entry.sourceSHA256 == hash, entry.renderSHA256 == hash, let expected = entry.runtimeSHA256,
           let bytes = try? ImportedLUT.readData(binary), LUTPhotoEditor.hash(bytes) == expected,
           let table = try? LUTBinaryCodec.decode(bytes) { return table }
        // The bundled source has already been hash-verified. It remains the
        // export representation; no duplicate .cube is needed for passthrough.
        let table = try CubeLUT.parse(String(decoding: source, as: UTF8.self))
        let bytes = try LUTBinaryCodec.encode(table)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let options: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        try bytes.write(to: binary, options: options)
        try JSONEncoder().encode(Record(version: version, sourceSHA256: hash, renderSHA256: hash,
            runtimeSHA256: LUTPhotoEditor.hash(bytes))).write(to: record, options: options)
        return table
    }
    private func cached(file: URL, record: URL, binary: URL, source: String) throws -> ImportedLUT {
        var entry = try readRecord(record)
        let data = try ImportedLUT.readData(file)
        guard entry.version == SDRVendorAdapter.version, entry.sourceSHA256 == source, LUTPhotoEditor.hash(data) == entry.renderSHA256 else { throw CameraError.invalidPhotoData }
        let lut: CubeLUT
        if let expected = entry.runtimeSHA256, let runtime = try? ImportedLUT.readData(binary), LUTPhotoEditor.hash(runtime) == expected,
           let decoded = try? LUTBinaryCodec.decode(runtime) { lut = decoded }
        else {
            // Upgrade a valid old text cache or repair only its derived binary.
            lut = try CubeLUT.parse(String(decoding: data, as: UTF8.self))
            let runtime = try LUTBinaryCodec.encode(lut)
            entry.runtimeSHA256 = LUTPhotoEditor.hash(runtime)
            let options: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            try runtime.write(to: binary, options: options)
            try JSONEncoder().encode(entry).write(to: record, options: options)
        }
        return ImportedLUT(data: data, lut: lut, displayName: "캐시된 룩")
    }
}
