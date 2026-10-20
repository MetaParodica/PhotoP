import XCTest
import Metal
@testable import PhotoP

final class MetalLUTTests: XCTestCase {
    private func renderer(header: String = "LUT_3D_SIZE 2", transform: (Double, Double, Double) -> SIMD3<Double>) throws -> (CubeLUT, MetalLUTRenderer) {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal GPU unavailable; device validation remains required") }
        var lines = [header]
        for b in 0...1 { for g in 0...1 { for r in 0...1 {
            let v = transform(Double(r), Double(g), Double(b))
            lines.append("\(v.x) \(v.y) \(v.z)")
        } } }
        let lut = try CubeLUT.parse(lines.joined(separator: "\n"))
        return (lut, try MetalLUTRenderer(lut: lut))
    }
    private func compare(header: String = "LUT_3D_SIZE 2", transform: (Double, Double, Double) -> SIMD3<Double>) async throws {
        let (lut, gpu) = try renderer(header: header, transform: transform)
        // More than one threadgroup, including a partial final group, alpha and off-grid colors.
        var bytes: [UInt8] = []
        for i in 0..<257 {
            let alpha = UInt8(i % 256)
            bytes += [UInt8(i % (Int(alpha) + 1)), alpha / 2, alpha / 3, alpha]
        }
        for strength in [0.0, 0.5, 1.0] {
            let result = [UInt8](try await gpu.render(Data(bytes), width: 257, height: 1, intensity: strength))
            if strength == 0 { XCTAssertEqual(result, bytes); continue }
            for pixel in 0..<257 {
                let offset = pixel * 4, alpha = Double(bytes[offset + 3])
                let input = alpha == 0 ? SIMD3<Double>(repeating: 0) : SIMD3(Double(bytes[offset]), Double(bytes[offset + 1]), Double(bytes[offset + 2])) / alpha
                let expected = try lut.sample(input, intensity: strength)
                for channel in 0..<3 {
                    let byte = (min(max(expected[channel], 0), 1) * alpha).rounded()
                    XCTAssertEqual(Double(result[offset + channel]), byte, accuracy: 1)
                }
                XCTAssertEqual(result[offset + 3], bytes[offset + 3])
            }
        }
    }
    func testIdentityAndPartialThreadgroup() async throws {
        try await compare { SIMD3($0, $1, $2) }
    }
    func testSwappedChannelsAndIntensity() async throws {
        try await compare { SIMD3($2, 1 - $0, $1) }
    }
    func testDeclaredDomainAndSDRClamp() async throws {
        try await compare(header: "DOMAIN_MIN -1 0 0\nDOMAIN_MAX 1 2 1\nLUT_3D_SIZE 2") { SIMD3(2 * $0, $1 - 0.5, $2) }
    }
    func testRejectsMalformedBuffersAndDimensions() async throws {
        let (_, gpu) = try renderer { SIMD3($0, $1, $2) }
        for (width, height, bytes, strength) in [(0, 1, 0, 1.0), (Int.max, 2, 0, 1), (1, 1, 3, 1), (1, 1, 4, Double.nan), (1, 1, 4, 1.1)] {
            do {
                _ = try await gpu.render(Data(count: bytes), width: width, height: height, intensity: strength)
                XCTFail("Expected input rejection")
            } catch { XCTAssertTrue(error is MetalLUTError) }
        }
    }
}
