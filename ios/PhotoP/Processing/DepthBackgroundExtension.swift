@preconcurrency import CoreImage
import Foundation

// Bounded, background-only normalized convolution. This estimates local color
// behind an edge; unsupported holes retain the observed original, not invented
// texture or foreground-contaminated all-image blur.
final class DepthBackgroundExtension {
    private var seed: CIColorKernel?
    private var normalize: CIColorKernel?
    func image(color: CIImage, coordinates: CIImage, validity: CIImage, radius: Double) throws -> CIImage {
        if seed == nil { seed = CIColorKernel(source: """
            kernel vec4 photopBackgroundSeed(__sample c, __sample d, __sample v) {
                float w=(1.0-smoothstep(0.485,0.5,d.r))*v.r;
                return c*w;
            }
            """) }
        if normalize == nil { normalize = CIColorKernel(source: """
            kernel vec4 photopBackgroundNormalize(__sample c, __sample observed) {
                return c.a>0.01 ? vec4(c.rgb/c.a,1.0) : observed;
            }
            """) }
        guard radius.isFinite, (0...256).contains(radius),
              let selected = seed?.apply(extent: color.extent, arguments: [color, coordinates, validity]) else { throw CameraError.configuration }
        let extended = selected.clampedToExtent().applyingFilter("CIDiscBlur", parameters: [kCIInputRadiusKey: radius]).cropped(to: color.extent)
        guard let output = normalize?.apply(extent: color.extent, arguments: [extended, color]) else { throw CameraError.configuration }
        return output
    }
}
