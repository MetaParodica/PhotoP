import XCTest
import Metal
import ImageIO
@testable import PhotoP

final class ExposureFusionIntegrationTests: XCTestCase {
    private func inputs(shifts: [Int] = [0, 0, 0]) throws -> (URL, [URL]) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let urls = try [0.7, 1.0, 1.3].enumerated().map { index, gain -> URL in
            var bytes = [UInt8](); bytes.reserveCapacity(48 * 48 * 4)
            var seed: UInt32 = 1967
            for _ in 0..<(48 * 48) {
                // Nonperiodic local detail disambiguates translation; a smooth
                // ramp cannot independently establish an image registration.
                seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
                let v = Double(45 + seed % 97)
                bytes.append(UInt8(v * gain)); bytes.append(UInt8((v + 10) * gain))
                bytes.append(UInt8((v - 10) * gain)); bytes.append(255)
            }
            var shifted = [UInt8](repeating: 0, count: bytes.count)
            for y in 0..<48 { for x in 0..<48 {
                let sx = min(47, max(0, x - shifts[index]))
                for c in 0..<4 { shifted[(y * 48 + x) * 4 + c] = bytes[(y * 48 + sx) * 4 + c] }
            } }
            let url = root.appendingPathComponent("frame\(index).jpg")
            try SDRImage(rgba: Data(shifted), width: 48, height: 48).jpeg().write(to: url)
            return url
        }
        return (root, urls)
    }
    func testMetalFusionWritesSDRDerivativeAndPreservesEveryOriginalHash() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal GPU unavailable") }
        for shifts in [[0, 0, 0], [2, 0, -1]] {
        let (root, urls) = try inputs(shifts: shifts), originals = try urls.map { try Data(contentsOf: $0) }
        var policy = ExposureFusionPolicy(); policy.weights = .init(contrast: 0, saturation: 0, wellExposedness: 0)
        let result = try await ExposureFusionProcessor.shared.fuse(originals: urls, biases: [-1, 0, 1], documents: root, policy: policy)
        let recipe = try JSONDecoder().decode(ExposureFusionManifest.self, from: Data(contentsOf: result.deletingLastPathComponent().appendingPathComponent("recipe.json")))
        XCTAssertEqual(recipe.width, 48); XCTAssertEqual(recipe.height, 48)
        XCTAssertEqual(recipe.policy, policy)
        XCTAssertEqual(recipe.fullResolutionRegistrations?.map(\.x), shifts)
        XCTAssertEqual(recipe.fullResolutionRegistrations?.map(\.y), [0, 0, 0])
        XCTAssertEqual(recipe.frames.map(\.sha256), originals.map { LUTPhotoEditor.hash($0) })
        XCTAssertEqual(try urls.map { try Data(contentsOf: $0) }, originals)
        let output = try SDRImage.decode(result)
        let inputs = try urls.map { try SDRImage.decode($0) }
        let position = (24 * 48 + 24) * 4
        for channel in 0..<3 {
            let expected = inputs.indices.reduce(0.0) { $0 + Double(inputs[$1].rgba[position + shifts[$1] * 4 + channel]) / 3 }
            XCTAssertEqual(Double(output.rgba[position + channel]), expected, accuracy: 5)
        }
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(result as CFURL, nil))
        XCTAssertNil(CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeHDRGainMap))
        }
    }
    func testRejectedOrCancelledFusionNeverCreatesDerivativeOrChangesOriginals() async throws {
        let (root, urls) = try inputs(), originals = try urls.map { try Data(contentsOf: $0) }
        var policy = ExposureFusionPolicy(); policy.minimumTexture = 100
        do { _ = try await ExposureFusionProcessor.shared.fuse(originals: urls, biases: [-1, 0, 1], documents: root, policy: policy); XCTFail("Must reject uncertain geometry") }
        catch { XCTAssertEqual(error as? ExposureFusionFailure, .insufficientDetail) }
        let task = Task { try Task.checkCancellation(); return try await ExposureFusionProcessor.shared.fuse(originals: urls, biases: [-1, 0, 1], documents: root) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("FusionResults").path))
        XCTAssertEqual(try urls.map { try Data(contentsOf: $0) }, originals)
    }
}
