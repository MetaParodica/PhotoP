@preconcurrency import AVFoundation
@preconcurrency import CoreImage
import CoreVideo
import ImageIO
import Foundation

struct NaturalDepthResult {
    let image: CIImage
    let field: SoftwareDepthField
    let focusInverse: Float
    let source: String
    let matteUsed: Bool
    var matte: DepthMatteSurface? = nil
    var fusionError: Double? = nil
}

// Initial Natural renderer: bounded inverse-depth layers, disk PSF, far-to-near
// premultiplied compositing, local background extension, original focus plane.
// This is an approximation, not a measured commercial-lens PSF or hidden-scene GT.
// Owned only by the high-resolution processing actor.
final class NaturalDepthEngine {
    private let estimator = ExternalDepthEstimator()
    private let matteRefiner = DepthMatteRefiner()
    private let lensFilter = DepthLensFilter()
    private var sliceKernel: CIColorKernel?
    private var backgroundKernel: CIColorKernel?
    private var planeKernel: CIColorKernel?
    private var edgeKernel: CIColorKernel?
    private var coverageKernel: CIColorKernel?
    private var matteCache: (id: UUID, extent: CGRect, images: (alpha: CIImage, foreground: CIImage, background: CIImage))?

    func render(original: URL, color: CIImage, width: Int, height: Int, aperture: Double,
                focus: CGPoint, source: SoftwareDepthSource, override: SoftwareDepthField? = nil,
                profile: DepthLensProfile = .natural, savedMatte: DepthMatteSurface? = nil,
                qualityPairs: Int = 16, includeMatte: Bool = true) throws -> NaturalDepthResult {
        guard SoftwareDepthPolicy.supports(width: width, height: height),
              aperture.isFinite, (1.4...16).contains(aperture) else {
            throw ImageEditingError.invalid("심도 처리는 최대64MP·긴 변16384px 일반 사진에서 지원합니다. 원본은 보존됩니다.")
        }
        try Task.checkCancellation()
        let measured = source == .ai || override != nil ? nil : try Self.measured(original)
        var field: SoftwareDepthField
        var origin: String
        var fusionError: Double?
        if let override { field = override; origin = "saved-depth" }
        else if let measured { field = measured; origin = "photo-depth" }
        else {
            guard source != .measured else {
                throw ImageEditingError.invalid("사진 깊이 데이터가 없습니다. AI 대체를 선택하거나 원본을 사용하세요.")
            }
            field = try estimator.estimate(color); origin = SoftwareDepthPolicy.modelID
        }
        if override == nil, source == .automatic, measured != nil,
           field.inverseDepth.contains(0), let prediction = try? estimator.estimate(color) {
            let fusion = DepthFusionCore.fuse(measured: field, predicted: prediction)
            if fusion.filled > 0 { field = fusion.field; origin = "photo-depth+calibrated-ai"; fusionError = fusion.calibration?.normalizedError }
        }
        if origin.hasPrefix("photo-depth"), abs((Double(field.width) / Double(field.height)) / (Double(width) / Double(height)) - 1) >= 0.02 {
            throw ImageEditingError.invalid("사진과 센서 깊이 좌표 비율이 다릅니다. 원본은 보존됩니다.")
        }
        let embedded = try Self.portraitMatte(original, extent: color.extent)
        let matte = savedMatte ?? (includeMatte ? try? matteRefiner.refine(color: color, focus: focus, embedded: embedded) : nil)
        return try renderField(color: color, field: field, aperture: aperture, focus: focus, profile: profile,
            matte: matte, embedded: embedded, source: origin, fusionError: fusionError, qualityPairs: qualityPairs)
    }

