import XCTest
import CoreVideo
import Metal
import QuartzCore
@testable import PhotoP

final class LivePreviewTests: XCTestCase {
    private func buffer(transfer: CFString = kCVImageBufferTransferFunction_ITU_R_709_2, tagged: Bool = true, format: OSType = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) throws -> CVPixelBuffer {
        var result: CVPixelBuffer?
        let attributes: [CFString: Any] = [kCVPixelBufferMetalCompatibilityKey: true, kCVPixelBufferIOSurfacePropertiesKey: [:]]
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 4, 4, format, attributes as CFDictionary, &result), kCVReturnSuccess)
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
    private func srgbFrom709(_ byte: Double, space: CGColorSpace) throws -> Double {
        // Independent CPU ColorSync reference, using the same explicitly declared profile.
        let color = try XCTUnwrap(CGColor(colorSpace: space, components: [byte / 255, byte / 255, byte / 255, 1]))
        let converted = try XCTUnwrap(color.converted(to: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), intent: .relativeColorimetric, options: nil))
        return try XCTUnwrap(converted.components?.first) * 255
    }
    func testYUVColorTransformOrientationAndLetterboxingOnGPU() throws {
        try compareYUV(format: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
    }
    func testVideoRangeYUVLevelsOnGPU() throws {
        try compareYUV(format: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
    }
    private func compareYUV(format: OSType) throws {
        let (device, lut) = try fixture()
        let processor = try LivePreviewImageProcessor(lut: lut, device: device)
        let display = try MetalPreviewDisplay(device: device)
        let command = try XCTUnwrap(device.makeCommandQueue()?.makeCommandBuffer())
        let pixelBuffer = try buffer(format: format)
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
                let y = Double(row < 4 ? 64 : 192)
                let normalized = format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ? (y - 16) * 255 / 219 : y
                let expected = (row < 2 || row >= 6) ? 0 : try srgbFrom709(normalized, space: LivePreviewImageProcessor.inputColorSpace(pixelBuffer))
                for channel in 0..<3 { XCTAssertEqual(Double(data[offset + channel]), expected, accuracy: 3) }
                XCTAssertEqual(data[offset + 3], 255)
            }
        }
    }
    func testRejectsUntaggedAndHDRFrames() throws {
        XCTAssertThrowsError(try LivePreviewImageProcessor.inputColorSpace(buffer(tagged: false)))
        XCTAssertThrowsError(try LivePreviewImageProcessor.inputColorSpace(buffer(transfer: kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ)))
        let srgb = try LivePreviewImageProcessor.inputColorSpace(buffer(transfer: kCVImageBufferTransferFunction_sRGB))
        XCTAssertEqual(try srgbFrom709(128, space: srgb), 128, accuracy: 1)
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
    func testStoppedCameraRejectsLiveOutputWithoutRequestingHardware() async throws {
        let (_, lut) = try fixture()
        let preview = try LiveLUTPreview(lut: lut) { _, _ in }
        let service = CameraService { _ in }
        do {
            try await service.setLivePreview(preview)
            XCTFail("Expected stopped session rejection")
        } catch {
            guard case CameraError.interrupted = error else { return XCTFail("Unexpected error: \(error)") }
        }
        service.removeLivePreview()
    }

    func testLateLifecycleEventsCannotReplaceLatestEvent() throws {
        let (_, lut) = try fixture()
        let recorder = EventRecorder()
        let preview = try LiveLUTPreview(lut: lut) { _, event in recorder.append(event) }
        let surface = CAMetalLayer()
        preview.attach(surface)
        let attached = try XCTUnwrap(recorder.events.last)
        preview.setRunning(false)
        let stopped = try XCTUnwrap(recorder.events.last)
        XCTAssertFalse(preview.isCurrentEvent(attached))
        XCTAssertTrue(preview.isCurrentEvent(stopped))
        preview.detach(surface)
        let detached = try XCTUnwrap(recorder.events.last)
        XCTAssertFalse(preview.isCurrentEvent(stopped))
        XCTAssertTrue(preview.isCurrentEvent(detached))
    }

    private final class EventRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [LiveLUTPreview.Event] = []
        var events: [LiveLUTPreview.Event] { lock.withLock { values } }
        func append(_ event: LiveLUTPreview.Event) { lock.withLock { values.append(event) } }
    }

    func testNeutralPreviewBypassesGradeTextureAndMatchesIdentityPixels() throws {
        let (device, lut) = try fixture()
        let processor = try LivePreviewImageProcessor(lut: lut, device: device)
        let queue = try XCTUnwrap(device.makeCommandQueue()), input = try buffer()
        func render(_ intensity: Double) throws -> (MTLTexture, [UInt8]) {
            let command = try XCTUnwrap(queue.makeCommandBuffer())
            let texture = try processor.encode(input, intensity: intensity, command: command)
            let readback = try XCTUnwrap(device.makeBuffer(length: 256 * texture.height, options: .storageModeShared))
            let blit = try XCTUnwrap(command.makeBlitCommandEncoder())
            blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: .init(x: 0,y: 0,z: 0), sourceSize: .init(width: texture.width,height: texture.height,depth: 1), to: readback, destinationOffset: 0, destinationBytesPerRow: 256, destinationBytesPerImage: 256 * texture.height)
            blit.endEncoding(); command.commit(); command.waitUntilCompleted()
            XCTAssertEqual(command.status, .completed)
            return (texture, Array(UnsafeBufferPointer(start: readback.contents().assumingMemoryBound(to: UInt8.self), count: readback.length)))
        }
        let first = try render(0), second = try render(0), graded = try render(1)
        XCTAssertTrue(first.0 === second.0)
        XCTAssertFalse(first.0 === graded.0)
        for row in 0..<4 { for c in 0..<16 { XCTAssertEqual(first.1[row * 256 + c], graded.1[row * 256 + c]) } }
        let command = try XCTUnwrap(queue.makeCommandBuffer())
        XCTAssertThrowsError(try processor.encode(input, intensity: 0, maximumDimension: 999, command: command))
    }

}
