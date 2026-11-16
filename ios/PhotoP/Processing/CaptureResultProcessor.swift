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
    var outputWidth: Int? = nil
    var outputHeight: Int? = nil
    var depthSource: String? = nil
    var depthMapFilename: String? = nil
    var depthMapSHA256: String? = nil
    var depthWidth: Int? = nil
    var depthHeight: Int? = nil
    var depthUnits: String? = nil
    var portraitMatteUsed: Bool? = nil
    var lensProfile: DepthLensProfile? = nil
    var matteWidth: Int? = nil
    var matteHeight: Int? = nil
    var matteSHA256: String? = nil
    var fusionNormalizedError: Double? = nil
}

// No camera/display resources: only runs AFTER original bytes are preserved.
actor CaptureResultProcessor {
    static let shared = CaptureResultProcessor()

    func reprocess(result: URL, original: URL, aperture: Double, documents: URL? = nil,
                   focus: CGPoint? = nil, profile: DepthLensProfile? = nil) async throws -> URL {
        let root = try documents ?? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = result.deletingLastPathComponent()
        guard result.lastPathComponent == "photo.jpg",
              folder.resolvingSymlinksInPath().deletingLastPathComponent().path == root.appendingPathComponent("CaptureResults").resolvingSymlinksInPath().path else {
            throw ImageEditingError.invalid("심도 결과 경로가 유효하지 않습니다.")
        }
        let recipe = try JSONDecoder().decode(CaptureResultRecipe.self, from: bounded(folder.appendingPathComponent("recipe.json"), limit: 131_072))
        guard [2, 3].contains(recipe.version), recipe.originalFilename == original.lastPathComponent,
              recipe.originalSHA256 == (try LUTPhotoEditor.hashFile(original)),
              recipe.depthMapFilename == "depth.f32", let hash = recipe.depthMapSHA256,
              let w = recipe.depthWidth, let h = recipe.depthHeight,
              w >= 3, h >= 3, w <= 4096, h <= 4096, w * h <= 2_097_152,
              let unit = recipe.depthUnits.flatMap(SoftwareDepthField.Units.init(rawValue:)) else {
            throw ImageEditingError.invalid("원본 또는 저장 심도 레시피가 변경되었거나 지원되지 않습니다.")
        }
        let bytes = try bounded(folder.appendingPathComponent("depth.f32"), limit: w * h * 4)
        guard bytes.count == w * h * 4, LUTPhotoEditor.hash(bytes) == hash else { throw CameraError.invalidPhotoData }
        let values: [Float] = bytes.withUnsafeBytes { raw in
            (0..<(w * h)).map { Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self))) }
        }
        guard let field = SoftwareDepthField(width: w, height: h, inverseDepth: values, units: unit) else { throw CameraError.invalidPhotoData }
        var matte: DepthMatteSurface?
        if let hash = recipe.matteSHA256 {
            guard let mw = recipe.matteWidth, let mh = recipe.matteHeight, (3...512).contains(mw), (3...512).contains(mh) else { throw CameraError.invalidPhotoData }
            let data = try bounded(folder.appendingPathComponent("matte.f32"), limit: mw * mh * 28)
            guard LUTPhotoEditor.hash(data) == hash, let decoded = DepthMatteSurface.decode(data, width: mw, height: mh) else { throw CameraError.invalidPhotoData }
            matte = decoded
        }
        var look: ImportedLUT?
        if let expected = recipe.lutSHA256 {
            let data = try bounded(folder.appendingPathComponent("look.cube"), limit: CubeLUT.maximumFileBytes)
            guard LUTPhotoEditor.hash(data) == expected, let text = String(data: data, encoding: .utf8) else { throw CameraError.invalidPhotoData }
            look = ImportedLUT(data: data, lut: try CubeLUT.parse(text), displayName: "촬영 당시 룩", preset: recipe.look, provenance: recipe.provenance)
        } else if recipe.look != nil { throw CameraError.invalidPhotoData }
        return try await render(original: original, look: look, aperture: aperture,
            focus: focus ?? CGPoint(x: recipe.focusX, y: recipe.focusY), documents: root, depthOverride: field,
            profile: profile ?? recipe.lensProfile ?? .natural, savedMatte: matte, depthOrigin: recipe.depthSource)
    }

    private func bounded(_ url: URL, limit: Int) throws -> Data {
        let info = try url.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey, .isRegularFileKey])
        guard info.isSymbolicLink != true, info.isRegularFile == true, let size = info.fileSize, size > 0, size <= limit else { throw CameraError.invalidPhotoData }
        let bytes = try Data(contentsOf: url)
        guard bytes.count <= limit else { throw CameraError.invalidPhotoData }; return bytes
    }

    func render(original: URL, look: ImportedLUT?, aperture: Double?, focus: CGPoint, documents: URL? = nil,
                depthSource: SoftwareDepthSource = .measured, depthOverride: SoftwareDepthField? = nil,
                profile: DepthLensProfile = .natural, savedMatte: DepthMatteSurface? = nil, depthOrigin: String? = nil) async throws -> URL {
        guard look != nil || aperture != nil else { return original }
        let settings = look.map { $0.preset ?? ProcessingLookSettings() }
        try settings?.validate()
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
            let result = try await HighResolutionPhotoProcessor.shared.renderJPEG(original: original,
                destination: pending.appendingPathComponent("photo.jpg"), lut: look?.lut, settings: settings ?? ProcessingLookSettings(),
                aperture: aperture, focus: focus, credit: credit, depthSource: depthSource, depthOverride: depthOverride,
                profile: profile, savedMatte: savedMatte)
            let depthStep = aperture == nil ? "no depth effect" : result.depthField != nil ? "linear-working-space Natural disk layers (max12.6MP)" : "legacy measured variable blur (high-resolution baseline)"
            var recipe = CaptureResultRecipe(version: 3, originalFilename: original.lastPathComponent,
                originalSHA256: try LUTPhotoEditor.hashFile(original), aperture: aperture,
                focusX: Double(focus.x), focusY: Double(focus.y), focusDistanceMetres: result.absoluteDepth ? result.focusDepth : nil,
                focusDepthValue: result.focusDepth, depthAccuracy: aperture == nil ? nil : result.absoluteDepth ? "absolute" : "relative",
                look: settings, lutSHA256: look.map { LUTPhotoEditor.hash($0.data) }, provenance: look?.provenance,
                pipeline: "Oriented color-managed SDR → \(depthStep) → encoded-sRGB LUT/grain/finish halo tiles → disk-backed RGBA → JPEG; original preserved; derivatives omit original metadata")
            recipe.outputWidth = result.width; recipe.outputHeight = result.height
            recipe.depthSource = depthOrigin ?? result.depthSource; recipe.portraitMatteUsed = result.matteUsed
            recipe.lensProfile = aperture == nil ? nil : profile; recipe.fusionNormalizedError = result.fusionError
            if let matte = result.matte {
                let bytes = matte.encoded(); try bytes.write(to: pending.appendingPathComponent("matte.f32"), options: options)
                recipe.matteWidth = matte.width; recipe.matteHeight = matte.height; recipe.matteSHA256 = LUTPhotoEditor.hash(bytes)
            }
            if let field = result.depthField {
                let words = field.inverseDepth.map { $0.bitPattern.littleEndian }
                let bytes = words.withUnsafeBytes { Data($0) }
                try bytes.write(to: pending.appendingPathComponent("depth.f32"), options: options)
                recipe.depthMapFilename = "depth.f32"; recipe.depthMapSHA256 = LUTPhotoEditor.hash(bytes)
                recipe.depthWidth = field.width; recipe.depthHeight = field.height; recipe.depthUnits = field.units.rawValue
            }
            try Task.checkCancellation()
            try JSONEncoder().encode(recipe).write(to: pending.appendingPathComponent("recipe.json"), options: options)
            if let look { try look.data.write(to: pending.appendingPathComponent("look.cube"), options: options) }
            try FileManager.default.moveItem(at: pending, to: final)
            return final.appendingPathComponent("photo.jpg")
        } catch { try? FileManager.default.removeItem(at: pending); throw error }
    }

}

