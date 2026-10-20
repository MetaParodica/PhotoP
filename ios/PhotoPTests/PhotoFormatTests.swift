import XCTest
import AVFoundation
import ImageIO
import UniformTypeIdentifiers
@testable import PhotoP

final class PhotoFormatTests: XCTestCase {
    private func jpeg() throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8,
                                            bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    func testOnlyAdvertisedCodecsAreEnabled() {
        XCTAssertEqual(PhotoFileFormat.supported(by: [.jpeg]), [.jpeg])
        XCTAssertEqual(PhotoFileFormat.supported(by: [.hevc]), [.heif])
        XCTAssertEqual(PhotoFileFormat.supported(by: []), [])
        XCTAssertEqual(PhotoFileFormat.supported(by: [.jpeg, .hevc]), [.jpeg, .heif])
    }

    func testJPEGContainerAndBytesArePreserved() throws {
        let bytes = try jpeg()
        let photo = try CapturedPhoto(data: bytes, expectedFormat: .jpeg)
        XCTAssertEqual(photo.data, bytes)
        XCTAssertEqual(photo.format, .jpeg)
    }

    func testJPEGIsNeverMislabelledAsHEIF() throws {
        let bytes = try jpeg()
        XCTAssertThrowsError(try CapturedPhoto(data: bytes, expectedFormat: .heif))
        XCTAssertThrowsError(try CapturedPhoto(data: Data("not a photo".utf8), expectedFormat: .jpeg))
    }

    func testOriginalFileRetainsBytesAndExtension() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let photo = try CapturedPhoto(data: jpeg(), expectedFormat: .jpeg)
        let url = try PhotoStore.writeOriginal(photo, in: folder)
        XCTAssertEqual(url.pathExtension, "jpg")
        XCTAssertEqual(try Data(contentsOf: url), photo.data)
        XCTAssertEqual(PhotoFileFormat.heif.fileExtension, "heic")
    }

    func testWriteFailureIsReportedInsteadOfClaimingSave() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data().write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let photo = try CapturedPhoto(data: jpeg(), expectedFormat: .jpeg)
        XCTAssertThrowsError(try PhotoStore.writeOriginal(photo, in: file))
    }
}
