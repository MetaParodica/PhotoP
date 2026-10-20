import Foundation
import CoreImage
import CoreVideo
import Metal

// Frame queue owns this object. Two reusable 1024px textures; no CPU pixel copy.
final class LivePreviewImageProcessor {
    private let context: CIContext
    private let renderer: MetalLUTTextureRenderer
    private var source: MTLTexture?
    private var processed: MTLTexture?
    private let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    init(lut: CubeLUT, device: MTLDevice) throws {
        context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        renderer = try MetalLUTTextureRenderer(lut: lut, device: device)
    }

    static func inputColorSpace(_ buffer: CVPixelBuffer) throws -> CGColorSpace {
        let format = CVPixelBufferGetPixelFormatType(buffer)
        guard [kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange].contains(format)
        else { throw ImageEditingError.invalid("실시간 LUT는 8비트 YUV SDR 입력만 지원합니다.") }
        let metadata = CVBufferCopyAttachments(buffer, .shouldPropagate) as? [String: Any] ?? [:]
        guard metadata[kCVImageBufferColorPrimariesKey as String] as? String == kCVImageBufferColorPrimaries_ITU_R_709_2 as String,
              let matrix = metadata[kCVImageBufferYCbCrMatrixKey as String] as? String,
              [kCVImageBufferYCbCrMatrix_ITU_R_709_2 as String, kCVImageBufferYCbCrMatrix_ITU_R_601_4 as String].contains(matrix),
              let transfer = metadata[kCVImageBufferTransferFunctionKey as String] as? String
        else { throw ImageEditingError.invalid("프리뷰 색 프로파일을 확인할 수 없습니다.") }
        let name: CFString
        if transfer == kCVImageBufferTransferFunction_ITU_R_709_2 as String { name = CGColorSpace.coreMedia709 }
        else if transfer == kCVImageBufferTransferFunction_sRGB as String { name = CGColorSpace.sRGB }
        else { throw ImageEditingError.invalid("HDR/Log 프리뷰는 아직 지원하지 않습니다.") }
        guard let space = CGColorSpace(name: name) else { throw ImageEditingError.invalid("입력 색공간을 만들 수 없습니다.") }
        return space
    }

    func encode(_ buffer: CVPixelBuffer, intensity: Double, command: MTLCommandBuffer) throws -> MTLTexture {
        let space = try Self.inputColorSpace(buffer)
        let image = CIImage(cvPixelBuffer: buffer, options: [.colorSpace: space])
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        guard w > 0, h > 0 else { throw ImageEditingError.invalid("프리뷰 크기가 유효하지 않습니다.") }
        let scale = min(1, 1024 / Double(max(w, h)))
        let width = max(1, Int((Double(w) * scale).rounded()))
        let height = max(1, Int((Double(h) * scale).rounded()))
        if source?.width != width || source?.height != height || processed == nil {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
            descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
            descriptor.storageMode = .private
            source = renderer.device.makeTexture(descriptor: descriptor)
            processed = renderer.device.makeTexture(descriptor: descriptor)
        }
        guard let source, let processed else { throw MetalLUTError.failed("프리뷰 texture 메모리를 확보할 수 없습니다.") }
        let scaled = image.transformed(by: CGAffineTransform(scaleX: Double(width) / Double(w), y: Double(height) / Double(h)))
        // CI uses bottom-left coordinates; the presentation texture uses top-left rows.
        let upright = scaled.transformed(by: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: Double(height)))
        context.render(upright, to: source, commandBuffer: command,
                       bounds: CGRect(x: 0, y: 0, width: width, height: height), colorSpace: srgb)
        try renderer.encode(source: source, destination: processed, intensity: intensity, command: command)
        return processed
    }
}
