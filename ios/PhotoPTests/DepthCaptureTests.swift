import XCTest
@testable import PhotoP

final class DepthCaptureTests: XCTestCase {
    private func fixture() -> DepthCapturePayload {
        let depths: [Float] = [1.25, 2.5, 0, .nan]
        let depth = depths.withUnsafeBytes { Data($0) }
        let confidence = Data([2, 1, 0, 0]), jpeg = Data([0xff, 0xd8, 0xff, 0xd9])
        let metadata = DepthCaptureMetadata(timestamp: 123, rgbWidth: 4, rgbHeight: 4, depthWidth: 2, depthHeight: 2,
            cameraIntrinsics: [1, 0, 0, 0, 1, 0, 0, 0, 1], cameraTransform: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
            depthBytes: depth.count, confidenceBytes: confidence.count, jpegBytes: jpeg.count,
            depthSHA256: LUTPhotoEditor.hash(depth), confidenceSHA256: LUTPhotoEditor.hash(confidence), jpegSHA256: LUTPhotoEditor.hash(jpeg))
        return DepthCapturePayload(metadata: metadata, depth: depth, confidence: confidence, jpeg: jpeg)
    }
    func testDepthPackageRoundTripPreservesMetricBytesConfidenceAndCalibration() throws {
        let original = fixture()
        let restored = try DepthCaptureStore.decode(DepthCaptureStore.encode(original))
        XCTAssertEqual(restored.depth, original.depth)
        XCTAssertEqual(restored.confidence, original.confidence)
        XCTAssertEqual(restored.jpeg, original.jpeg)
        XCTAssertEqual(restored.metadata.cameraIntrinsics, original.metadata.cameraIntrinsics)
        XCTAssertEqual(restored.metadata.cameraTransform, original.metadata.cameraTransform)
        XCTAssertEqual(restored.metadata.depthWidth, 2)
        XCTAssertEqual(restored.metadata.version, 1)
    }
    func testTruncationTamperingOversizedHeaderAndUnknownVersionAreRejected() throws {
        let original = fixture()
        let encoded = try DepthCaptureStore.encode(original)
        XCTAssertThrowsError(try DepthCaptureStore.decode(Data(encoded.dropLast())))
        var tampered = encoded; tampered[tampered.count - 1] ^= 1
        XCTAssertThrowsError(try DepthCaptureStore.decode(tampered))
        var oversized = encoded
        for offset in 0..<4 { oversized[DepthCaptureStore.magic.count + offset] = 0xff }
        XCTAssertThrowsError(try DepthCaptureStore.decode(oversized))
        var metadata = original.metadata; metadata.version = 99
        XCTAssertThrowsError(try DepthCaptureStore.encode(.init(metadata: metadata, depth: original.depth, confidence: original.confidence, jpeg: original.jpeg)))
    }
    func testCaptureWritesSeparatePackagesAndDoesNotOverwriteEarlierResults() throws {
        let documents = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: documents) }
        let original = fixture()
        let first = try DepthCaptureStore.write(original, documents: documents)
        let before = try Data(contentsOf: first.package)
        let second = try DepthCaptureStore.write(original, documents: documents)
        XCTAssertNotEqual(first.package, second.package)
        XCTAssertEqual(try Data(contentsOf: first.package), before)
        XCTAssertEqual(try Data(contentsOf: second.photo), original.jpeg)
        XCTAssertEqual(try DepthCaptureStore.decode(before).depth, original.depth)
    }
}
