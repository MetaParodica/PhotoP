import XCTest
@testable import PhotoP

final class CubeLUTTests: XCTestCase {
    func cube(header: String = "LUT_3D_SIZE 2", transform: (Double, Double, Double) -> SIMD3<Double> = { SIMD3($0, $1, $2) }) -> String {
        var lines = [header]
        for b in 0...1 { for g in 0...1 { for r in 0...1 {
            let value = transform(Double(r), Double(g), Double(b))
            lines.append("\(value.x) \(value.y) \(value.z)")
        } } }
        return lines.joined(separator: "\n")
    }
    func equal(_ value: SIMD3<Double>, _ expected: SIMD3<Double>, file: StaticString = #filePath, line: UInt = #line) {
        for channel in 0..<3 { XCTAssertEqual(value[channel], expected[channel], accuracy: 1e-10, file: file, line: line) }
    }

    func testIdentityAcrossGridAndOffGridColors() throws {
        let lut = try CubeLUT.parse(cube())
        for color in [SIMD3(0.0, 0, 0), SIMD3(1.0, 1, 1), SIMD3(0.125, 0.4, 0.85)] {
            equal(try lut.sample(color), color)
        }
    }
    func testChannelOrderAndTrilinearInterpolation() throws {
        let lut = try CubeLUT.parse(cube { r, g, b in SIMD3(b, 1 - r, g) })
        equal(try lut.sample(SIMD3(0.2, 0.6, 0.9)), SIMD3(0.9, 0.8, 0.6))
    }
    func testDeclaredDomainsAndClampPolicy() throws {
        let lut = try CubeLUT.parse(cube(header: "DOMAIN_MIN -1 0 2\nDOMAIN_MAX 1 2 4\nLUT_3D_SIZE 2"))
        equal(try lut.sample(SIMD3(0, 1, 3)), SIMD3(repeating: 0.5))
        equal(try lut.sample(SIMD3(-4, 8, 1)), SIMD3(0, 1, 0))
    }
    func testIntensityZeroHalfAndOne() throws {
        let lut = try CubeLUT.parse(cube { r, g, b in SIMD3(1 - r, 1 - g, 1 - b) })
        let color = SIMD3(0.1, 0.3, 0.8)
        equal(try lut.sample(color, intensity: 0), color)
        equal(try lut.sample(color, intensity: 0.5), SIMD3(repeating: 0.5))
        equal(try lut.sample(color, intensity: 1), SIMD3(0.9, 0.7, 0.2))
    }
    func testCommentsTitleWhitespaceAndScientificNotation() throws {
        let text = cube(header: "# comment\r\nTITLE \"Look #1\" # outside\nLUT_3D_SIZE\t2")
            .replacingOccurrences(of: "1.0", with: "1e0").replacingOccurrences(of: "0.0", with: "0e0")
        let lut = try CubeLUT.parse(text)
        XCTAssertEqual(lut.title, "Look #1")
        equal(try lut.sample(SIMD3(0.3, 0.2, 0.1)), SIMD3(0.3, 0.2, 0.1))
    }
    func testRejectsInvalidCountsSizesAndHeaderPlacement() {
        for text in ["", "LUT_3D_SIZE 1", "LUT_3D_SIZE 66", "LUT_3D_SIZE 999999999999999999999",
                     cube() + "\n0 0 0", cube().components(separatedBy: "\n").dropLast().joined(separator: "\n"),
                     cube(header: "LUT_3D_SIZE 2\nLUT_3D_SIZE 2"), cube() + "\nDOMAIN_MIN 0 0 0"] {
            XCTAssertThrowsError(try CubeLUT.parse(text), text)
        }
    }
    func testLFCRLFAndCRLineEndings() throws {
        for ending in ["\n", "\r\n", "\r"] {
            let text = cube(header: "# comment\nTITLE \"Line endings\"\nLUT_3D_SIZE 2").replacingOccurrences(of: "\n", with: ending)
            XCTAssertEqual(try CubeLUT.parse(text).title, "Line endings")
        }
    }
    func testRejectsUnknownAndShaperFormats() {
        XCTAssertThrowsError(try CubeLUT.parse(cube(header: "LUT_3D_SIZE 2\nLUT_1D_SIZE 2")))
        XCTAssertThrowsError(try CubeLUT.parse(cube(header: "LUT_3D_SIZE 2\nUNKNOWN 1")))
    }
    func testRejectsInvalidDomainsAndNonFiniteData() {
        for header in ["DOMAIN_MAX 0 1 1", "DOMAIN_MIN 2 0 0", "DOMAIN_MIN nan 0 0",
                       "DOMAIN_MAX inf 1 1", "DOMAIN_MIN 1e-300 0 0\nDOMAIN_MAX 2e-300 1 1"] {
            XCTAssertThrowsError(try CubeLUT.parse(cube(header: header + "\nLUT_3D_SIZE 2")))
        }
        XCTAssertThrowsError(try CubeLUT.parse(cube().replacingOccurrences(of: "0.0", with: "nan")))
        XCTAssertThrowsError(try CubeLUT.parse(cube().replacingOccurrences(of: "0.0", with: "1e100")))
    }
    func testRejectsNonFiniteInputsAndInvalidStrength() throws {
        let lut = try CubeLUT.parse(cube())
        for strength in [-0.01, 1.01, .nan, .infinity] {
            XCTAssertThrowsError(try lut.sample(SIMD3(repeating: 0.5), intensity: strength))
        }
        XCTAssertThrowsError(try lut.sample(SIMD3(.nan, 0, 0)))
    }
    func testFileByteLimit() {
        XCTAssertThrowsError(try CubeLUT.parse(String(repeating: " ", count: CubeLUT.maximumFileBytes + 1)))
    }
    func testRejectsOverlongInputAndRetainsExtendedOutputValues() throws {
        XCTAssertThrowsError(try CubeLUT.parse(String(repeating: "#", count: 4097)))
        let lut = try CubeLUT.parse(cube { r, g, b in SIMD3(2 * r, g - 1, b) })
        equal(try lut.sample(SIMD3(1, 0, 1)), SIMD3(2, -1, 1))
    }
}
