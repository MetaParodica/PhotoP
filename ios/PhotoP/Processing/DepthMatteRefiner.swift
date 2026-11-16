@preconcurrency import Vision
@preconcurrency import CoreImage
import CoreVideo
import CoreGraphics
import Foundation

// One owner/serial analysis executor. This is instance matting + a conservative
// local color solution, not a claim of ground-truth transparent-object recovery.
final class DepthMatteRefiner {
    private let context = CIContext(options: [.cacheIntermediates: false])

    func refine(color: CIImage, focus: CGPoint, embedded: CIImage?, maximumDimension: Int = 384) throws -> DepthMatteSurface? {
        try Task.checkCancellation()
        guard focus.x.isFinite, focus.y.isFinite, (0...1).contains(focus.x), (0...1).contains(focus.y),
              color.extent.width.isFinite, color.extent.height.isFinite,
              color.extent.width >= 3, color.extent.height >= 3 else { throw CameraError.invalidSettings }
        let scale = min(1, CGFloat(min(512, max(32, maximumDimension))) / max(color.extent.width, color.extent.height))
        let small = color.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = context.createCGImage(small, from: small.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!) else { throw CameraError.invalidPhotoData }
        let raster = try SDRImage.rasterize(cg), w = raster.width, h = raster.height
        let mask: CIImage
        if let embedded {
            mask = embedded.transformed(by: CGAffineTransform(scaleX: CGFloat(w) / embedded.extent.width, y: CGFloat(h) / embedded.extent.height))
        } else {
            OnDeviceInferenceGate.lock.lock(); defer { OnDeviceInferenceGate.lock.unlock() }
            try Task.checkCancellation()
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
            try handler.perform([request])
            guard let observation = request.results?.first else { return nil }
            // Select the instance under the actual focal point, not all people
            // in the image. A far person's matte must not erase background.
            var selected: CIImage?
            for instance in observation.allInstances.prefix(8) {
                let buffer = try observation.generateScaledMaskForImage(forInstances: IndexSet(integer: instance), from: handler)
                let candidate = CIImage(cvPixelBuffer: buffer, options: [.colorSpace: NSNull()])
                let a = try Self.alpha(candidate, width: w, height: h, context: context)
                let x = min(w - 1, max(0, Int(focus.x * CGFloat(w)))), y = min(h - 1, max(0, Int(focus.y * CGFloat(h))))
                if a[y * w + x] > 0.5 { selected = candidate; break }
            }
            guard let selected else { return nil }; mask = selected
        }
        let alpha = try Self.alpha(mask, width: w, height: h, context: context)
        let x = min(w - 1, max(0, Int(focus.x * CGFloat(w)))), y = min(h - 1, max(0, Int(focus.y * CGFloat(h))))
        guard alpha[y * w + x] > 0.5 else { return nil }
        func linear(_ byte: UInt8) -> Float {
            let c = Float(byte) / 255; return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let rgb = (0..<(w * h)).map { i in SIMD3(linear(raster.rgba[i * 4]), linear(raster.rgba[i * 4 + 1]), linear(raster.rgba[i * 4 + 2])) }
        try Task.checkCancellation()
        return DepthMatteCore.refine(alpha: alpha, color: rgb, width: w, height: h)
    }

    static func alpha(_ image: CIImage, width: Int, height: Int, context: CIContext) throws -> [Float] {
        let scaled = image.transformed(by: CGAffineTransform(scaleX: CGFloat(width) / image.extent.width, y: CGFloat(height) / image.extent.height))
        guard let cg = context.createCGImage(scaled, from: CGRect(x: 0, y: 0, width: width, height: height), format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!), cg.bitsPerPixel == 32,
              let data = cg.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { throw CameraError.invalidPhotoData }
        return (0..<(width * height)).map { Float(bytes[($0 / width) * cg.bytesPerRow + ($0 % width) * 4]) / 255 }
    }
    static func images(_ surface: DepthMatteSurface, extent: CGRect) throws -> (alpha: CIImage, foreground: CIImage, background: CIImage) {
        func image(_ values: [SIMD4<Float>], space: CGColorSpace) throws -> CIImage {
            let data = values.withUnsafeBytes { Data($0) }
            guard let provider = CGDataProvider(data: data as CFData),
                  let cg = CGImage(width: surface.width, height: surface.height, bitsPerComponent: 32, bitsPerPixel: 128,
                    bytesPerRow: surface.width * 16, space: space,
                    bitmapInfo: [.floatComponents, .byteOrder32Little, CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)],
                    provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { throw CameraError.invalidPhotoData }
            return CIImage(cgImage: cg).transformed(by: CGAffineTransform(scaleX: extent.width / CGFloat(surface.width), y: extent.height / CGFloat(surface.height)))
        }
        let linear = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
        let alpha = try image(surface.alpha.map { SIMD4($0, $0, $0, 1) }, space: linear)
        let f = try image(surface.foreground.map { SIMD4($0.x, $0.y, $0.z, 1) }, space: linear)
        let b = try image(surface.background.map { SIMD4($0.x, $0.y, $0.z, 1) }, space: linear)
        return (alpha, f, b)
    }
}
