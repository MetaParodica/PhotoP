import XCTest
#if canImport(PhotoPImagePolicies)
@testable import PhotoPImagePolicies
#else
@testable import PhotoP
#endif

final class ScopeAnalysisPolicyTests: XCTestCase {
    func testNeutralColorsStayAtChromaCenterAndRedBlueReachCorrectAxes() throws {
        for grey in [0.0, 0.25, 0.5, 1] {
            let bin = try XCTUnwrap(ScopeAnalysisPolicy.chroma(red: grey, green: grey, blue: grey))
            XCTAssertEqual(bin.x, 32); XCTAssertEqual(bin.y, 32)
        }
        let red = try XCTUnwrap(ScopeAnalysisPolicy.chroma(red: 1, green: 0, blue: 0))
        let blue = try XCTUnwrap(ScopeAnalysisPolicy.chroma(red: 0, green: 0, blue: 1))
        XCTAssertEqual(red.x, 24); XCTAssertEqual(red.y, 63)
        XCTAssertEqual(blue.x, 63); XCTAssertEqual(blue.y, 28)
        XCTAssertNil(ScopeAnalysisPolicy.chroma(red: .nan, green: 0, blue: 0))
    }
    func testFalseColorBoundariesHaveDefinedSDRPalette() {
        XCTAssertEqual(ScopeAnalysisPolicy.falseColor(0), [106, 53, 167])
        XCTAssertEqual(ScopeAnalysisPolicy.falseColor(0.03), [36, 95, 240])
        XCTAssertEqual(ScopeAnalysisPolicy.falseColor(0.1), [89, 89, 89])
        XCTAssertEqual(ScopeAnalysisPolicy.falseColor(0.4), [50, 176, 90])
        XCTAssertEqual(ScopeAnalysisPolicy.falseColor(0.6), [184, 184, 184])
        XCTAssertEqual(ScopeAnalysisPolicy.falseColor(0.9), [244, 207, 69])
        XCTAssertEqual(ScopeAnalysisPolicy.falseColor(0.97), [234, 68, 59])
    }
    func testAggregateBufferRangesAreDisjointAndBounded() {
        XCTAssertEqual(ScopeAnalysisPolicy.waveformOffset + 4096, ScopeAnalysisPolicy.paradeOffset)
        XCTAssertEqual(ScopeAnalysisPolicy.paradeOffset + 12288, ScopeAnalysisPolicy.vectorscopeOffset)
        XCTAssertEqual(ScopeAnalysisPolicy.vectorscopeOffset + 4096, ScopeAnalysisPolicy.count)
        XCTAssertLessThan(ScopeAnalysisPolicy.count * 4, 84 * 1024)
    }
}
