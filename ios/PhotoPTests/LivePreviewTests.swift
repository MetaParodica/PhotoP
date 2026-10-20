import XCTest
import CoreVideo
import Metal
@testable import PhotoP

final class LivePreviewTests: XCTestCase {
    private func buffer(transfer: CFString = kCVImageBufferTransferFunction_ITU_R_709_2, tagged: Bool = true) throws -> CVPixelBuffer {
        var result: CVPixelBuffer?
        let attributes: [CFString: Any] = [kCVPixelBufferMetalCompatibilityKey: true, kCVPixelBufferIOSurfacePropertiesKey: [:]]
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 4, 4, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, attributes as CFDictionary, &result), kCVReturnSuccess)
        let resultBuffer = try XCTUnwrap(result)
        if tagged {
            CVBufferSetAttachment(resultBuffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
            CVBufferSetAttachment(resultBuffer, kCVImageBufferTransferFunctionKey, transfer, .shouldPropagate)
            CVBufferSetAttachment(resultBuffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
        }
        CVPixelBufferLockBaseAddress(resultBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(resultBuffer, []) }
        let y = try XCTUnwrap(CVPixelBufferGetBaseAddressOfPlane(resultBuffer, 0)).assumingMemoryBound(to: UInt8.self)
        let uv = try XCTUnwrap(CVPixelBufferGetBaseAddressOfPlane(resultBuffer, 1)).assumingMemoryBound(to: UInt8.self)
        for row in 0..<4 { for column in 0..<4 { y[row * CVPixelBufferGetBytesPerRowOfPlane(resultBuffer, 0) + column] = row < 2 ? 64 : 192 } }
        for row in 0..<2 { for column in 0..<4 { uv[row * CVPixelBufferGetBytesPerRowOfPlane(resultBuffer, 1) + column] = 128 } }
        return resultBuffer
    }
    private func fixture() throws -> (MTLDevice, CubeLUT) {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("Metal GPU unavailable") }
        var lines = ["LUT_3D_SIZE 2"]
        for b in 0...1 { for g in 0...1 { for r in 0...1 { lines.append("\(r) \(g) \(b)") } } }
        return (device, try CubeLUT.parse(lines.joined(separator: "\n")))
    }
    private func readback(_ texture: MTLTexture, command: MTLCommandBuffer) throws -> MTLBuffer {
        let buffer = try XCTUnwrap(texture.device.makeBuffer(length: 256 * texture.height, options: .storageModeShared))
        let blit = try XCTUnwrap(command.makeBlitCommandEncoder())
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1),
                  to: buffer, destinationOffset: 0, destinationBytesPerRow: 256, destinationBytesPerImage: 256 * texture.height)
        blit.endEncoding()
        return buffer
    }
    private func srgbFrom709(_ byte: Double) -> Double {
        let value = byte / 255
        let linear = value < 0.081 ? value / 4.5 : pow((value + 0.099) / 1.099, 1 / 0.45)
        return (linear <= 0.0031308 ? linear * 12.92 : 1.055 * pow(linear, 1 / 2.4) - 0.055) * 255
    }
    func testYUVColorTransformOrientationAndLetterboxingOnGPU() throws {
        let (device, lut) = try fixture()
        let processor = try LivePreviewImageProcessor(lut: lut, device: device)
        let display = try MetalPreviewDisplay(device: device)
        let command = try XCTUnwrap(device.makeCommandQueue()?.makeCommandBuffer())
        let pixelBuffer = try buffer()
        let texture = try processor.encode(pixelBuffer, intensity: 0, command: command)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 4, height: 8, mipmapped: false)
        descriptor.usage = [.renderTarget]
        let output = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        try display.encode(image: texture, destination: output, command: command)
        let bytes = try readback(output, command: command)
        command.commit(); command.waitUntilCompleted()
        XCTAssertEqual(command.status, .completed)
        let data = bytes.contents().assumingMemoryBound(to: UInt8.self)
        for row in 0..<8 {
            for column in 0..<4 {
                let offset = row * 256 + column * 4
                let expected = (row < 2 || row >= 6) ? 0 : srgbFrom709(row < 4 ? 64 : 192)
                for channel in 0..<3 { XCTAssertEqual(Double(data[offset + channel]), expected, accuracy: 3) }
                XCTAssertEqual(data[offset + 3], 255)
            }
        }
    }
    func testRejectsUntaggedAndHDRFrames() throws {
        XCTAssertThrowsError(try LivePreviewImageProcessor.inputColorSpace(buffer(tagged: false)))
        XCTAssertThrowsError(try LivePreviewImageProcessor.inputColorSpace(buffer(transfer: kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ)))
        XCTAssertEqual(try LivePreviewImageProcessor.inputColorSpace(buffer(transfer: kCVImageBufferTransferFunction_sRGB)).name, CGColorSpace.sRGB)
    }
    func testFrameGateBoundsWorkAndReleasesResourcesAfterStop() throws {
        var state = PreviewFrameState()
        XCTAssertNil(state.begin())
        state.setRunning(true)
        let first = try XCTUnwrap(state.begin())
        XCTAssertNil(state.begin())
        state.setRunning(false)
        state.setRunning(true)
        XCTAssertNil(state.begin())
        XCTAssertFalse(state.complete(first))
        let next = try XCTUnwrap(state.begin())
        XCTAssertFalse(state.complete(first))
        XCTAssertNil(state.begin())
        XCTAssertTrue(state.complete(next))
    }
    func testSurfaceChangeInvalidatesOldCompletion() throws {
        var state = PreviewFrameState()
        state.setRunning(true)
        let old = try XCTUnwrap(state.begin())
        state.invalidate()
        XCTAssertFalse(state.complete(old))
        let current = try XCTUnwrap(state.begin())
        XCTAssertTrue(state.complete(current))
        XCTAssertFalse(state.complete(current))
    }
}
