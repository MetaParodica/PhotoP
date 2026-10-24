import XCTest
import ImageIO
import UniformTypeIdentifiers
import Metal
@testable import PhotoP

final class CaptureResultTests: XCTestCase {
    private func identity() throws -> ImportedLUT {
        var lines = ["LUT_3D_SIZE 2"]
        for b in 0...1 { for g in 0...1 { for r in 0...1 { lines.append("\(r) \(g) \(b)") } } }
        let text = lines.joined(separator: "\n")
        return ImportedLUT(data: Data(text.utf8), lut: try CubeLUT.parse(text), displayName: "Fixture")
    }
    private func fixture() throws -> (root: URL, photo: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let pixels = SDRImage(rgba: Data((0..<64).map { $0 % 4 == 3 ? UInt8(255) : UInt8(180) }), width: 4, height: 4)
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try pixels.cgImage(), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let url = root.appendingPathComponent("original.png")
        try (data as Data).write(to: url)
        return (root, url)
    }
    @MainActor func testOfflineLookSelectionDoesNotInventAFrameOrChangeManualSettings() async throws {
        let model = CameraModel()
        model.settings.exposure.manual = true; model.settings.exposure.iso = 321
        model.guideAIEnabled = true; model.monitoring.histogram = true
        let previous = model.settings
        try await model.useLiveLUT(identity())
        XCTAssertNil(model.livePreview)
        XCTAssertTrue(model.liveUsesLUT); XCTAssertEqual(model.liveLUTTitle, "Fixture")
        XCTAssertEqual(model.settings, previous)
        await model.selectOriginalLook()
        XCTAssertFalse(model.liveUsesLUT); XCTAssertNil(model.liveLUTTitle)
        XCTAssertTrue(model.guideAIEnabled); XCTAssertTrue(model.monitoring.histogram)
        XCTAssertEqual(model.settings, previous)
    }
    @MainActor func testOriginalComparisonDoesNotChangeSelectedCapturePreset() async throws {
        let model = CameraModel()
        var look = try identity()
        look.preset = .init(intensity: 0.7, grain: .init(amount: 0.2, seed: 8), finish: .init(vignette: 0.4))
        try await model.useLiveLUT(look)
        model.liveCompareOriginal = true; model.updateLiveIntensity()
        XCTAssertTrue(model.liveUsesLUT); XCTAssertEqual(model.liveIntensity, 0.7)
        XCTAssertEqual(model.liveGrain, 0.2); XCTAssertEqual(model.liveFinish.vignette, 0.4)
        XCTAssertTrue(model.captureLookNotice.contains("원본 비교"))
        model.disableLiveLUT() // Analysis-off must not turn a selected look off.
        XCTAssertTrue(model.liveUsesLUT); XCTAssertFalse(model.guideAIEnabled)
        XCTAssertFalse(model.monitoring.enabled)
    }
    func testMissingDepthRejectsEffectAndKeepsOriginalBytes() async throws {
        let input = try fixture(), before = try Data(contentsOf: input.photo)
        do {
            _ = try await CaptureResultProcessor.shared.render(original: input.photo, look: nil, aperture: 2.8,
                                                              focus: CGPoint(x: 0.5, y: 0.5), documents: input.root)
            XCTFail("A regular image without measured depth must not produce a fake depth effect")
        } catch { XCTAssertTrue(error.localizedDescription.contains("깊이")) }
        XCTAssertEqual(try Data(contentsOf: input.photo), before)
        let folder = input.root.appendingPathComponent("CaptureResults")
        if FileManager.default.fileExists(atPath: folder.path) {
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
        }
    }
    func testCaptureLookCreatesSeparateResultAndReproductionAssets() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal unavailable") }
        let input = try fixture(), before = try Data(contentsOf: input.photo), look = try identity()
        let output = try await CaptureResultProcessor.shared.render(original: input.photo, look: look, aperture: nil,
                                                                   focus: CGPoint(x: 0.5, y: 0.5), documents: input.root)
        XCTAssertNotEqual(output, input.photo)
        XCTAssertEqual(try Data(contentsOf: input.photo), before)
        let recipe = try JSONDecoder().decode(CaptureResultRecipe.self, from: Data(contentsOf: output.deletingLastPathComponent().appendingPathComponent("recipe.json")))
        XCTAssertEqual(recipe.originalSHA256, LUTPhotoEditor.hash(before))
        XCTAssertEqual(recipe.lutSHA256, LUTPhotoEditor.hash(look.data)); XCTAssertNil(recipe.aperture)
        XCTAssertEqual(try Data(contentsOf: output.deletingLastPathComponent().appendingPathComponent("look.cube")), look.data)
        let rendered = try SDRImage.decode(output)
        XCTAssertEqual(rendered.width, 4); XCTAssertEqual(rendered.height, 4)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: input.root.appendingPathComponent("CaptureResults").path).contains { $0.hasPrefix(".pending-") })
    }
    func testNoEffectsDoesNotCreateOrRewriteAFile() async throws {
        let input = try fixture(), before = try Data(contentsOf: input.photo)
        let output = try await CaptureResultProcessor.shared.render(original: input.photo, look: nil, aperture: nil,
                                                                   focus: CGPoint(x: 0.5, y: 0.5), documents: input.root)
        XCTAssertEqual(output, input.photo)
        XCTAssertEqual(try Data(contentsOf: input.photo), before)
    }
    func testNonIdentityCaptureLookChangesPixelsAndKeepsOriginal() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal unavailable") }
        let input = try fixture(), before = try Data(contentsOf: input.photo)
        var lines = ["LUT_3D_SIZE 2"]
        for b in 0...1 { for g in 0...1 { for r in 0...1 { lines.append("\(1-r) \(1-g) \(1-b)") } } }
        let text = lines.joined(separator: "\n")
        let look = ImportedLUT(data: Data(text.utf8), lut: try CubeLUT.parse(text), displayName: "Negative")
        let output = try await CaptureResultProcessor.shared.render(original: input.photo, look: look, aperture: nil,
            focus: CGPoint(x: 0.5, y: 0.5), documents: input.root)
        let pixels = try SDRImage.decode(output)
        XCTAssertEqual(Double(pixels.rgba[0]), 75, accuracy: 3)
        XCTAssertEqual(try Data(contentsOf: input.photo), before)
    }
}
