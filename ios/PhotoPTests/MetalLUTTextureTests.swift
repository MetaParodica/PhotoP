import XCTest
import Metal
@testable import PhotoP

final class MetalLUTTextureTests: XCTestCase {
    private func fixture() throws -> (MTLDevice, CubeLUT) {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("Metal GPU unavailable") }
        var lines = ["DOMAIN_MIN -1 0 0", "DOMAIN_MAX 1 2 1", "LUT_3D_SIZE 3"]
        for b in 0..<3 { for g in 0..<3 { for r in 0..<3 {
            let red = Double(r) / 2, green = Double(g) / 2, blue = Double(b) / 2
            lines.append("\(red * green) \(blue * blue) \(1 - red)")
        } } }
        return (device, try CubeLUT.parse(lines.joined(separator: "\n")))
    }
    private func texture(_ device: MTLDevice, width: Int = 7, height: Int = 5, format: MTLPixelFormat = .rgba8Unorm) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        return try XCTUnwrap(device.makeTexture(descriptor: descriptor))
    }
    private func read(_ texture: MTLTexture) -> Data {
        var bytes = Data(count: texture.width * texture.height * 4)
        bytes.withUnsafeMutableBytes { texture.getBytes($0.baseAddress!, bytesPerRow: texture.width * 4,
                                                       from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0) }
        return bytes
    }
    func testTextureMatchesCPUAndStillBufferAcrossCellsStrengthAndAlpha() async throws {
        let (device, lut) = try fixture()
        let gpu = try MetalLUTTextureRenderer(lut: lut, device: device)
        let still = try MetalLUTRenderer(lut: lut)
        let source = try texture(device), output = try texture(device)
        var bytes: [UInt8] = []
        for i in 0..<35 {
            let a = (i * 37) % 256, range = a + 1
            bytes += [UInt8((i * 17) % range), UInt8((i * 43) % range), UInt8((i * 71) % range), UInt8(a)]
        }
        bytes.withUnsafeBytes { source.replace(region: MTLRegionMake2D(0, 0, 7, 5), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 28) }
        let queue = try XCTUnwrap(device.makeCommandQueue())
        for strength in [0.0, 0.5, 1.0] {
            let command = try XCTUnwrap(queue.makeCommandBuffer())
            try gpu.encode(source: source, destination: output, intensity: strength, command: command)
            command.commit(); command.waitUntilCompleted()
            XCTAssertEqual(command.status, .completed)
            let actual = [UInt8](read(output))
            let stillBytes = [UInt8](try await still.render(Data(bytes), width: 7, height: 5, intensity: strength))
            for i in 0..<35 {
                let offset = i * 4, alpha = Double(bytes[offset + 3])
                let input = alpha == 0 ? SIMD3<Double>(repeating: 0) : SIMD3(Double(bytes[offset]), Double(bytes[offset + 1]), Double(bytes[offset + 2])) / alpha
                let expected = try lut.sample(input, intensity: strength)
                for c in 0..<3 {
                    XCTAssertEqual(Double(actual[offset + c]), (min(max(expected[c], 0), 1) * alpha).rounded(), accuracy: 1)
                    XCTAssertEqual(Double(actual[offset + c]), Double(stillBytes[offset + c]), accuracy: 1)
                }
                XCTAssertEqual(actual[offset + 3], bytes[offset + 3])
            }
            if strength == 0 { XCTAssertEqual(actual, bytes) }
        }
    }
    func testBGRATextureChannelInterpretation() throws {
        let (device, lut) = try fixture()
        let gpu = try MetalLUTTextureRenderer(lut: lut, device: device)
        let source = try texture(device, width: 1, height: 1, format: .bgra8Unorm)
        let output = try texture(device, width: 1, height: 1)
        let bytes: [UInt8] = [192, 128, 64, 255]
        bytes.withUnsafeBytes { source.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 4) }
        let command = try XCTUnwrap(device.makeCommandQueue()?.makeCommandBuffer())
        try gpu.encode(source: source, destination: output, intensity: 0, command: command)
        command.commit(); command.waitUntilCompleted()
        XCTAssertEqual([UInt8](read(output)), [64, 128, 192, 255])
    }
    func testRejectsInPlaceMismatchedAndImplicitSRGBTextures() throws {
        let (device, lut) = try fixture()
        let gpu = try MetalLUTTextureRenderer(lut: lut, device: device)
        let source = try texture(device)
        let queue = try XCTUnwrap(device.makeCommandQueue())
        for destination in [source, try texture(device, width: 8), try texture(device, format: .rgba8Unorm_srgb)] {
            let command = try XCTUnwrap(queue.makeCommandBuffer())
            XCTAssertThrowsError(try gpu.encode(source: source, destination: destination, intensity: 1, command: command))
        }
        let destination = try texture(device)
        for strength in [-0.1, .nan, 1.1] {
            let command = try XCTUnwrap(queue.makeCommandBuffer())
            XCTAssertThrowsError(try gpu.encode(source: source, destination: destination, intensity: strength, command: command))
        }
    }
}
