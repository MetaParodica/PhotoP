import XCTest
@testable import PhotoP

final class PhotoResolutionTests: XCTestCase {
    private let small = PhotoResolution(width: 4032, height: 3024)
    private let large = PhotoResolution(width: 8064, height: 6048)
    func testOptionsComeFromActiveFormatAndRespectBothAxes() {
        let invalid = PhotoResolution(width: 0, height: 3024)
        let wide = PhotoResolution(width: 9000, height: 1000)
        let options = PhotoResolutionPolicy.options(supported: [large, small, small, invalid, wide], ceiling: large)
        XCTAssertEqual(options, [small, large])
        XCTAssertEqual(large.pixels, 48_771_072)
        XCTAssertTrue(large.title.contains("48.8MP"))
    }
    func testExplicitAndMaximumRequestsDoNotInventIntermediateSizes() throws {
        let sizes = [small, large]
        XCTAssertEqual(try PhotoResolutionPolicy.resolve(nil, supported: sizes, ceiling: large, raw: .processed, bracket: false), large)
        XCTAssertEqual(try PhotoResolutionPolicy.resolve(small, supported: sizes, ceiling: large, raw: .processed, bracket: false), small)
        XCTAssertThrowsError(try PhotoResolutionPolicy.resolve(.init(width: 6000, height: 4000), supported: sizes, ceiling: large, raw: .processed, bracket: false))
        XCTAssertThrowsError(try PhotoResolutionPolicy.resolve(large, supported: sizes, ceiling: small, raw: .processed, bracket: false))
        XCTAssertThrowsError(try PhotoResolutionPolicy.resolve(nil, supported: [], ceiling: large, raw: .processed, bracket: false))
    }
    func testRAWAndBracketKeepExistingMaximumPolicy() throws {
        for raw in [RawCaptureMode.bayer, .appleProRAW] {
            XCTAssertThrowsError(try PhotoResolutionPolicy.resolve(small, supported: [small, large], ceiling: large, raw: raw, bracket: false))
            XCTAssertEqual(try PhotoResolutionPolicy.resolve(nil, supported: [small, large], ceiling: large, raw: raw, bracket: false), large)
        }
        XCTAssertThrowsError(try PhotoResolutionPolicy.resolve(small, supported: [small, large], ceiling: large, raw: .processed, bracket: true))
    }
    func testActualFileDimensionsAreReadInsteadOfAssumingRequestSucceeded() throws {
        let image = SDRImage(rgba: Data(repeating: 255, count: 2 * 3 * 4), width: 2, height: 3)
        let photo = try CapturedPhoto(data: image.jpeg(), expectedFormat: .jpeg)
        XCTAssertEqual(photo.pixelDimensions, .init(width: 2, height: 3))
        XCTAssertNotEqual(photo.pixelDimensions, large)
    }
}