    func renderField(color: CIImage, field: SoftwareDepthField, aperture: Double, focus: CGPoint,
                     profile: DepthLensProfile = .natural, matte: DepthMatteSurface? = nil, embedded: CIImage? = nil,
                     source: String = "live-ai", fusionError: Double? = nil, qualityPairs: Int = 16) throws -> NaturalDepthResult {
        guard color.extent.width.isFinite, color.extent.height.isFinite,
              color.extent.width > 0, color.extent.height > 0,
              color.extent.width <= 16384, color.extent.height <= 16384 else { throw CameraError.invalidPhotoData }
        let width = Int(color.extent.width), height = Int(color.extent.height)
        guard SoftwareDepthPolicy.supports(width: width, height: height), aperture.isFinite, (1.4...16).contains(aperture) else { throw CameraError.invalidSettings }
        guard let focusValue = field.focusValue(x: Double(focus.x), y: Double(focus.y)), let bounds = field.bounds else {
            throw ImageEditingError.invalid("초점 위치 또는 깊이 대비가 불확실합니다. 다른 위치를 선택하세요. 원본은 보존됩니다.")
        }
        let span = bounds.upper - bounds.lower
        let longEdge = max(width, height)
        let radiusLimit = SoftwareDepthPolicy.maximumRadius(longEdge: longEdge)
        let coordinates = field.inverseDepth.map { value -> Float in
            guard value > 0, let radius = SoftwareDepthPolicy.radius(inverse: Double(value), focus: Double(focusValue),
                span: Double(span), absolute: field.units == .inverseMetres, aperture: aperture, longEdge: longEdge, focalLengthMM: profile.focalLengthMM) else { return 0.5 }
            return SoftwareDepthPolicy.blurCoordinate(radius: radius, longEdge: longEdge) ?? 0.5
        }
        let validity = field.inverseDepth.map { $0 > 0 ? UInt8(255) : 0 }
        let extent = color.extent
        // A stored instance matte belongs to the original subject. Refocusing
        // on another object must not pin the new sharp plane to that old mask.
        let selectedMatte = matte.flatMap { surface -> DepthMatteSurface? in
            let x = min(surface.width - 1, max(0, Int(focus.x * CGFloat(surface.width))))
            let y = min(surface.height - 1, max(0, Int(focus.y * CGFloat(surface.height))))
            return surface.alpha[y * surface.width + x] > 0.5 ? surface : nil
        }
        let effectiveEmbedded = matte == nil ? embedded : nil
        let matteImages = try selectedMatte.map { surface in
            if let cached = matteCache, cached.id == surface.id, cached.extent == extent { return cached.images }
            let images = try DepthMatteRefiner.images(surface, extent: extent)
            matteCache = (surface.id, extent, images)
            return images
        }
        var sourceColor = color
        if let matteImages {
            let kernel = try Self.kernel(&edgeKernel, source: """
            kernel vec4 photopEdgeColor(__sample c, __sample f, __sample a) {
                float w=4.0*a.r*(1.0-a.r); return mix(c,f,w);
            }
            """)
            let edge = kernel.apply(extent: extent, arguments: [color, matteImages.foreground, matteImages.alpha])
            if let edge { sourceColor = edge }
        }
        // Float data avoids 8-bit quantization around the focal plane. Compute
        // CoC BEFORE resampling; small close foreground objects outside the
        // 2/98 percentile range keep their signed radius instead of flattening.
        let map = try Self.mask(coordinates, width: field.width, height: field.height, extent: extent)
        let valid = try Self.mask(validity, width: field.width, height: field.height, extent: extent)
        let focusNormalized = 0.5
        let slice = try Self.kernel(&sliceKernel, source: """
        kernel vec4 photopDepthSlice(__sample c, __sample d, __sample valid, __sample alpha, float lo, float center, float hi, float focus) {
            float w = d.r <= center ? (d.r-lo)/max(0.00001,center-lo) : (hi-d.r)/max(0.00001,hi-center);
            float edge=4.0*alpha.r*(1.0-alpha.r);
            float target=1.0-smoothstep(0.05,0.18,abs(d.r-focus));
            return c * clamp(w,0.0,1.0) * valid.r * mix(1.0,alpha.r,edge*target);
        }
        """)
        let fill = try Self.kernel(&backgroundKernel, source: """
        kernel vec4 photopDepthFill(__sample c, __sample fallback) {
            return c.a > 0.01 ? vec4(c.rgb/c.a,1.0) : fallback;
        }
        """)
        let plane = try Self.kernel(&planeKernel, source: """
        kernel vec4 photopFocusPlane(__sample d, __sample valid, float sharp, float soft) {
            float w = (1.0-smoothstep(sharp,soft,abs(d.r-0.5))) * valid.r;
            return vec4(w,w,w,1.0);
        }
        """)
        let centers = SoftwareDepthPolicy.layerCenters(qualityPairs: qualityPairs)
        // The fill only estimates occluded background; never claim it recovers
        // unseen detail. Foreground layers subsequently overwrite it by depth.
        let effectScale = Double(max(width, height)) / 4032
        var result = color.clampedToExtent().applyingFilter("CIDiscBlur", parameters: [kCIInputRadiusKey: 24 * effectScale]).cropped(to: extent)
        var foreground = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: extent)
        for i in centers.indices {
            try Task.checkCancellation()
            let center = centers[i], lo = i == 0 ? -0.0625 : centers[i - 1], hi = i == centers.count - 1 ? 1.0625 : centers[i + 1]
            let signedRadius = (0.5 - center) * 2 * radiusLimit
            guard var layer = slice.apply(extent: extent, arguments: [sourceColor, map, valid,
                    matteImages?.alpha ?? CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: extent),
                    lo, center, hi, focusNormalized]) else { throw CameraError.configuration }
            let radius = abs(signedRadius)
            if radius > 0.3 { layer = try lensFilter.blur(layer, radius: radius, profile: profile, aperture: aperture, pairs: qualityPairs) }
            if i == 0 {
                // Extend only background samples into the occluded boundary.
                // Keep known sharp background intact; filling must not simply
                // blur foreground colors into the newly revealed background.
                let extended = layer.clampedToExtent().applyingFilter("CIDiscBlur", parameters: [kCIInputRadiusKey: 48 * effectScale]).cropped(to: extent)
                guard let localFill = fill.apply(extent: extent, arguments: [extended, result]),
                      let background = fill.apply(extent: extent, arguments: [layer, localFill]) else { throw CameraError.configuration }
                result = background
            } else if signedRadius < -0.3 {
                // Adjacent triangular depth bins are coverage fractions of
                // the same surface. Source-over would attenuate them twice.
                foreground = layer.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: foreground])
            } else { result = layer.composited(over: result) }
        }
        let sharpCoordinate = SoftwareDepthPolicy.sharpRadius / 96
        let softCoordinate = SoftwareDepthPolicy.softRadius / 96
        guard var sharp = plane.apply(extent: extent, arguments: [map, valid, sharpCoordinate, softCoordinate]) else { throw CameraError.configuration }
        // An embedded portrait matte is a boundary aid, not metric depth. Use
        // only around the focal plane rather than flattening the entire person.
        if let alpha = matteImages?.alpha ?? effectiveEmbedded {
            sharp = sharp.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: alpha])
        }
        result = color.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: result, kCIInputMaskImageKey: sharp])
        // Foreground bokeh must spread over a sharp background. Restoring the
        // focus plane AFTER this step would erase that physically important spill.
        let coverage = try Self.kernel(&coverageKernel, source: """
        kernel vec4 photopNearCoverage(__sample c) {
            float a=clamp(c.a,0.0,1.0);
            return c.a>0.00001 ? vec4(c.rgb*(a/c.a),a) : vec4(0.0);
        }
        """)
        guard let near = coverage.apply(extent: extent, arguments: [foreground]) else { throw CameraError.configuration }
        result = near.composited(over: result)
        result = result.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: color, kCIInputMaskImageKey: valid]).cropped(to: extent)
        return NaturalDepthResult(image: result, field: field, focusInverse: focusValue, source: source,
            matteUsed: matteImages != nil || effectiveEmbedded != nil, matte: matte, fusionError: fusionError)
    }

    private static func kernel(_ cache: inout CIColorKernel?, source: String) throws -> CIColorKernel {
        if let cache { return cache }
        guard let value = CIColorKernel(source: source) else { throw CameraError.configuration }
        cache = value; return value
    }

    private static func mask(_ values: [Float], width: Int, height: Int, extent: CGRect) throws -> CIImage {
        let data = values.withUnsafeBytes { Data($0) }
        guard let provider = CGDataProvider(data: data as CFData),
              let cg = CGImage(width: width, height: height, bitsPerComponent: 32, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: [.floatComponents, .byteOrder32Little, CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)],
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { throw CameraError.invalidPhotoData }
        // Match the existing top-left depth/validity CGImage row convention.
        // CoC is numeric data and must not undergo a display-gray gamma curve.
        return CIImage(cgImage: cg, options: [.colorSpace: NSNull()])
            .transformed(by: CGAffineTransform(scaleX: extent.width / CGFloat(width), y: extent.height / CGFloat(height)))
    }

    private static func mask(_ bytes: [UInt8], width: Int, height: Int, extent: CGRect) throws -> CIImage {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let cg = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { throw CameraError.invalidPhotoData }
        // Depth/matte values are data, not display gray: no gamma conversion.
        return CIImage(cgImage: cg, options: [.colorSpace: NSNull()])
            .transformed(by: CGAffineTransform(scaleX: extent.width / CGFloat(width), y: extent.height / CGFloat(height)))
    }

    private static func portraitMatte(_ url: URL, extent: CGRect) throws -> CIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let info = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypePortraitEffectsMatte) as? [AnyHashable: Any] else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = CGImagePropertyOrientation(rawValue: (properties?[kCGImagePropertyOrientation] as? UInt32) ?? 1) ?? .up
        let matte = try AVPortraitEffectsMatte(fromDictionaryRepresentation: info).applyingExifOrientation(orientation)
        let image = CIImage(cvPixelBuffer: matte.mattingImage, options: [.colorSpace: NSNull()])
        return image.transformed(by: CGAffineTransform(scaleX: extent.width / image.extent.width, y: extent.height / image.extent.height))
    }

    private static func measured(_ url: URL) throws -> SoftwareDepthField? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let dictionary = (CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeDepth)
                ?? CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeDisparity)) as? [AnyHashable: Any] else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = CGImagePropertyOrientation(rawValue: (properties?[kCGImagePropertyOrientation] as? UInt32) ?? 1) ?? .up
        let data = try AVDepthData(fromDictionaryRepresentation: dictionary).applyingExifOrientation(orientation)
            .converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        let buffer = data.depthDataMap, w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        guard w >= 3, h >= 3, w <= 4096, h <= 4096, w * h <= 2_097_152,
              CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { throw CameraError.invalidPhotoData }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        guard stride >= w * 4, let base = CVPixelBufferGetBaseAddress(buffer) else { throw CameraError.invalidPhotoData }
        var values = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            let row = base.advanced(by: y * stride).assumingMemoryBound(to: Float.self)
            for x in 0..<w { let z = row[x]; values[y * w + x] = z.isFinite && z > 0 ? 1 / z : 0 }
        }
        return SoftwareDepthField(width: w, height: h, inverseDepth: values,
                                  units: data.depthDataAccuracy == .absolute ? .inverseMetres : .relativeInverse)
    }
}
