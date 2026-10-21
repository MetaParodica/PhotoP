import XCTest
import Metal
@testable import PhotoP

final class OneDLUTTests: XCTestCase {
    private let curve = "TITLE \"1D RGB\"\nLUT_1D_SIZE 3\n0 1 0\n0.25 0.5 0.8\n1 0 1"
    func testIndependentChannelsDomainClampAndStrength() throws {
        let lut = try CubeLUT.parse("DOMAIN_MIN -1 0 2\nDOMAIN_MAX 1 2 4\n" + curve)
        XCTAssertTrue(lut.isOneDimensional); XCTAssertEqual(lut.values.count, 3)
        let result = try lut.sample(.init(-0.5, 1.5, 3.5))
        XCTAssertEqual(result.x, 0.125, accuracy: 1e-9)
        XCTAssertEqual(result.y, 0.25, accuracy: 1e-9)
        XCTAssertEqual(result.z, 0.9, accuracy: 1e-9)
        let edge = try lut.sample(.init(-2, 3, 0)); XCTAssertEqual(edge, .init(0, 0, 0))
        let source = SIMD3<Double>(0.2, 0.6, 0.9)
        XCTAssertEqual(try lut.sample(source, intensity: 0), source)
    }
    func testRejectsMixedTruncatedOversizedAndNonFiniteCurves() {
        for text in ["LUT_1D_SIZE 1", "LUT_1D_SIZE 65537", curve + "\n0 0 0", curve + "\nDOMAIN_MIN 0 0 0",
                     "LUT_1D_SIZE 2\nLUT_3D_SIZE 2\n0 0 0\n1 1 1", "LUT_1D_SIZE 2\n0 0 0", curve.replacingOccurrences(of: "0.25", with: "nan")] {
            XCTAssertThrowsError(try CubeLUT.parse(text))
        }
    }
    func testMaximumOneDSizeRemainsExactWithoutThreeDBaking() throws {
        var rows = ["LUT_1D_SIZE 65536"]
        for i in 0..<65536 { let v = Double(i) / 65535; rows.append("\(v) \(v) \(v)") }
        let lut = try CubeLUT.parse(rows.joined(separator: "\n"))
        XCTAssertEqual(lut.values.count, 65536)
        let color = SIMD3<Double>(0.123456, 0.50001, 0.98765), sample = try lut.sample(color)
        for c in 0..<3 { XCTAssertEqual(sample[c], color[c], accuracy: 1e-12) }
    }
    func testStillAndTextureGPUAgreeWithIndependentOneDReference() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("Metal unavailable") }
        let lut = try CubeLUT.parse(curve), renderer = try MetalLUTRenderer(lut: lut)
        let bytes: [UInt8] = [64,192,128,255, 200,20,240,255]
        let still = [UInt8](try await renderer.render(Data(bytes), width: 2, height: 1, intensity: 0.7))
        for pixel in 0..<2 {
            let offset = pixel * 4, input = SIMD3(Double(bytes[offset]), Double(bytes[offset+1]), Double(bytes[offset+2])) / 255
            let expected = try lut.sample(input, intensity: 0.7)
            for c in 0..<3 { XCTAssertEqual(Double(still[offset+c]), (expected[c] * 255).rounded(), accuracy: 1) }
        }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 2, height: 1, mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]; d.storageMode = .shared
        let source = try XCTUnwrap(device.makeTexture(descriptor: d)), output = try XCTUnwrap(device.makeTexture(descriptor: d))
        bytes.withUnsafeBytes { source.replace(region: MTLRegionMake2D(0,0,2,1), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 8) }
        let textureRenderer = try MetalLUTTextureRenderer(lut: lut, device: device), command = try XCTUnwrap(device.makeCommandQueue()?.makeCommandBuffer())
        try textureRenderer.encode(source: source, destination: output, intensity: 0.7, command: command)
        command.commit(); command.waitUntilCompleted(); XCTAssertEqual(command.status, .completed)
        var texture = [UInt8](repeating: 0, count: 8)
        texture.withUnsafeMutableBytes { output.getBytes($0.baseAddress!, bytesPerRow: 8, from: MTLRegionMake2D(0,0,2,1), mipmapLevel: 0) }
        for i in still.indices { XCTAssertEqual(Double(texture[i]), Double(still[i]), accuracy: 1) }
    }
}
