import Foundation
import ImageIO
import UniformTypeIdentifiers

// Hald level 2...8: square side n^3, cube dimension n^2, red varies fastest.
// 8-bit RGB/sRGB only. No automatic Log, HDR, ICC-gamut or rotated-table guesses.
enum HaldLUT {
    static func convert(_ data: Data) throws -> Data {
        guard data.count <= 8 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) == 1,
              CGImageSourceGetType(source) as String? == UTType.png.identifier,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = properties[kCGImagePropertyPixelWidth] as? Int, let h = properties[kCGImagePropertyPixelHeight] as? Int,
              w == h, let level = (2...8).first(where: { $0 * $0 * $0 == w }),
              (properties[kCGImagePropertyOrientation] as? Int ?? 1) == 1,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil), image.bitsPerComponent == 8,
              image.colorSpace?.model == .rgb,
              image.colorSpace?.name == nil || image.colorSpace?.name == CGColorSpace.sRGB
        else { throw ImageEditingError.invalid("Hald는 level 2~8의 정사각형 8비트 sRGB PNG만 지원합니다. 방향·색 프로파일을 확인하세요.") }
        let pixels = [UInt8](try SDRImage.rasterize(image).rgba)
        var lines = ["TITLE \"User Hald sRGB\"", "# Original PNG SHA256: \(LUTPhotoEditor.hash(data))", "LUT_3D_SIZE \(level * level)"]
        for i in stride(from: 0, to: pixels.count, by: 4) {
            guard pixels[i + 3] == 255 else { throw ImageEditingError.invalid("투명한 Hald 표는 지원하지 않습니다.") }
            lines.append(String(format: "%.8f %.8f %.8f", locale: Locale(identifier: "en_US_POSIX"), Double(pixels[i]) / 255, Double(pixels[i + 1]) / 255, Double(pixels[i + 2]) / 255))
        }
        return Data(lines.joined(separator: "\n").utf8)
    }
}
