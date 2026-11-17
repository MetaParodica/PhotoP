import XCTest
#if canImport(PhotoP)
@testable import PhotoP
#else
@testable import PhotoPImagePolicies
#endif

final class LUTTextEncoderTests: XCTestCase {
    func testPlaneWriterPreservesLegacyBytesHeadersPrecisionAndRedFastestOrder() throws {
        let n = 3, headers = ["TITLE \"Fixture\"", "# Unicode: 색", "LUT_3D_SIZE 3"]
        func color(_ c: SIMD3<Double>) -> SIMD3<Double> { SIMD3(c.z * 0.234567891, c.y - 0.5, c.x * 1.234567891) }
        for places in [7, 8] {
            var expected = headers
            for b in 0..<n { for g in 0..<n { for r in 0..<n {
                let c = color(SIMD3(Double(r), Double(g), Double(b)) / Double(n - 1))
                expected.append(String(format: "%.\(places)f %.\(places)f %.\(places)f", locale: Locale(identifier: "en_US_POSIX"), c.x, c.y, c.z))
            } } }
            let output = try LUTTextEncoder.encode(dimension: n, header: headers, decimalPlaces: places, sample: color)
            XCTAssertEqual(output, Data(expected.joined(separator: "\n").utf8))
            let lut = try CubeLUT.parse(String(decoding: output, as: UTF8.self))
            let c = try lut.sample(SIMD3(0.25, 0.5, 0.75))
            XCTAssertEqual(c.x, 0.17592591825, accuracy: 0.0000001)
            XCTAssertEqual(c.y, 0, accuracy: 0.0000001)
            XCTAssertEqual(c.z, 0.30864197275, accuracy: 0.0000001)
        }
    }
    func testInvalidGenerationAndNonFiniteSamplesFailClosed() {
        XCTAssertThrowsError(try LUTTextEncoder.encode(dimension: 66, header: ["LUT_3D_SIZE 66"], decimalPlaces: 8) { $0 })
        XCTAssertThrowsError(try LUTTextEncoder.encode(dimension: 2, header: [], decimalPlaces: 8) { $0 })
        XCTAssertThrowsError(try LUTTextEncoder.encode(dimension: 2, header: ["LUT_3D_SIZE 2"], decimalPlaces: 8) { _ in SIMD3(repeating: .nan) })
    }
    func testCancellationStopsBeforeGeneratingAnyPlane() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try LUTTextEncoder.encode(dimension: 65, header: ["LUT_3D_SIZE 65"], decimalPlaces: 8) { $0 }
        }
        do { _ = try await task.value; XCTFail("Cancelled LUT generation succeeded") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
}
