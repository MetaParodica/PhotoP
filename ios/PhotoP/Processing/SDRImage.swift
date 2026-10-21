import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

struct SDRImage: Sendable {
    let rgba: Data
    let width: Int
    let height: Int

    static let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue

    func cgImage() throws -> CGImage {
        guard width > 0, height > 0, width <= MetalLUTRenderer.maximumPixels,
              height <= MetalLUTRenderer.maximumPixels / width, rgba.count == width * height * 4,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: rgba as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width * 4, space: space, bitmapInfo: CGBitmapInfo(rawValue: Self.bitmapInfo),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .relativeColorimetric)
        else { throw ImageEditingError.invalid("SDR 이미지 데이터가 유효하지 않습니다.") }
        return image
    }

    // Decode the SDR base image, bake EXIF orientation once, convert embedded ICC to sRGB.
    // HDR gain maps are deliberately not copied to the derivative.
    static func decode(_ url: URL, previewMaxDimension: Int? = nil) throws -> SDRImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 100_000, height <= 100_000
        else { throw ImageEditingError.invalid("원본 이미지를 읽을 수 없습니다.") }
        guard CGImageSourceGetType(source) as String? != "com.adobe.raw-image" else {
            throw ImageEditingError.invalid("RAW 현상은 아직 제공하지 않습니다. DNG 원본을 외부 RAW 편집기로 내보내세요.")
        }
        let maxDimension: Int
        if let previewMaxDimension {
            guard (1...2048).contains(previewMaxDimension) else { throw ImageEditingError.invalid("미리보기 크기가 유효하지 않습니다.") }
            maxDimension = min(previewMaxDimension, max(width, height))
        } else {
            guard width <= MetalLUTRenderer.maximumPixels, height <= MetalLUTRenderer.maximumPixels / width
            else { throw ImageEditingError.invalid("현재 편집본 저장은 12.6MP 이하만 지원합니다. 원본은 그대로 보존됩니다.") }
            maxDimension = max(width, height)
        }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: maxDimension,
                                        kCGImageSourceShouldCacheImmediately: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { throw ImageEditingError.invalid("SDR 이미지를 현상할 수 없습니다.") }
        let w = image.width, h = image.height
        guard w > 0, h > 0, w <= MetalLUTRenderer.maximumPixels, h <= MetalLUTRenderer.maximumPixels / w
        else { throw ImageEditingError.invalid("디코딩된 이미지가 처리 제한을 초과합니다.") }
        var pixels = Data(count: w * h * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: w * 4, space: space, bitmapInfo: bitmapInfo)
            else { throw ImageEditingError.invalid("색변환 메모리를 확보할 수 없습니다.") }
            context.setRenderingIntent(.relativeColorimetric)
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return SDRImage(rgba: pixels, width: w, height: h)
    }

    func jpeg() throws -> Data {
        let result = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(result, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw ImageEditingError.invalid("JPEG 인코더를 만들 수 없습니다.") }
        CGImageDestinationAddImage(destination, try cgImage(), [kCGImageDestinationLossyCompressionQuality: 0.95,
                                                              kCGImagePropertyOrientation: 1] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImageEditingError.invalid("JPEG 인코딩이 실패했습니다.") }
        return result as Data
    }
}

enum ImageEditingError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { switch self { case .invalid(let reason): return reason } }
}
