import Foundation
import ImageIO
import UniformTypeIdentifiers
import CryptoKit

struct LongExposureRecipe: Codable, Sendable {
    struct Frame: Codable, Sendable { let filename: String; let sha256: String }
    let version: Int
    let configuration: LongExposureConfiguration
    let elapsed: Double
    let accepted: Int
    let rejected: Int
    let endedBy: String
    let frames: [Frame]
}

// A lossless sampled-frame archive, capped at 128 MiB. This is processed SDR
// video data, not sensor RAW or a continuous physical sensor exposure.
final class LongExposureArchive {
    static let maximumBytes = 128 * 1024 * 1024
    let root: URL
    private let pending: URL
    private let id = UUID().uuidString
    private var frames: [LongExposureRecipe.Frame] = []
    private var bytes = 0
    init(root: URL) throws {
        self.root = root
        pending = root.appendingPathComponent(".pending-" + id)
        try FileManager.default.createDirectory(at: pending, withIntermediateDirectories: true)
    }
    func append(_ image: SDRImage) throws -> Bool {
        guard frames.count < 1200 else { return false }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { throw CameraError.invalidPhotoData }
        CGImageDestinationAddImage(destination, try image.cgImage(), [kCGImagePropertyOrientation: 1] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CameraError.invalidPhotoData }
        guard data.length <= Self.maximumBytes - bytes else { return false }
        let filename = String(format: "%06d.png", frames.count)
        try (data as Data).write(to: pending.appendingPathComponent(filename), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        frames.append(.init(filename: filename, sha256: Self.hash(data as Data)))
        bytes += data.length
        return true
    }
    func finish(stack: LongExposureStack, elapsed: Double, reason: String) throws -> URL {
        guard stack.accepted >= 2, elapsed.isFinite, elapsed >= 0 else { throw ImageEditingError.invalid("합성에 유효한 프레임이 2장 이상 필요합니다.") }
        let recipe = LongExposureRecipe(version: 1, configuration: stack.configuration, elapsed: elapsed,
                                       accepted: stack.accepted, rejected: stack.rejected, endedBy: reason, frames: frames)
        try stack.image().jpeg().write(to: pending.appendingPathComponent("result.jpg"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try JSONEncoder().encode(recipe).write(to: pending.appendingPathComponent("recipe.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        let folder = root.appendingPathComponent(id)
        try FileManager.default.moveItem(at: pending, to: folder)
        return folder.appendingPathComponent("result.jpg")
    }
    func cancel() { try? FileManager.default.removeItem(at: pending) }
    private static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    static func reprocess(_ result: URL, configuration: LongExposureConfiguration) async throws -> URL {
        let task = Task.detached(priority: .utility) {
            try configuration.validate()
            let folder = result.deletingLastPathComponent().standardizedFileURL
            guard UUID(uuidString: folder.lastPathComponent) != nil, folder.resolvingSymlinksInPath() == folder else { throw CameraError.invalidPhotoData }
            let recipeURL = folder.appendingPathComponent("recipe.json")
            guard recipeURL.resolvingSymlinksInPath() == recipeURL else { throw CameraError.invalidPhotoData }
            let handle = try FileHandle(forReadingFrom: recipeURL)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: 512 * 1024 + 1) ?? Data()
            guard data.count <= 512 * 1024 else { throw CameraError.invalidPhotoData }
            let recipe = try JSONDecoder().decode(LongExposureRecipe.self, from: data)
            guard recipe.version == 1, (2...1200).contains(recipe.frames.count),
                  Set(recipe.frames.map(\.filename)).count == recipe.frames.count else { throw CameraError.invalidPhotoData }
            let archive = try LongExposureArchive(root: folder.deletingLastPathComponent())
            do {
                var stack: LongExposureStack?
                for frame in recipe.frames {
                    try Task.checkCancellation()
                    guard frame.filename.range(of: "^[0-9]{6}\\.png$", options: .regularExpression) != nil else { throw CameraError.invalidPhotoData }
                    let url = folder.appendingPathComponent(frame.filename)
                    guard url.resolvingSymlinksInPath() == url else { throw CameraError.invalidPhotoData }
                    let frameHandle = try FileHandle(forReadingFrom: url)
                    let bytes: Data
                    do { bytes = try frameHandle.read(upToCount: 16 * 1024 * 1024 + 1) ?? Data(); try frameHandle.close() }
                    catch { try? frameHandle.close(); throw error }
                    guard bytes.count <= 16 * 1024 * 1024, Self.hash(bytes) == frame.sha256 else { throw CameraError.invalidPhotoData }
                    let image = try SDRImage.decode(url)
                    guard try archive.append(image) else { throw ImageEditingError.invalid("재처리 저장 예산을 초과했습니다.") }
                    if stack == nil { stack = try LongExposureStack(first: image, configuration: configuration) }
                    else { try stack?.add(image) }
                }
                guard let stack else { throw CameraError.missingPhoto }
                return try archive.finish(stack: stack, elapsed: recipe.elapsed, reason: "reprocessed")
            } catch { archive.cancel(); throw error }
        }
        return try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
    }
}
