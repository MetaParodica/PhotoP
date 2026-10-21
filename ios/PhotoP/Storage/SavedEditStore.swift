import Foundation

struct SavedEditSummary: Identifiable, Sendable {
    let id: String
    let title: String
    let modified: Date
}
struct SavedEdit: Identifiable, Sendable {
    let id: String
    let original: URL
    let recipe: ImageProcessingRecipe
    let imported: ImportedLUT
}

actor SavedEditStore {
    static let shared = SavedEditStore(documents: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0])
    private let documents: URL
    init(documents: URL) { self.documents = documents.standardizedFileURL.resolvingSymlinksInPath() }

    func list() throws -> [SavedEditSummary] {
        let root = documents.appendingPathComponent("Edits", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        try requireLocal(root)
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
            .filter { UUID(uuidString: $0.lastPathComponent) != nil }
            .map { url in
                SavedEditSummary(id: url.lastPathComponent, title: "편집 " + String(url.lastPathComponent.prefix(8)),
                                 modified: (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
            }.sorted { $0.modified > $1.modified }
    }

    func open(_ id: String) throws -> SavedEdit {
        guard UUID(uuidString: id) != nil, !id.contains("/") else { throw ImageEditingError.invalid("편집 기록 ID가 유효하지 않습니다.") }
        let folder = documents.appendingPathComponent("Edits", isDirectory: true).appendingPathComponent(id, isDirectory: true)
        try requireLocal(folder)
        let data = try readBounded(folder.appendingPathComponent("recipe.json"), maximum: 64 * 1024)
        let recipe = try JSONDecoder().decode(ImageProcessingRecipe.self, from: data)
        guard [1, 2, 3].contains(recipe.version), recipe.intensity.isFinite, (0...1).contains(recipe.intensity),
              recipe.workingColorSpace == "encoded sRGB SDR", recipe.lutInputColorSpace == "sRGB",
              recipe.lutOutputColorSpace == "sRGB", recipe.outputColorSpace == "sRGB",
              !recipe.originalFilename.isEmpty, recipe.originalFilename != ".", recipe.originalFilename != "..",
              !recipe.originalFilename.contains("/"), !recipe.originalFilename.contains("\\"),
              !recipe.originalFilename.contains("\0"),
              (recipe.version == 1 ? recipe.grain == nil : recipe.grain != nil),
              (recipe.version < 3 ? recipe.finish == nil : recipe.finish != nil)
        else { throw ImageEditingError.invalid("지원하지 않거나 손상된 편집 레시피입니다.") }
        try (recipe.grain ?? GrainSettings()).validate()
        try (recipe.finish ?? FilmFinishSettings()).validate()
        let original = documents.appendingPathComponent("Originals", isDirectory: true).appendingPathComponent(recipe.originalFilename)
        try requireLocal(original)
        let cubeURL = folder.appendingPathComponent("look.cube")
        let cube = try readBounded(cubeURL, maximum: CubeLUT.maximumFileBytes)
        guard try LUTPhotoEditor.hashFile(original) == recipe.originalSHA256,
              LUTPhotoEditor.hash(cube) == recipe.lutSHA256 else {
            throw ImageEditingError.invalid("원본 또는 LUT 해시가 저장된 레시피와 다릅니다.")
        }
        if let provenance = recipe.provenance {
            guard provenance.renderLUTSHA256 == recipe.lutSHA256,
                  provenance.inputColorSpace == "sRGB", provenance.outputColorSpace == "sRGB" else { throw CameraError.invalidPhotoData }
        }
        guard let text = String(data: cube, encoding: .utf8) else { throw ImageEditingError.invalid("LUT UTF-8 데이터가 유효하지 않습니다.") }
        let lut = try CubeLUT.parse(text)
        return SavedEdit(id: id, original: original, recipe: recipe,
                         imported: ImportedLUT(data: cube, lut: lut, displayName: recipe.lutTitle ?? lut.title ?? "저장된 LUT", provenance: recipe.provenance))
    }

    private func requireLocal(_ url: URL) throws {
        let normalized = url.standardizedFileURL
        guard normalized.path.hasPrefix(documents.path + "/"),
              normalized.resolvingSymlinksInPath().path == normalized.path else {
            throw ImageEditingError.invalid("편집 파일 경로가 앱 문서 범위를 벗어나거나 링크를 포함합니다.")
        }
    }
    private func readBounded(_ url: URL, maximum: Int) throws -> Data {
        try requireLocal(url)
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let data = try file.read(upToCount: maximum + 1) ?? Data()
        guard !data.isEmpty, data.count <= maximum else { throw ImageEditingError.invalid("편집 파일 크기가 유효하지 않습니다.") }
        return data
    }
}
