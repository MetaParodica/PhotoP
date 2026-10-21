import XCTest
import Metal
@testable import PhotoP

final class FilmFinishTests: XCTestCase {
    private func identity() throws -> CubeLUT {
        var lines = ["LUT_3D_SIZE 2"]
        for b in 0...1 { for g in 0...1 { for r in 0...1 { lines.append("\(r) \(g) \(b)") } } }
        return try CubeLUT.parse(lines.joined(separator: "\n"))
    }
    func testFadeAndVignetteHaveIndependentExpectedEndpoints() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal GPU unavailable") }
        let renderer = try MetalLUTRenderer(lut: identity())
        let endpoints = Data([0, 0, 0, 255, 255, 255, 255, 255])
        let faded = try await renderer.render(endpoints, width: 2, height: 1, intensity: 0, effects: .init(fade: 1))
        XCTAssertEqual(faded[0], 32); XCTAssertEqual(faded[4], 223)
        let white = Data(repeating: 255, count: 5 * 5 * 4)
        let vignette = try await renderer.render(white, width: 5, height: 5, intensity: 0, effects: .init(vignette: 1))
        XCTAssertEqual(vignette[(2 * 5 + 2) * 4], 255)
        XCTAssertLessThan(vignette[0], 150)
    }
    func testBloomAndHalationUseHighlightNeighborsAndPreserveAlpha() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal GPU unavailable") }
        let renderer = try MetalLUTRenderer(lut: identity())
        var bytes = [UInt8](repeating: 0, count: 5 * 5 * 4)
        for i in 0..<25 { bytes[i * 4 + 3] = 255 }
        for c in 0..<3 { bytes[(2 * 5 + 2) * 4 + c] = 255 }
        let bloom = try await renderer.render(Data(bytes), width: 5, height: 5, intensity: 0, effects: .init(bloom: 1))
        let halo = try await renderer.render(Data(bytes), width: 5, height: 5, intensity: 0, effects: .init(halation: 1))
        let neighbor = (2 * 5 + 1) * 4
        for c in 0..<3 { XCTAssertEqual(Double(bloom[neighbor + c]), 8, accuracy: 1) }
        XCTAssertEqual(Double(halo[neighbor]), 8, accuracy: 1); XCTAssertEqual(Double(halo[neighbor + 1]), 1, accuracy: 1)
        XCTAssertEqual(halo[neighbor + 2], 0)
        let transparent = try await renderer.render(Data([0, 0, 0, 0]), width: 1, height: 1, intensity: 0, effects: .init(fade: 1, vignette: 1, bloom: 1, halation: 1))
        XCTAssertEqual(transparent, Data([0, 0, 0, 0]))
    }
    func testTextureAndStillFinishAgreeWithinOneCodeValue() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("Metal GPU unavailable") }
        let lut = try identity(), renderer = try MetalLUTRenderer(lut: lut)
        let textureRenderer = try MetalLUTTextureRenderer(lut: lut, device: device)
        let width = 7, height = 5
        let bytes: [UInt8] = (0..<35).flatMap { i in [UInt8(i * 7), UInt8(i * 3), UInt8(255 - i * 6), 255] }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]; d.storageMode = .shared
        let source = try XCTUnwrap(device.makeTexture(descriptor: d)), output = try XCTUnwrap(device.makeTexture(descriptor: d))
        bytes.withUnsafeBytes { source.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: width * 4) }
        let finish = FilmFinishSettings(fade: 0.3, vignette: 0.6, bloom: 0.7, halation: 0.8)
        let command = try XCTUnwrap(device.makeCommandQueue()?.makeCommandBuffer())
        try textureRenderer.encode(source: source, destination: output, intensity: 0.7, effects: finish, command: command)
        command.commit(); command.waitUntilCompleted(); XCTAssertEqual(command.status, .completed)
        var actual = [UInt8](repeating: 0, count: bytes.count)
        actual.withUnsafeMutableBytes { output.getBytes($0.baseAddress!, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0) }
        let expected = [UInt8](try await renderer.render(Data(bytes), width: width, height: height, intensity: 0.7, effects: finish))
        for i in expected.indices { XCTAssertEqual(Double(actual[i]), Double(expected[i]), accuracy: 1) }
    }
    func testInvalidFinishIsRejectedEvenOnIdentityBypass() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal GPU unavailable") }
        let renderer = try MetalLUTRenderer(lut: identity())
        for effects in [FilmFinishSettings(fade: .nan), FilmFinishSettings(bloom: 2)] {
            do { _ = try await renderer.render(Data([0, 0, 0, 255]), width: 1, height: 1, intensity: 0, effects: effects); XCTFail("Invalid effect accepted") } catch {}
        }
    }
}
