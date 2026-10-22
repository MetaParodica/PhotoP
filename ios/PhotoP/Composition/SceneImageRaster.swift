import CoreGraphics
import Foundation

enum SceneImageRaster {
    static func photometry(_ image: CGImage) -> ScenePhotometry? {
        let side = 96
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        let rendered = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: side, height: side, bitsPerComponent: 8,
                bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            // Same CGImage -> RGBA memory convention as SDRImage.rasterize.
            // Input orientation is already baked; do not apply a second flip.
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return rendered ? ScenePhotometry.measure(rgba: bytes, side: side) : nil
    }
}
