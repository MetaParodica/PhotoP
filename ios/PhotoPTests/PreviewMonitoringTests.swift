import XCTest
import Metal
@testable import PhotoP

final class PreviewMonitoringTests: XCTestCase {
    private func run(_ bytes: [UInt8], width: Int, height: Int, settings: MonitoringSettings,
                     graded: [UInt8]? = nil) throws -> ([UInt8], PreviewHistogram) {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("Metal GPU unavailable") }
        let monitor = try MetalPreviewMonitor(device: device)
        func texture(_ data: [UInt8]) throws -> MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
            d.storageMode = .shared; d.usage = [.shaderRead, .shaderWrite]
            let texture = try XCTUnwrap(device.makeTexture(descriptor: d))
            data.withUnsafeBytes { texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: width * 4) }
            return texture
        }
        let source = try texture(bytes), input = try texture(graded ?? bytes)
        let queue = try XCTUnwrap(device.makeCommandQueue()), command = try XCTUnwrap(queue.makeCommandBuffer())
        let output = try monitor.encode(source: source, graded: input, settings: settings, command: command)
        // Private overlay needs a blit to a shared texture for this test only.
        let readable = try texture([UInt8](repeating: 0, count: bytes.count))
        let blit = try XCTUnwrap(command.makeBlitCommandEncoder())
        blit.copy(from: output, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(), sourceSize: MTLSize(width: width, height: height, depth: 1),
                  to: readable, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin())
        blit.endEncoding(); command.commit(); command.waitUntilCompleted()
        XCTAssertEqual(command.status, .completed)
        var result = [UInt8](repeating: 0, count: bytes.count)
        result.withUnsafeMutableBytes { readable.getBytes($0.baseAddress!, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0) }
        return (result, monitor.histogram())
    }
    func testHistogramMatchesIndependentByteReferenceAndUsesPreLUTInput() throws {
        var bytes: [UInt8] = []
        for i in 0..<256 { bytes += [UInt8(i), UInt8(255 - i), UInt8(i / 2), 255] }
        let graded = [UInt8](repeating: 0, count: bytes.count)
        let (result, histogram) = try run(bytes, width: 32, height: 8, settings: MonitoringSettings(histogram: true), graded: graded)
        XCTAssertEqual(result, graded)
        var bins = [[UInt32]](repeating: [UInt32](repeating: 0, count: 64), count: 4)
        for i in 0..<256 {
            let r = Double(bytes[i * 4]), g = Double(bytes[i * 4 + 1]), b = Double(bytes[i * 4 + 2])
            let values = [r, g, b, (54 * r + 183 * g + 19 * b) / 256]
            for channel in 0..<4 { bins[channel][min(Int(values[channel] / 255 * 64), 63)] += 1 }
        }
        XCTAssertEqual(histogram.bins, bins)
        XCTAssertEqual(histogram.sampleCount, 256)
    }
    func testZebraThresholdStripesAndUnchangedGradedPixels() throws {
        let bytes: [UInt8] = (0..<16).flatMap { i -> [UInt8] in [i < 8 ? 255 : 128, 0, 0, 255] }
        let (result, _) = try run(bytes, width: 16, height: 1, settings: MonitoringSettings(zebra: true))
        for i in 0..<16 {
            if i < 8 {
                let stripe: [Double] = i % 12 < 6 ? [255, 255, 0] : [0, 0, 0]
                for c in 0..<3 { XCTAssertEqual(Double(result[i * 4 + c]), (Double(bytes[i * 4 + c]) * 0.3 + stripe[c] * 0.7).rounded(), accuracy: 1) }
            } else { XCTAssertEqual(Array(result[i * 4..<i * 4 + 4]), Array(bytes[i * 4..<i * 4 + 4])) }
        }
    }
    func testPeakingMarksStepEdgesButNotUniformAreas() throws {
        let bytes: [UInt8] = (0..<64).flatMap { i -> [UInt8] in let v: UInt8 = i % 8 < 4 ? 40 : 210; return [v, v, v, 255] }
        let (result, _) = try run(bytes, width: 8, height: 8, settings: MonitoringSettings(peaking: true))
        for y in 0..<8 { for x in 0..<8 {
            let offset = (y * 8 + x) * 4
            let expected: [UInt8] = (x == 3 || x == 4) ? [0, 255, 0, 255] : Array(bytes[offset..<offset + 4])
            XCTAssertEqual(Array(result[offset..<offset + 4]), expected)
        } }
    }
    func testSampleBudgetAndTransparentPixels() throws {
        let bytes = [UInt8](repeating: 255, count: 1024 * 4)
        let (_, histogram) = try run(bytes, width: 1024, height: 1, settings: MonitoringSettings(histogram: true))
        XCTAssertEqual(histogram.sampleCount, 256)
        let (transparent, empty) = try run([0, 0, 0, 0], width: 1, height: 1, settings: MonitoringSettings(histogram: true, zebra: true, peaking: true))
        XCTAssertEqual(transparent, [0, 0, 0, 0]); XCTAssertEqual(empty.sampleCount, 0)
    }
    func testInvalidMonitoringSettingsAreRejected() {
        XCTAssertThrowsError(try MonitoringSettings(zebraThreshold: .nan).validate())
        XCTAssertThrowsError(try MonitoringSettings(peakingThreshold: 0).validate())
    }
}
