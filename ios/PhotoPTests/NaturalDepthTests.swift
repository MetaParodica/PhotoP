import XCTest
import CoreML
import CoreImage
import Metal
import ImageIO
import UniformTypeIdentifiers
@testable import PhotoP

final class NaturalDepthTests: XCTestCase {
    private func fixture() throws -> (root: URL, photo: URL, field: SoftwareDepthField) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        var pixels = [UInt8](repeating: 255, count: 256 * 192 * 4)
        for y in 0..<192 { for x in 0..<256 {
            let i = (y * 256 + x) * 4
            pixels[i] = x < 128 ? 180 : 20; pixels[i + 1] = 30
            pixels[i + 2] = x < 128 ? 30 : ((x + y) % 2 == 0 ? 30 : 240)
        } }
        let image = try SDRImage(rgba: Data(pixels), width: 256, height: 192).cgImage()
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil); XCTAssertTrue(CGImageDestinationFinalize(destination))
        let url = root.appendingPathComponent("original.png"); try (data as Data).write(to: url)
        let values = (0..<(16 * 12)).map { Float($0 % 16 < 8 ? 2 : 1) }
        return (root, url, try XCTUnwrap(SoftwareDepthField(width: 16, height: 12, inverseDepth: values, units: .relativeInverse)))
    }
    func testPinnedCompiledModelContractAndInference() throws {
        let input = try fixture()
        let image = try XCTUnwrap(CIImage(contentsOf: input.photo))
        let result = try ExternalDepthEstimator().estimate(image)
        let geometry = try XCTUnwrap(DepthModelGeometry(sourceWidth: 256, sourceHeight: 192))
        XCTAssertEqual(result.width, geometry.width); XCTAssertEqual(result.height, geometry.height)
        XCTAssertEqual(result.units, .relativeInverse)
        XCTAssertTrue(result.inverseDepth.contains(where: { $0 > 0 && $0.isFinite }))
    }
    func testNaturalRendererStoresDepthAndChangesBackgroundNotOriginal() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal unavailable") }
        let input = try fixture(), before = try Data(contentsOf: input.photo)
        let result = try await CaptureResultProcessor.shared.render(original: input.photo, look: nil, aperture: 1.4,
            focus: CGPoint(x: 0.25, y: 0.5), documents: input.root, depthOverride: input.field)
        XCTAssertEqual(try Data(contentsOf: input.photo), before)
        let folder = result.deletingLastPathComponent()
        let recipe = try JSONDecoder().decode(CaptureResultRecipe.self, from: Data(contentsOf: folder.appendingPathComponent("recipe.json")))
        XCTAssertEqual(recipe.version, 2); XCTAssertEqual(recipe.depthUnits, "relativeInverse")
        XCTAssertNil(recipe.focusDistanceMetres)
        let map = try Data(contentsOf: folder.appendingPathComponent("depth.f32"))
        XCTAssertEqual(map.count, 16 * 12 * 4); XCTAssertEqual(recipe.depthMapSHA256, LUTPhotoEditor.hash(map))
        let output = try SDRImage.decode(result)
        XCTAssertEqual(Double(output.rgba[(96 * 256 + 32) * 4]), 180, accuracy: 5)
        XCTAssertGreaterThan(Int(output.rgba[(96 * 256 + 200) * 4 + 2]), 70)
        let second = try await CaptureResultProcessor.shared.reprocess(result: result, original: input.photo, aperture: 8, documents: input.root)
        XCTAssertNotEqual(result, second); XCTAssertTrue(FileManager.default.fileExists(atPath: result.path))
        XCTAssertEqual(try Data(contentsOf: input.photo), before)
    }
    func testChangedDepthOrOriginalIsRejectedByReprocessor() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal unavailable") }
        let input = try fixture()
        let result = try await CaptureResultProcessor.shared.render(original: input.photo, look: nil, aperture: 2.8,
            focus: CGPoint(x: 0.25, y: 0.5), documents: input.root, depthOverride: input.field)
        let map = result.deletingLastPathComponent().appendingPathComponent("depth.f32")
        let beforeMap = try Data(contentsOf: map)
        var changed = beforeMap; changed[0] ^= 1; try changed.write(to: map)
        do {
            _ = try await CaptureResultProcessor.shared.reprocess(result: result, original: input.photo, aperture: 4, documents: input.root)
            XCTFail("Tampered depth must fail closed")
        } catch { }
        try beforeMap.write(to: map)
        var original = try Data(contentsOf: input.photo); original[0] ^= 1; try original.write(to: input.photo)
        do {
            _ = try await CaptureResultProcessor.shared.reprocess(result: result, original: input.photo, aperture: 4, documents: input.root)
            XCTFail("Changed original must fail closed")
        } catch { }
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.path))
    }
    func testUniformDepthFailsWithoutInventingBlur() throws {
        let input = try fixture(), image = try XCTUnwrap(CIImage(contentsOf: input.photo))
        let field = try XCTUnwrap(SoftwareDepthField(width: 3, height: 3, inverseDepth: Array(repeating: 1, count: 9), units: .relativeInverse))
        XCTAssertThrowsError(try NaturalDepthEngine().render(original: input.photo, color: image, width: 256, height: 192,
            aperture: 2.8, focus: CGPoint(x: 0.5, y: 0.5), source: .ai, override: field))
    }
    @MainActor func testOfflineManualAndExposureLocksAreNotChangedByAFOn() async {
        let model = CameraModel(); model.settings.focus.manual = true; model.settings.exposure.locked = true
        let before = model.settings
        await model.autofocusOn()
        XCTAssertEqual(model.settings, before)
        XCTAssertEqual(model.focusPhase, .manual)
    }
}
