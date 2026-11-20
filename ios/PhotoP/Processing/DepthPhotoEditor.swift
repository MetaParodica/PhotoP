import Foundation
import CoreImage

// Owns an oriented, bounded ORIGINAL image. Preview and export use the same
// saved depth/matte and lens pipeline; opening never runs Vision/Core ML again.
actor DepthPhotoEditor {
    private let session: DepthEditSession
    private let engine = NaturalDepthEngine()
    private let context = CIContext(options: [.cacheIntermediates: false,
        .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!])
    private var image: CIImage?
    private var renderer: MetalLUTRenderer?
    private var corrected: (DepthCorrections, SoftwareDepthField)?
    init(session: DepthEditSession) { self.session = session }

    func preview(aperture: Double, focus: CGPoint, profile: DepthLensProfile, original: Bool, corrections: DepthCorrections? = nil, diagnostic: DepthDiagnostic = .result) async throws -> SDRImage {
        try Task.checkCancellation()
        if image == nil {
            let pixels = try SDRImage.decode(session.original, previewMaxDimension: 768)
            image = CIImage(cgImage: try pixels.cgImage())
        }
        guard let image else { throw CameraError.invalidPhotoData }
        let edits = corrections ?? session.corrections
        if corrected?.0 != edits {
            guard let field = edits.applying(to: session.field, isCancelled: { Task.isCancelled }) else {
                try Task.checkCancellation(); throw CameraError.invalidSettings
            }
            corrected = (edits, field)
        }
        guard let field = corrected?.1 else { throw CameraError.invalidPhotoData }
        if !original, diagnostic != .result {
            return try diagnosticPixels(image: image, field: field, focus: focus, aperture: aperture, profile: profile, mode: diagnostic)
        }
        let color = original ? image : try engine.renderField(color: image, field: field, aperture: aperture,
            focus: focus, profile: profile, matte: session.matte, source: "saved-depth").image
        try Task.checkCancellation()
        guard let cg = context.createCGImage(color, from: image.extent, format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!) else { throw CameraError.invalidPhotoData }
        let pixels = try SDRImage.rasterize(cg)
        if !original, let look = session.look {
            if renderer == nil { renderer = try MetalLUTRenderer(lut: look.lut) }
            let settings = look.preset ?? ProcessingLookSettings()
            guard let renderer else { throw CameraError.invalidPhotoData }
            let bytes = try await renderer.render(pixels.rgba, width: pixels.width, height: pixels.height,
                intensity: settings.intensity, grain: settings.grain, effects: settings.finish)
            try Task.checkCancellation()
            return SDRImage(rgba: bytes, width: pixels.width, height: pixels.height)
        }
        return pixels
    }

    func save(aperture: Double, focus: CGPoint, profile: DepthLensProfile, corrections: DepthCorrections? = nil) async throws -> URL {
        try await CaptureResultProcessor.shared.reprocess(result: session.result, original: session.original,
            aperture: aperture, focus: focus, profile: profile, corrections: corrections ?? session.corrections)
    }
    private func diagnosticPixels(image: CIImage, field: SoftwareDepthField, focus: CGPoint, aperture: Double,
                                  profile: DepthLensProfile, mode: DepthDiagnostic) throws -> SDRImage {
        let w = Int(image.extent.width), h = Int(image.extent.height)
        guard let cg = context.createCGImage(image, from: image.extent), let bounds = field.bounds else { throw CameraError.invalidPhotoData }
        let original = try SDRImage.rasterize(cg)
        var bytes = original.rgba
        let focusValue = field.focusValue(x: Double(focus.x), y: Double(focus.y)) ?? bounds.upper
        for y in 0..<h {
            try Task.checkCancellation()
            for x in 0..<w {
                let nx = (Double(x)+0.5)/Double(w), ny = (Double(y)+0.5)/Double(h), i = (y*w+x)*4
                let fx = min(field.width-1,Int(nx*Double(field.width))), fy = min(field.height-1,Int(ny*Double(field.height)))
                let depth = field.inverseDepth[fy*field.width+fx]
                let alpha = session.matte.map { surface in
                    DepthGrid.sample(surface.alpha, width: surface.width, height: surface.height,
                        x: nx*Double(surface.width)-0.5, y: ny*Double(surface.height)-0.5)
                }
                var value: Float = 0
                switch mode {
                case .result: break
                case .depth: value = depth > 0 ? min(1,max(0,(depth-bounds.lower)/(bounds.upper-bounds.lower))) : 0
                case .matte: value = alpha ?? 0
                case .uncertainty: value = depth <= 0 ? 1 : alpha.map { 4*$0*(1-$0) } ?? 0
                case .focusPlane:
                    let radius = SoftwareDepthPolicy.radius(inverse: Double(depth), focus: Double(focusValue), span: Double(bounds.upper-bounds.lower),
                        absolute: field.units == .inverseMetres, aperture: aperture, longEdge: max(w,h), focalLengthMM: profile.focalLengthMM)
                    if let radius, abs(radius) <= SoftwareDepthPolicy.softRadius {
                        bytes[i] /= 2; bytes[i+1] = max(180,bytes[i+1]); bytes[i+2] /= 2
                    }
                    continue
                }
                let level = UInt8(min(255,max(0,Int((value*255).rounded()))))
                bytes[i] = level; bytes[i+1] = level; bytes[i+2] = mode == .uncertainty ? 0 : level; bytes[i+3] = 255
            }
        }
        return SDRImage(rgba: bytes, width: w, height: h)
    }

}
