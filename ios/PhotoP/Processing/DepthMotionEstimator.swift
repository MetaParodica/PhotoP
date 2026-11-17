@preconcurrency import Vision
@preconcurrency import CoreImage
import CoreVideo
import Foundation

// One request at a time, analysis executor only. Flow uses the same small,
// oriented RGB canvas as the depth history. Failure leaves motion-gated fallback.
final class DepthMotionEstimator {
    private let context = CIContext(options: [.cacheIntermediates: false])
    func image(_ color: CIImage, width: Int, height: Int) throws -> CGImage {
        let small = color.transformed(by: CGAffineTransform(scaleX: CGFloat(width) / color.extent.width, y: CGFloat(height) / color.extent.height))
        guard let result = context.createCGImage(small, from: CGRect(x: 0, y: 0, width: width, height: height), format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!) else { throw CameraError.invalidPhotoData }
        return result
    }
    func backwardFlow(current: CGImage, previous: CGImage) throws -> [SIMD2<Float>] {
        let span = ProcessingTrace.begin("Optical flow")
        defer { ProcessingTrace.end("Optical flow", span) }
        guard current.width == previous.width, current.height == previous.height,
              current.width <= 512, current.height <= 512 else { throw CameraError.invalidSettings }
        OnDeviceInferenceGate.lock.lock(); defer { OnDeviceInferenceGate.lock.unlock() }
        try Task.checkCancellation()
        // The targeted image owns the reported vectors. Target=current makes
        // vectors point from current pixels to the previous handler image.
        let request = VNGenerateOpticalFlowRequest(targetedCGImage: current, options: [:])
        request.computationAccuracy = .medium
        request.outputPixelFormat = kCVPixelFormatType_TwoComponent32Float
        let handler = VNImageRequestHandler(cgImage: previous, orientation: .up, options: [:])
        try handler.perform([request])
        guard let buffer = request.results?.first?.pixelBuffer,
              CVPixelBufferGetWidth(buffer) == current.width, CVPixelBufferGetHeight(buffer) == current.height,
              CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_TwoComponent32Float,
              CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { throw CameraError.invalidPhotoData }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let w = current.width, h = current.height, stride = CVPixelBufferGetBytesPerRow(buffer)
        guard stride >= w * 8, let base = CVPixelBufferGetBaseAddress(buffer) else { throw CameraError.invalidPhotoData }
        var flow = [SIMD2<Float>](repeating: .zero, count: w * h)
        for y in 0..<h {
            let row = base.advanced(by: y * stride).assumingMemoryBound(to: Float.self)
            for x in 0..<w { flow[y * w + x] = SIMD2(row[x * 2], row[x * 2 + 1]) }
        }
        return flow
    }
}
