import CoreGraphics
import Foundation
import ImageIO

// CGImage is immutable; the wrapper lets a decoded thumbnail cross from a background task.
struct PhotoThumbnailImage: @unchecked Sendable {
    let image: CGImage
}

enum PhotoThumbnail {
    // Reads only a downsampled, orientation-applied preview. The original file is opened read-only.
    static func make(_ url: URL, maxPixel: Int) -> PhotoThumbnailImage? {
        guard maxPixel > 0, let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map(PhotoThumbnailImage.init)
    }
}
