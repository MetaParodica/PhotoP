#if DEBUG && targetEnvironment(simulator)
import SwiftUI

/// A deterministic UI-test barrier around the production editor's real save.
/// No camera capability is fabricated; this host cannot enter a device/release build.
private actor DepthEditorReviewGate {
    private var released = false
    func wait() async throws {
        while !released { try await Task.sleep(for: .milliseconds(25)) }
        try Task.checkCancellation()
    }
    func release() { released = true }
}

@MainActor
struct DepthEditorReviewFixture: View {
    @State private var session: DepthEditSession?
    @State private var failure: String?
    @State private var gate = DepthEditorReviewGate()
    var body: some View {
        Group {
            if let session {
                DepthResultEditorView(session: session, beforeSave: { [gate] in try await gate.wait() })
                    .safeAreaInset(edge: .top) {
                        Button("UI 검증 · 저장 계속") { Task { await gate.release() } }
                            .accessibilityIdentifier("editor.review.releaseSave")
                    }
            } else if let failure { Text(failure).accessibilityIdentifier("editor.review.failure") }
            else { ProgressView("검증용 사진 준비") }
        }.task {
            guard session == nil else { return }
            do { session = try await makeSession() } catch { failure = error.localizedDescription }
        }
    }
    private func makeSession() async throws -> DepthEditSession {
        let root = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let originals = root.appendingPathComponent("Originals")
        let folder = root.appendingPathComponent("CaptureResults").appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let original = originals.appendingPathComponent("ui-review-depth-" + UUID().uuidString + ".jpg")
        var bytes = [UInt8]()
        bytes.reserveCapacity(64 * 64 * 4)
        for y in 0..<64 { for x in 0..<64 {
            bytes.append(UInt8(30 + x * 3)); bytes.append(UInt8(40 + y * 2))
            bytes.append(110); bytes.append(255)
        } }
        let jpeg: Data = try SDRImage(rgba: Data(bytes), width: 64, height: 64).jpeg()
        try jpeg.write(to: original, options: Data.WritingOptions.atomic)
        let result = folder.appendingPathComponent("photo.jpg")
        try jpeg.write(to: result, options: Data.WritingOptions.atomic)
        let values = (0..<81).map { Float(1 + $0 % 9) }
        var depth = Data()
        for value in values {
            var bits = value.bitPattern.littleEndian
            withUnsafeBytes(of: &bits) { depth.append(contentsOf: $0) }
        }
        try depth.write(to: folder.appendingPathComponent("depth.f32"), options: .atomic)
        var recipe = CaptureResultRecipe(version: 3, originalFilename: original.lastPathComponent,
            originalSHA256: LUTPhotoEditor.hash(jpeg), aperture: 2.8, focusX: 0.5, focusY: 0.5,
            focusDistanceMetres: nil, focusDepthValue: nil, depthAccuracy: "relative",
            look: nil, lutSHA256: nil, provenance: nil, pipeline: "Simulator UI fixture; SDR; original preserved")
        recipe.depthMapFilename = "depth.f32"; recipe.depthMapSHA256 = LUTPhotoEditor.hash(depth)
        recipe.depthWidth = 9; recipe.depthHeight = 9; recipe.depthUnits = SoftwareDepthField.Units.relativeInverse.rawValue
        recipe.lensProfile = DepthLensProfile.natural
        try JSONEncoder().encode(recipe).write(to: folder.appendingPathComponent("recipe.json"), options: .atomic)
        return try await CaptureResultProcessor.shared.loadSession(result: result, original: original)
    }
    static func removePriorFixtures() {
        guard let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let results = root.appendingPathComponent("CaptureResults")
        for folder in (try? FileManager.default.contentsOfDirectory(at: results, includingPropertiesForKeys: nil)) ?? [] {
            guard UUID(uuidString: folder.lastPathComponent) != nil,
                  let data = try? Data(contentsOf: folder.appendingPathComponent("recipe.json")),
                  let recipe = try? JSONDecoder().decode(CaptureResultRecipe.self, from: data),
                  recipe.originalFilename.hasPrefix("ui-review-depth-") else { continue }
            try? FileManager.default.removeItem(at: folder)
        }
        let originals = root.appendingPathComponent("Originals")
        for file in (try? FileManager.default.contentsOfDirectory(at: originals, includingPropertiesForKeys: nil)) ?? [] where file.lastPathComponent.hasPrefix("ui-review-depth-") {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
#endif
