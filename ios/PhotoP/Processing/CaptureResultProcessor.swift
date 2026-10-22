@preconcurrency import AVFoundation
import CoreImage
import CoreVideo
import ImageIO
import Foundation

struct CaptureResultRecipe: Codable {
    let version: Int
    let originalFilename: String
    let originalSHA256: String
    let aperture: Double?
    let focusX: Double
    let focusY: Double
    let focusDistanceMetres: Float?
    let focusDepthValue: Float?
    let depthAccuracy: String?
    let look: ProcessingLookSettings?
    let lutSHA256: String?
    let provenance: LUTProvenance?
    let pipeline: String
}

// No camera/display resources: only runs AFTER original bytes are preserved.
actor CaptureResultProcessor {
    static let shared = CaptureResultProcessor()
    private let context = CIContext(options: [.cacheIntermediates: false])

    func render(original: URL, look: ImportedLUT?, aperture: Double?, focus: CGPoint, documents: URL? = nil) async throws -> URL {
        guard look != nil || aperture != nil else { return original }
        var image = try SDRImage.decode(original)
        var distance: Float?
        var absoluteDepth = false
        if let aperture {
            let result = try depthBlur(original: original, image: image, aperture: aperture, focus: focus)
            image = result.image; distance = result.focus; absoluteDepth = result.absolute
        }
        let settings = look.map { $0.preset ?? ProcessingLookSettings() }
        if let look, let settings {
            try settings.validate()
            let renderer = try MetalLUTRenderer(lut: look.lut)
            let pixels = try await renderer.render(image.rgba, width: image.width, height: image.height,
                                                  intensity: settings.intensity, grain: settings.grain, effects: settings.finish)
            image = SDRImage(rgba: pixels, width: image.width, height: image.height)
        }
        let recipe = CaptureResultRecipe(version: 1, originalFilename: original.lastPathComponent,
            originalSHA256: try LUTPhotoEditor.hashFile(original), aperture: aperture,
            focusX: Double(focus.x), focusY: Double(focus.y), focusDistanceMetres: absoluteDepth ? distance : nil,
            focusDepthValue: distance, depthAccuracy: aperture == nil ? nil : absoluteDepth ? "absolute" : "relative",
            look: settings, lutSHA256: look.map { LUTPhotoEditor.hash($0.data) }, provenance: look?.provenance,
            pipeline: "Oriented SDR sRGB base (max 12.6MP) → optional measured-depth variable Gaussian blur (software f strength, not optical aperture) → optional LUT/grain/finish → sRGB JPEG; original metadata omitted")
        let root = try documents ?? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = root.appendingPathComponent("CaptureResults", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let id = UUID().uuidString
        let pending = folder.appendingPathComponent(".pending-" + id, isDirectory: true)
        let final = folder.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: pending, withIntermediateDirectories: false)
        do {
            let options: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            let credit = look?.provenance.map { "\($0.requiredCredit)\nSource: \($0.source)\n\($0.previewDescription)" }
            try image.jpeg(credit: credit).write(to: pending.appendingPathComponent("photo.jpg"), options: options)
            try JSONEncoder().encode(recipe).write(to: pending.appendingPathComponent("recipe.json"), options: options)
            if let look { try look.data.write(to: pending.appendingPathComponent("look.cube"), options: options) }
            try FileManager.default.moveItem(at: pending, to: final)
            return final.appendingPathComponent("photo.jpg")
        } catch { try? FileManager.default.removeItem(at: pending); throw error }
    }

    private func depthBlur(original: URL, image: SDRImage, aperture: Double, focus: CGPoint) throws -> (image: SDRImage, focus: Float, absolute: Bool) {
        guard let radius = DepthBlurPolicy.radius(aperture: aperture, longEdge: max(image.width, image.height)),
              focus.x.isFinite, focus.y.isFinite, (0...1).contains(focus.x), (0...1).contains(focus.y),
              let source = CGImageSourceCreateWithURL(original as CFURL, nil) else { throw CameraError.invalidSettings }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let exif = CGImagePropertyOrientation(rawValue: (properties?[kCGImagePropertyOrientation] as? UInt32) ?? 1) ?? .up
        guard let dictionary = (CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeDepth)
            ?? CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeDisparity)) as? [AnyHashable: Any] else {
            throw ImageEditingError.invalid("사진의 실제 깊이 데이터를 받지 못했습니다. 원본은 보존했으며 가짜 심도 효과를 만들지 않습니다.")
        }
        let depth = try AVDepthData(fromDictionaryRepresentation: dictionary)
            .applyingExifOrientation(exif).converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        let buffer = depth.depthDataMap
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        guard w > 0, h > 0, abs((Double(w) / Double(h)) / (Double(image.width) / Double(image.height)) - 1) < 0.02 else {
            throw ImageEditingError.invalid("깊이 지도와 사진 비율이 일치하지 않습니다. 원본은 보존했습니다.")
        }
        guard w >= 3, h >= 3, w <= 4096, h <= 4096,
              CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { throw CameraError.invalidPhotoData }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        guard stride >= w * MemoryLayout<Float>.size, let base = CVPixelBufferGetBaseAddress(buffer) else { throw CameraError.invalidPhotoData }
        func value(_ x: Int, _ y: Int) -> Float { base.advanced(by: y * stride).assumingMemoryBound(to: Float.self)[x] }
        let cx = min(w - 1, Int(focus.x * CGFloat(w))), cy = min(h - 1, Int(focus.y * CGFloat(h)))
        var samples: [Float] = []
        for y in max(0, cy - 2)...min(h - 1, cy + 2) {
            for x in max(0, cx - 2)...min(w - 1, cx + 2) { samples.append(value(x, y)) }
        }
        guard let distance = DepthBlurPolicy.focusDistance(samples) else {
            throw ImageEditingError.invalid("초점 위치의 깊이가 유효하지 않습니다. 피사체를 다시 터치하고 촬영해 주세요. 원본은 보존했습니다.")
        }
        var mask = Data(count: w * h)
        mask.withUnsafeMutableBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            for y in 0..<h { for x in 0..<w { bytes[y * w + x] = DepthBlurPolicy.mask(depth: value(x, y), focus: distance) } }
        }
        guard let provider = CGDataProvider(data: mask as CFData),
              let cgMask = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w,
                                   space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                   provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent),
              let filter = CIFilter(name: "CIMaskedVariableBlur") else { throw CameraError.configuration }
        let color = CIImage(cgImage: try image.cgImage())
        let scaledMask = CIImage(cgImage: cgMask).transformed(by: CGAffineTransform(scaleX: CGFloat(image.width) / CGFloat(w), y: CGFloat(image.height) / CGFloat(h)))
        filter.setValue(color.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(scaledMask, forKey: "inputMask")
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let result = filter.outputImage?.cropped(to: color.extent),
              let rendered = context.createCGImage(result, from: color.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!) else {
            throw CameraError.invalidPhotoData
        }
        return (try SDRImage.rasterize(rendered), distance, depth.depthDataAccuracy == .absolute)
    }
}
