import XCTest
import AVFoundation
@testable import PhotoP

final class RawCaptureTests: XCTestCase {
    // Synthetic linear TIFF/DNG; validates the container contract, not sensor output.
    private func dng() throws -> Data {
        var data = try XCTUnwrap(Data(base64Encoded: "SUkqAAgAAAAZAP4ABAABAAAAAAAAAAABBAABAAAAIAAAAAEBBAABAAAAIAAAAAIBAwADAAAAOgEAAAMBAwABAAAAAQAAAAYBAwABAAAATIgAAA8BAgAHAAAAQAEAABABAgAVAAAASAEAABEBBAABAAAA+gEAABIBAwABAAAAAQAAABUBAwABAAAAAwAAABYBBAABAAAAIAAAABcBBAABAAAAABgAABwBAwABAAAAAQAAABLGAQAEAAAAAQQAABPGAQAEAAAAAQEAABTGAgAcAAAAXgEAABrGBAABAAAAAAAAAB3GBAABAAAA//8AAB/GBAACAAAAegEAACDGBAACAAAAggEAACHGCgAJAAAAigEAACjGBQADAAAA0gEAAFrGAwABAAAAFQAAAI3GBAAEAAAA6gEAAAAAAAAQABAAEABQaG90b1AAAFN5bnRoZXRpYyBMaW5lYXIgRE5HAABQaG90b1AgU3ludGhldGljIExpbmVhciBETkcAAAAAAAAAAAAgAAAAIAAAAAEAAAABAAAAAAAAAAEAAAAAAAAAAQAAAAAAAAABAAAAAQAAAAEAAAAAAAAAAQAAAAAAAAABAAAAAAAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAAAAAAAAAAAIAAAACAAAAA="))
        for _ in 0..<(32 * 32 * 3) { data.append(contentsOf: [0, 128]) }
        return data
    }
    func testOnlyAdvertisedRAWClassesAreSelectable() {
        let classify: (UInt32) -> RawCaptureMode? = { $0 == 10 ? .bayer : ($0 == 20 ? .appleProRAW : nil) }
        XCTAssertEqual(RawCapturePolicy.modes(formats: [], classify: classify), [.processed])
        XCTAssertEqual(RawCapturePolicy.modes(formats: [99, 20], classify: classify), [.processed, .appleProRAW])
        XCTAssertEqual(RawCapturePolicy.modes(formats: [20, 10, 10], classify: classify), [.processed, .bayer, .appleProRAW])
        XCTAssertNil(PhotoFileFormat.dng.codec)
        XCTAssertFalse(PhotoFileFormat.supported(by: [.jpeg, .hevc]).contains(.dng))
    }
    func testRAWExecutionPolicySeparatesSupportFromCurrentAvailability() {
        let all = RawCaptureMode.allCases
        XCTAssertNotNil(RawCapturePolicy.unavailableReason(mode: .bayer, available: [.processed], live: false, exposureMode: .continuousAutoExposure))
        XCTAssertNotNil(RawCapturePolicy.unavailableReason(mode: .appleProRAW, available: all, live: false, exposureMode: .custom))
        XCTAssertNotNil(RawCapturePolicy.unavailableReason(mode: .appleProRAW, available: all, live: false, exposureMode: .locked))
        XCTAssertNotNil(RawCapturePolicy.unavailableReason(mode: .bayer, available: all, live: true, exposureMode: .custom))
        XCTAssertNil(RawCapturePolicy.unavailableReason(mode: .bayer, available: all, live: false, exposureMode: .custom))
        XCTAssertNil(RawCapturePolicy.unavailableReason(mode: .appleProRAW, available: all, live: false, exposureMode: .continuousAutoExposure))
    }
    func testDNGContainerAndOriginalBytesArePreserved() throws {
        let data = try dng()
        let photo = try CapturedPhoto(data: data, expectedFormat: .dng)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try PhotoStore.writeOriginal(photo, in: folder)
        XCTAssertEqual(url.pathExtension, "dng")
        XCTAssertEqual(try Data(contentsOf: url), data)
        XCTAssertThrowsError(try CapturedPhoto(data: data, expectedFormat: .jpeg))
        XCTAssertThrowsError(try SDRImage.decode(url))
    }
    func testRAWDeliveryCannotBeReplacedByProcessedDuplicateOrMissingData() throws {
        var delivery = PhotoSeriesDelivery(format: .dng, biases: nil)
        XCTAssertThrowsError(try delivery.result())
        try delivery.receive(dng(), isRaw: true, sequence: 1, bracketBias: nil)
        XCTAssertEqual(try delivery.result().photos[0].data, try dng())
        XCTAssertThrowsError(try delivery.receive(dng(), isRaw: true, sequence: 1, bracketBias: nil))
        XCTAssertThrowsError(try delivery.result())
        for raw in [true, false] {
            var missing = PhotoSeriesDelivery(format: .dng, biases: nil)
            XCTAssertThrowsError(try missing.receive(raw ? nil : dng(), isRaw: raw, sequence: 1, bracketBias: nil))
            XCTAssertThrowsError(try missing.result())
        }
        var processed = PhotoSeriesDelivery(format: .jpeg, biases: nil)
        XCTAssertThrowsError(try processed.receive(dng(), isRaw: true, sequence: 1, bracketBias: nil))
    }
    func testDNGContainerRejectsTruncationNonDNGAndCorruptDirectory() throws {
        let valid = try dng()
        for end in [0, 4, 8, 12, 100] { XCTAssertThrowsError(try DNGContainer.validate(Data(valid.prefix(end)))) }
        var corrupt = valid
        corrupt[4] = 255; corrupt[5] = 255; corrupt[6] = 255; corrupt[7] = 255
        XCTAssertThrowsError(try DNGContainer.validate(corrupt))
        corrupt = valid
        // Replace the DNGVersion tag with an unknown private tag.
        for offset in stride(from: 10, through: 10 + 25 * 12, by: 12) where corrupt[offset] == 18 && corrupt[offset + 1] == 198 {
            corrupt[offset] = 17
        }
        XCTAssertThrowsError(try DNGContainer.validate(corrupt))
    }

}
