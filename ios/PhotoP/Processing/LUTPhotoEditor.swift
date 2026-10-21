import Foundation
import CryptoKit

struct ImageProcessingRecipe: Codable, Sendable {
    let version: Int
    let originalFilename: String
    let originalSHA256: String
    let lutSHA256: String
    let lutTitle: String?
    let intensity: Double
    let workingColorSpace: String
    let lutInputColorSpace: String
    let lutOutputColorSpace: String
    let outputColorSpace: String
    let pipeline: String
    var grain: GrainSettings? = nil
    var finish: FilmFinishSettings? = nil
    var provenance: LUTProvenance? = nil
}

// Separate actor for file decoding/encoding; the renderer owns GPU resources.
actor LUTPhotoEditor {
    private let original: URL
    private var preview: SDRImage?
    private var renderer: MetalLUTRenderer?
    private var cubeData: Data?
    private var lut: CubeLUT?
    private var lutDisplayName: String?
    private var provenance: LUTProvenance?

    init(original: URL) { self.original = original }

    func loadOriginal() throws -> SDRImage {
        let image = try SDRImage.decode(original, previewMaxDimension: 1024)
        preview = image
        return image
    }

    func importCube(_ url: URL) throws -> String {
        try useLUT(ImportedLUT.read(url))
    }

    func useLUT(_ imported: ImportedLUT) throws -> String {
        let next = try MetalLUTRenderer(lut: imported.lut)
        lut = imported.lut
        lutDisplayName = imported.displayName
        renderer = next
        cubeData = imported.data
        provenance = imported.provenance
        return imported.displayName
    }

    func favoriteCurrent() async throws {
        guard let cubeData, let lut else { throw ImageEditingError.invalid("LUT를 먼저 불러오세요.") }
        let imported = ImportedLUT(data: cubeData, lut: lut, displayName: lutDisplayName ?? lut.title ?? "사용자 LUT", provenance: provenance)
        try await LUTLibrary.shared.save(imported)
    }

    func savePreset(name: String, settings: ProcessingLookSettings) async throws {
        guard let cubeData, let lut else { throw CameraError.invalidPhotoData }
        let imported = ImportedLUT(data: cubeData, lut: lut, displayName: lutDisplayName ?? "사용자 LUT", provenance: provenance)
        try await FilterPresetLibrary.shared.save(imported, settings: settings, name: name)
    }

    func renderPreview(intensity: Double, grain: GrainSettings = GrainSettings(), effects: FilmFinishSettings = FilmFinishSettings()) async throws -> SDRImage {
        guard let preview, let renderer else { throw ImageEditingError.invalid("원본과 LUT를 먼저 불러오세요.") }
        let data = try await renderer.render(preview.rgba, width: preview.width, height: preview.height, intensity: intensity, grain: grain, effects: effects)
        return SDRImage(rgba: data, width: preview.width, height: preview.height)
    }

    func export(intensity: Double, grain: GrainSettings = GrainSettings(), effects: FilmFinishSettings = FilmFinishSettings()) async throws -> URL {
        guard let renderer, let cubeData, let lut else { throw ImageEditingError.invalid("LUT를 먼저 불러오세요.") }
        let source = try SDRImage.decode(original)
        let pixels = try await renderer.render(source.rgba, width: source.width, height: source.height, intensity: intensity, grain: grain, effects: effects)
        let image = SDRImage(rgba: pixels, width: source.width, height: source.height)
        var recipe = ImageProcessingRecipe(version: 3, originalFilename: original.lastPathComponent,
                                            originalSHA256: try Self.hashFile(original), lutSHA256: Self.hash(cubeData),
                                            lutTitle: lut.title, intensity: intensity, workingColorSpace: "encoded sRGB SDR",
                                            lutInputColorSpace: "sRGB", lutOutputColorSpace: "sRGB", outputColorSpace: "sRGB",
                                            pipeline: "SDR base decode + EXIF orientation → ICC to sRGB → channel-linear 1D / trilinear 3D LUT → strength mix → deterministic monochrome grain v1 (512-cell long edge, seed) → creative fade/vignette/8-tap bloom/red halation v1 → SDR clamp → JPEG 0.95; original metadata omitted; LUT attribution caption when available")
        recipe.grain = grain
        recipe.finish = effects
        recipe.provenance = provenance
        let folder = original.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Edits", isDirectory: true)
        let credit = provenance.map { "\($0.requiredCredit)\nSource: \($0.source)\n\($0.previewDescription)" }
        return try Self.writeBundle(jpeg: image.jpeg(credit: credit), cube: cubeData, recipe: recipe, in: folder)
    }

    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func hashFile(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while let data = try file.read(upToCount: 64 * 1024), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func writeBundle(jpeg: Data, cube: Data, recipe: ImageProcessingRecipe, in folder: URL) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let id = UUID().uuidString
        let temporary = folder.appendingPathComponent(".pending-" + id, isDirectory: true)
        let destination = folder.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
        do {
            let options: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            try jpeg.write(to: temporary.appendingPathComponent("photo.jpg"), options: options)
            try cube.write(to: temporary.appendingPathComponent("look.cube"), options: options)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(recipe).write(to: temporary.appendingPathComponent("recipe.json"), options: options)
            try FileManager.default.moveItem(at: temporary, to: destination)
            return destination.appendingPathComponent("photo.jpg")
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }
}
