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
    init(session: DepthEditSession) { self.session = session }

    func preview(aperture: Double, focus: CGPoint, profile: DepthLensProfile, original: Bool) async throws -> SDRImage {
        try Task.checkCancellation()
        if image == nil {
            let pixels = try SDRImage.decode(session.original, previewMaxDimension: 768)
            image = CIImage(cgImage: try pixels.cgImage())
        }
        guard let image else { throw CameraError.invalidPhotoData }
        let color = original ? image : try engine.renderField(color: image, field: session.field, aperture: aperture,
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

    func save(aperture: Double, focus: CGPoint, profile: DepthLensProfile) async throws -> URL {
        try await CaptureResultProcessor.shared.reprocess(result: session.result, original: session.original,
            aperture: aperture, focus: focus, profile: profile)
    }
}
