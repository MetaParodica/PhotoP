import XCTest
@testable import PhotoP

final class LongExposureStackTests: XCTestCase {
    private func pixel(_ rgb: [UInt8]) -> SDRImage { SDRImage(rgba: Data(rgb + [255]), width: 1, height: 1) }
    func testAverageUsesLinearLightRatherThanEncodedMean() throws {
        var stack = try LongExposureStack(first: pixel([0, 0, 0]), configuration: .init())
        try stack.add(pixel([255, 255, 255]))
        XCTAssertEqual(Array(stack.image().rgba), [188, 188, 188, 255])
    }
    func testLightenSelectsWholeBrighterPixelWithoutInventingColors() throws {
        var config = LongExposureConfiguration(); config.blend = .lighten
        var stack = try LongExposureStack(first: pixel([255, 0, 0]), configuration: config)
        try stack.add(pixel([0, 255, 0]))
        XCTAssertEqual(Array(stack.image().rgba), [0, 255, 0, 255])
    }
    func testStreamingMemoryDoesNotGrowWithFrameCountAndNoiseCancels() throws {
        var stack = try LongExposureStack(first: pixel([90, 90, 90]), configuration: .init())
        for i in 1..<100 { let v: UInt8 = i % 2 == 0 ? 90 : 110; try stack.add(pixel([v, v, v])) }
        XCTAssertEqual(stack.allocatedPixels, 1); XCTAssertEqual(stack.accepted, 100)
        XCTAssertEqual(Double(stack.image().rgba[0]), 101, accuracy: 1)
        XCTAssertThrowsError(try stack.add(SDRImage(rgba: Data(), width: 2, height: 1)))
    }
    func testKnownTranslationAndValidEdgesDoNotDarken() throws {
        let w = 32
        var a = [UInt8](repeating: 255, count: w * w * 4), b = a
        for y in 0..<w { for x in 0..<w {
            let v = UInt8((x * 37 + y * 19 + x * y * 11) % 220)
            for c in 0..<3 { a[(y * w + x) * 4 + c] = v }
        } }
        for y in 0..<w { for x in 0..<w { for c in 0..<3 {
            b[(y * w + x) * 4 + c] = x >= 2 && y >= 1 ? a[((y - 1) * w + x - 2) * 4 + c] : 0
        } } }
        let ref = SDRImage(rgba: Data(a), width: w, height: w), shifted = SDRImage(rgba: Data(b), width: w, height: w)
        let offset = try XCTUnwrap(TranslationAlignment.estimate(reference: ref, frame: shifted))
        XCTAssertEqual(offset.x, 2); XCTAssertEqual(offset.y, 1)
        var config = LongExposureConfiguration(); config.align = true
        var stack = try LongExposureStack(first: ref, configuration: config)
        XCTAssertTrue(try stack.add(shifted))
        let actual = Array(stack.image().rgba)
        for i in a.indices { XCTAssertEqual(Double(actual[i]), Double(a[i]), accuracy: 1) }
    }
    func testAlignmentRejectsAmbiguousUniformScene() throws {
        let flat = SDRImage(rgba: Data(repeating: 255, count: 32 * 32 * 4), width: 32, height: 32)
        var config = LongExposureConfiguration(); config.align = true
        var stack = try LongExposureStack(first: flat, configuration: config)
        XCTAssertFalse(try stack.add(flat)); XCTAssertEqual(stack.rejected, 1)
    }
    func testConfigurationAndResolutionBounds() {
        for value in [0, 301, Double.nan] { XCTAssertThrowsError(try LongExposureConfiguration(duration: value).validate()) }
        XCTAssertThrowsError(try LongExposureStack(first: SDRImage(rgba: Data(), width: 1281, height: 1), configuration: .init()))
    }
}
