import XCTest
import CoreImage
import ImageIO
import Metal
@testable import PhotoP

// Apple SDK/runtime tests, not part of the portable policy test suite.
final class HighResolutionProcessingTests: XCTestCase {
    private func folder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    private func lut() throws -> CubeLUT {
        var lines = ["LUT_3D_SIZE 2"]
        for b in 0...1 { for g in 0...1 { for r in 0...1 { lines.append("\(b) \(g) \(r)") } } }
        return try CubeLUT.parse(lines.joined(separator: "\n"))
    }
    private func fixture(_ root: URL, width: Int, height: Int) throws -> URL {
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        let base = CIImage(color: CIColor(red: 0.2, green: 0.4, blue: 0.7)).cropped(to: rect)
        let topLeft = CIImage(color: CIColor(red: 0.9, green: 0.2, blue: 0.1))
            .cropped(to: CGRect(x: 0, y: height / 2, width: width / 2, height: height - height / 2))
        let source = topLeft.composited(over: base)
        let file = root.appendingPathComponent(UUID().uuidString + ".png")
        try CIContext(options: [.cacheIntermediates: false]).writePNGRepresentation(of: source, to: file,
            format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        return file
    }
    func test24And48MPExportKeepsDimensionsAndOriginalHash() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal unavailable") }
        let root = try folder()
        for (width, height) in [(5712, 4284), (8064, 6048)] {
            let original = try fixture(root, width: width, height: height)
            let hash = try LUTPhotoEditor.hashFile(original)
            let output = root.appendingPathComponent(UUID().uuidString + ".jpg")
            let result = try await HighResolutionPhotoProcessor.shared.renderJPEG(original: original, destination: output,
                lut: lut(), settings: ProcessingLookSettings(grain: .init(amount: 0.1, seed: 4), finish: .init(vignette: 0.2)))
            XCTAssertEqual(result.width, width); XCTAssertEqual(result.height, height)
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
            let facts = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
            XCTAssertEqual(facts[kCGImagePropertyPixelWidth] as? Int, width)
            XCTAssertEqual(facts[kCGImagePropertyPixelHeight] as? Int, height)
            XCTAssertEqual(try LUTPhotoEditor.hashFile(original), hash)
        }
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".raster-") })
    }
    func testTiledDecodeDoesNotFlipQuadrantsOrSwapLUTChannels() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal unavailable") }
        let root = try folder(), original = try fixture(root, width: 2050, height: 2050)
        let output = root.appendingPathComponent("photo.jpg")
        _ = try await HighResolutionPhotoProcessor.shared.renderJPEG(original: original, destination: output, lut: lut(), settings: .init())
        let preview = try SDRImage.decode(output, previewMaxDimension: 128)
        let x = 16, y = 16, i = (y * preview.width + x) * 4
        XCTAssertGreaterThan(preview.rgba[i + 2], preview.rgba[i] + 50, "Red top-left becomes blue through channel-swap LUT, not bottom-left")
        let bottom = ((preview.height - 16) * preview.width + x) * 4
        XCTAssertGreaterThan(preview.rgba[bottom], preview.rgba[bottom + 2] + 50)
    }
    func testHaloTilesMatchSinglePassGrainAndEverySpatialEffect() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal unavailable") }
        let width = 2051, height = 1027, renderer = try MetalLUTRenderer(lut: lut())
        var bytes = Data(count: width * height * 4)
        bytes.withUnsafeMutableBytes { raw in
            let p = raw.bindMemory(to: UInt8.self)
            for y in 0..<height { for x in 0..<width {
                let i = (y * width + x) * 4
                p[i] = UInt8((x * 13 + y * 7) % 256); p[i + 1] = UInt8((x * 7 + y * 3) % 256)
                p[i + 2] = UInt8((x + y * 11) % 256); p[i + 3] = 255
            } }
        }
        let effects = FilmFinishSettings(fade: 0.4, vignette: 0.7, bloom: 0.8, halation: 0.6, softFocus: 0.5, chromaticAberration: 0.9, streak: 0.8)
        let grain = GrainSettings(amount: 0.4, seed: 17)
        let expected = try await renderer.render(bytes, width: width, height: height, intensity: 0.8, grain: grain, effects: effects)
        let halo = try XCTUnwrap(HighResolutionPlan.halo(longEdge: width, neighbours: true, chromaticAberration: effects.chromaticAberration, streak: true))
        let plan = try XCTUnwrap(HighResolutionPlan(width: width, height: height, halo: halo))
        var actual = Data(count: bytes.count)
        for tile in plan.tiles {
            var input = Data(count: tile.input.width * tile.input.height * 4)
            input.withUnsafeMutableBytes { dst in bytes.withUnsafeBytes { src in
                for y in 0..<tile.input.height {
                    dst.baseAddress!.advanced(by: y * tile.input.width * 4).copyMemory(from: src.baseAddress!.advanced(by: ((tile.input.y + y) * width + tile.input.x) * 4), byteCount: tile.input.width * 4)
                }
            } }
            let rendered = try await renderer.render(input, width: tile.input.width, height: tile.input.height, intensity: 0.8, grain: grain, effects: effects,
                frame: SIMD4(UInt32(tile.input.x), UInt32(tile.input.y), UInt32(width), UInt32(height)))
            actual.withUnsafeMutableBytes { dst in rendered.withUnsafeBytes { src in
                for y in 0..<tile.output.height {
                    let offset = ((tile.output.y - tile.input.y + y) * tile.input.width + tile.output.x - tile.input.x) * 4
                    dst.baseAddress!.advanced(by: ((tile.output.y + y) * width + tile.output.x) * 4).copyMemory(from: src.baseAddress!.advanced(by: offset), byteCount: tile.output.width * 4)
                }
            } }
        }
        XCTAssertEqual(actual, expected, "Includes seams, global grain, vignette, chromatic and streak coordinates")
    }
    func testDepthGraphKeeps48MPSizeAndUsesActualMaskScale() throws {
        let maskPixels = SDRImage(rgba: Data(repeating: 255, count: 4 * 4 * 4), width: 4, height: 4)
        let color = CIImage(color: CIColor(red: 0.2, green: 0.3, blue: 0.4)).cropped(to: CGRect(x: 0, y: 0, width: 8064, height: 6048))
        let result = try MeasuredDepthEffect.compose(color: color, mask: maskPixels.cgImage(), width: 8064, height: 6048, radius: 80)
        XCTAssertEqual(result.extent, color.extent)
        XCTAssertThrowsError(try MeasuredDepthEffect.compose(color: color, mask: maskPixels.cgImage(), width: 8064, height: 6048, radius: .nan))
    }
    func testMissingMeasuredDepthNeverCreatesHighResolutionEffect() async throws {
        let root = try folder(), original = try fixture(root, width: 4200, height: 3100)
        let hash = try LUTPhotoEditor.hashFile(original), output = root.appendingPathComponent("photo.jpg")
        do {
            _ = try await HighResolutionPhotoProcessor.shared.renderJPEG(original: original, destination: output, lut: nil, settings: .init(), aperture: 2.8)
            XCTFail("Missing depth must not be invented")
        } catch { XCTAssertTrue(error.localizedDescription.contains("깊이")) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertEqual(try LUTPhotoEditor.hashFile(original), hash)
    }
    func testExistingOutputIsNeverOverwritten() async throws {
        let root = try folder(), original = try fixture(root, width: 8, height: 8)
        let output = root.appendingPathComponent("photo.jpg"), sentinel = Data("keep".utf8)
        try sentinel.write(to: output)
        do { _ = try await HighResolutionPhotoProcessor.shared.renderJPEG(original: original, destination: output, lut: nil, settings: .init()); XCTFail("Overwrite accepted") } catch {}
        XCTAssertEqual(try Data(contentsOf: output), sentinel)
    }
    func testCancelledExportDoesNotPublishOrLeaveRaster() async throws {
        let root = try folder(), original = try fixture(root, width: 8, height: 8), output = root.appendingPathComponent("photo.jpg")
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await HighResolutionPhotoProcessor.shared.renderJPEG(original: original, destination: output, lut: nil, settings: .init())
        }
        do { _ = try await task.value; XCTFail("Cancelled output accepted") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".raster-") })
    }
}
