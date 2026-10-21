import Foundation

struct BundledFilmStyle: Decodable, Identifiable, Sendable {
    let id: String
    let file: String
    let name: String
    let category: String
    let detail: String
    let creator: String
    let source: String
    let license: String
    let licenseFile: String
    let licenseSHA256: String
    let commercialUseAllowed: Bool
    let redistributionAllowed: Bool
    let requiredCredit: String
    let inputProfile: String
    let outputProfile: String
    let profileBasis: String
    let requiresSRGBConfirmation: Bool
    let sha256: String
    let previewColors: [[Double]]
}
enum BundledFilmLibrary {
    private struct Manifest: Decodable { let schemaVersion: Int; let assets: [BundledFilmStyle] }
    static func root() throws -> URL {
        guard let url = Bundle.main.url(forResource: "luts", withExtension: nil) else { throw ImageEditingError.invalid("번들 룩 리소스를 찾을 수 없습니다.") }
        return url
    }
    static func entries(in root: URL) throws -> [BundledFilmStyle] {
        let data = try Data(contentsOf: root.appendingPathComponent("manifest.json"), options: .mappedIfSafe)
        guard data.count <= 256 * 1024 else { throw CameraError.invalidPhotoData }
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        guard manifest.schemaVersion == 1, manifest.assets.count <= 100,
              Set(manifest.assets.map(\.id)).count == manifest.assets.count else { throw CameraError.invalidPhotoData }
        for entry in manifest.assets {
            guard entry.commercialUseAllowed, entry.redistributionAllowed, !entry.license.isEmpty, !entry.requiredCredit.isEmpty,
                  entry.inputProfile == "sRGB", entry.outputProfile == "sRGB",
                  entry.profileBasis != "assumed-sRGB" || entry.requiresSRGBConfirmation,
                  entry.previewColors.count == FilmStyle.chart.count,
                  entry.previewColors.allSatisfy({ $0.count == 3 && $0.allSatisfy { $0.isFinite && (0...1).contains($0) } }) else { throw CameraError.invalidPhotoData }
            _ = try local(entry.file, root: root); _ = try local(entry.licenseFile, root: root)
        }
        return manifest.assets
    }
    static func load(_ entry: BundledFilmStyle, in root: URL, confirmedSRGB: Bool) throws -> ImportedLUT {
        guard !entry.requiresSRGBConfirmation || confirmedSRGB else { throw ImageEditingError.invalid("외부 룩은 원본 색공간이 미기재되어 sRGB SDR 해석 확인이 필요합니다.") }
        guard entry.commercialUseAllowed, entry.redistributionAllowed,
              entry.inputProfile == "sRGB", entry.outputProfile == "sRGB" else { throw CameraError.invalidPhotoData }
        let license = try local(entry.licenseFile, root: root)
        guard try LUTPhotoEditor.hashFile(license) == entry.licenseSHA256 else { throw ImageEditingError.invalid("라이선스 파일 해시가 다릅니다.") }
        let imported = try ImportedLUT.read(local(entry.file, root: root))
        guard LUTPhotoEditor.hash(imported.data) == entry.sha256 else { throw ImageEditingError.invalid("번들 LUT 파일 해시가 다릅니다.") }
        let provenance = LUTProvenance(identifier: entry.id, name: entry.name, creator: entry.creator, source: entry.source,
            kind: "creator-published/\(entry.profileBasis)", license: entry.license, commercialUseAllowed: true, redistributionAllowed: true,
            inputColorSpace: "sRGB", outputColorSpace: "sRGB", requiredCredit: entry.requiredCredit,
            sourceSHA256: entry.sha256, renderLUTSHA256: entry.sha256, minimumIntensity: 0, maximumIntensity: 1,
            previewDescription: "Generated patches; input/output \(entry.profileBasis); original LUT unmodified")
        return ImportedLUT(data: imported.data, lut: imported.lut, displayName: entry.name, preset: .init(), provenance: provenance)
    }
    private static func local(_ file: String, root: URL) throws -> URL {
        let base = root.standardizedFileURL.resolvingSymlinksInPath()
        let url = base.appendingPathComponent(file).standardizedFileURL
        guard !file.hasPrefix("/"), !file.split(separator: "/").contains(".."),
              url.path.hasPrefix(base.path + "/"), url.resolvingSymlinksInPath() == url else { throw CameraError.invalidPhotoData }
        return url
    }
}
