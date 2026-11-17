import XCTest
#if canImport(PhotoP)
@testable import PhotoP
#else
@testable import PhotoPImagePolicies
#endif

final class LUTBinaryCodecTests: XCTestCase {
    func testRuntimeCachePreserves1DAnd3DTablesAndSampledColorExactly() throws {
        for one in [true, false] {
            let n = 3, count = one ? n : n * n * n
            let table = (0..<count).map { SIMD3<Double>(Double($0) / 31, -Double($0) / 23, $0 == 0 ? -0.0 : Double($0) / 17) }
            let original = try CubeLUT(title: "색 · runtime", dimension: n, domainMin: SIMD3(-1, 0.25, -0.0), domainMax: SIMD3(2, 1.25, 3), values: table, isOneDimensional: one)
            let data = try LUTBinaryCodec.encode(original)
            let restored = try LUTBinaryCodec.decode(data)
            XCTAssertEqual(restored.title, original.title); XCTAssertEqual(restored.dimension, n)
            XCTAssertEqual(restored.domainMin, original.domainMin); XCTAssertEqual(restored.domainMax, original.domainMax)
            XCTAssertEqual(restored.isOneDimensional, one)
            for i in table.indices { for c in 0..<3 { XCTAssertEqual(restored.values[i][c].bitPattern, table[i][c].bitPattern) } }
            XCTAssertEqual(try restored.sample(SIMD3(0.5, 0.75, 1.5)), try original.sample(SIMD3(0.5, 0.75, 1.5)))
        }
    }
    func testTruncatedOversizedAndNonFiniteCacheRejectedBeforeUse() throws {
        let lut = try CubeLUT.parse("LUT_1D_SIZE 2\n0 0 0\n1 1 1")
        let data = try LUTBinaryCodec.encode(lut)
        for broken in [Data(), Data([255, 255, 255, 255]), Data(data.dropLast()), data + Data([0])] {
            XCTAssertThrowsError(try LUTBinaryCodec.decode(broken))
        }
        var nan = data
        var word = Double.nan.bitPattern.littleEndian
        withUnsafeBytes(of: &word) { nan.replaceSubrange((nan.count - 8)..<nan.count, with: $0) }
        XCTAssertThrowsError(try LUTBinaryCodec.decode(nan))
        let header = Data("{\"version\":1,\"dimension\":9223372036854775807,\"oneDimensional\":false,\"minimum\":[0,0,0],\"maximum\":[1,1,1]}".utf8)
        var length = UInt32(header.count).littleEndian
        var extreme = withUnsafeBytes(of: &length) { Data($0) }; extreme.append(header)
        XCTAssertThrowsError(try LUTBinaryCodec.decode(extreme))
    }
}
