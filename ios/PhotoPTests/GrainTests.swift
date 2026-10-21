import XCTest
import Metal
@testable import PhotoP

final class GrainTests: XCTestCase {
    func testValidationAndNormalizedCoordinates() throws {
        for amount in [-1.0, 1.1, .nan, .infinity] {
            XCTAssertThrowsError(try GrainSettings(amount: amount).validate())
        }
        let grain = GrainSettings(amount: 1, seed: 42)
        // Pixel centers coincide at these two resolutions.
        XCTAssertEqual(grain.noise(x: 1, y: 1, width: 9, height: 9),
                       grain.noise(x: 4, y: 4, width: 27, height: 27), accuracy: 0.0001)
        for x in 0..<100 {
            XCTAssertLessThanOrEqual(abs(grain.noise(x: x, y: 0, width: 100, height: 1)), 1)
        }
    }
    func testMetalGrainMatchesReferenceAndIsDeterministic() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("Metal GPU unavailable") }
        var lines = ["LUT_3D_SIZE 2"]
        for b in 0...1 { for g in 0...1 { for r in 0...1 { lines.append("\(r) \(g) \(b)") } } }
        let lut = try CubeLUT.parse(lines.joined(separator: "\n"))
        let still = try MetalLUTRenderer(lut: lut)
        let width = 31, height = 17
        var bytes: [UInt8] = []
        for i in 0..<(width * height) {
            let alpha: UInt8 = [0, 128, 255][i % 3]
            bytes += [alpha / 2, alpha / 2, alpha / 2, alpha]
        }
        let grain = GrainSettings(amount: 0.8, seed: 42)
        let result = try await still.render(Data(bytes), width: width, height: height, intensity: 0, grain: grain)
        let repeated = try await still.render(Data(bytes), width: width, height: height, intensity: 0, grain: grain)
        XCTAssertEqual(result, repeated)
        XCTAssertNotEqual(result, Data(bytes))
        let changed = try await still.render(Data(bytes), width: width, height: height, intensity: 0, grain: GrainSettings(amount: 0.8, seed: 43))
        XCTAssertNotEqual(result, changed)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        descriptor.storageMode = .shared; descriptor.usage = [.shaderRead, .shaderWrite]
        let input = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        let output = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        bytes.withUnsafeBytes { input.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: width * 4) }
        let command = try XCTUnwrap(device.makeCommandQueue()?.makeCommandBuffer())
        try MetalLUTTextureRenderer(lut: lut, device: device).encode(source: input, destination: output, intensity: 0, grain: grain, command: command)
        command.commit(); command.waitUntilCompleted()
        XCTAssertEqual(command.status, .completed)
        var textureBytes = [UInt8](repeating: 0, count: bytes.count)
        textureBytes.withUnsafeMutableBytes { output.getBytes($0.baseAddress!, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0) }
        let actual = [UInt8](result)
        for i in 0..<(width * height) {
            let a = Float(bytes[i * 4 + 3])
            let v = a == 0 ? 0 : Float(bytes[i * 4]) / a
            let noise = grain.noise(x: i % width, y: i / width, width: width, height: height) * Float(grain.amount) * 0.12 * (4 * v * (1 - v))
            let expected = (min(max(v + noise, 0), 1) * a).rounded()
            for c in 0..<3 {
                XCTAssertEqual(Float(actual[i * 4 + c]), expected, accuracy: 1)
                XCTAssertEqual(Double(textureBytes[i * 4 + c]), Double(actual[i * 4 + c]), accuracy: 1)
            }
            XCTAssertEqual(actual[i * 4 + 3], bytes[i * 4 + 3])
        }
        do { _ = try await still.render(Data(bytes), width: width, height: height, intensity: 0, grain: GrainSettings(amount: .nan)); XCTFail("invalid bypass") } catch {}
    }
}
