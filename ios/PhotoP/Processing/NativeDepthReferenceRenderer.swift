@preconcurrency import CoreImage
import Foundation

// Independent same-input reference for diagnostics/tests, not the Camera app's
// proprietary pipeline and not a silent replacement for our lens renderer.
struct NativeDepthReferenceResult {
    let image: CIImage
    let supportedInputKeys: [String]
    let apertureApplied: Bool
    let focusApplied = false // no undocumented focus-key convention is assumed
}

enum NativeDepthReferenceRenderer {
    static func make(color: CIImage, depth: NativePhotoDepth, aperture: Double, context: CIContext) throws -> NativeDepthReferenceResult? {
        guard depth.geometry.matchesOrientedColor(width: Int(color.extent.width), height: Int(color.extent.height)),
              aperture.isFinite, (1.4...16).contains(aperture) else { throw CameraError.invalidSettings }
        guard let filter = context.depthBlurEffectFilter(for: color, disparityImage: depth.disparity,
            portraitEffectsMatte: nil, orientation: .up, options: nil) else { return nil }
        let apertureApplied = filter.inputKeys.contains("inputAperture")
        if apertureApplied { filter.setValue(aperture, forKey: "inputAperture") }
        guard let output = filter.outputImage else { return nil }
        return .init(image: output.cropped(to: color.extent), supportedInputKeys: filter.inputKeys, apertureApplied: apertureApplied)
    }
}