enum MeasuredDepthEffect {
    static func make(original: URL, color: CIImage, width: Int, height: Int, aperture: Double, focus: CGPoint) throws -> (image: CIImage, focus: Float, absolute: Bool) {
        guard let radius = DepthBlurPolicy.radius(aperture: aperture, longEdge: max(width, height)),
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
        guard w > 0, h > 0, abs((Double(w) / Double(h)) / (Double(width) / Double(height)) - 1) < 0.02 else {
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
                                   provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { throw CameraError.configuration }
        return (try compose(color: color, mask: cgMask, width: width, height: height, radius: radius), distance, depth.depthDataAccuracy == .absolute)
    }
    // Separate image graph construction from AVDepthData extraction for SDK
    // tests. Production callers still require measured embedded photo depth.
    static func compose(color: CIImage, mask: CGImage, width: Int, height: Int, radius: Double) throws -> CIImage {
        guard HighResolutionPlan(width: width, height: height) != nil, radius.isFinite, (0...80).contains(radius),
              color.extent == CGRect(x: 0, y: 0, width: width, height: height), mask.width > 0, mask.height > 0,
              let filter = CIFilter(name: "CIMaskedVariableBlur") else { throw CameraError.configuration }
        let w = mask.width, h = mask.height
        let scaledMask = CIImage(cgImage: mask, options: [.colorSpace: NSNull()])
            .transformed(by: CGAffineTransform(scaleX: CGFloat(width) / CGFloat(w), y: CGFloat(height) / CGFloat(h)))
        filter.setValue(color.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(scaledMask, forKey: "inputMask")
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let result = filter.outputImage?.cropped(to: color.extent) else {
            throw CameraError.invalidPhotoData
        }
        return result
    }
}
