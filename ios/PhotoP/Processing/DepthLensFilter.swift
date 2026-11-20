@preconcurrency import CoreImage
import Foundation

// Linear premultiplied PSF. Large-radius pyramid and bounded support are preserved.
final class DepthLensFilter {
    func blur(_ image: CIImage, radius: Double, profile: DepthLensProfile, aperture: Double, pairs: Int = 16) throws -> CIImage {
        guard radius.isFinite, radius >= 0, radius <= 256 else { throw CameraError.invalidSettings }
        guard radius > 0.3 else { return image }
        if radius > 8 {
            // A fixed sparse kernel at 48MP would turn one highlight into a
            // constellation of taps. Band-limit and evaluate large CoCs on a
            // smaller pyramid level, then reconstruct in full-image space.
            let scale = 8 / radius
            let extent = image.extent
            let reducedExtent = extent.applying(CGAffineTransform(scaleX: scale, y: scale))
            let filtered = image.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 0.55 / scale]).cropped(to: extent)
            let reduced = filtered.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1]).cropped(to: reducedExtent)
            let blurred = try kernelBlur(reduced, radius: 8, profile: profile, aperture: aperture, pairs: pairs)
            return blurred.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: 1 / scale, kCIInputAspectRatioKey: 1]).cropped(to: extent)
        }
        return try kernelBlur(image, radius: radius, profile: profile, aperture: aperture, pairs: pairs)
    }
    private func kernelBlur(_ image: CIImage, radius: Double, profile: DepthLensProfile, aperture: Double, pairs: Int) throws -> CIImage {
        let taps = DepthLensKernel.taps(profile: profile, aperture: aperture, pairs: pairs)
        let arguments: [String: Any] = ["radius": radius, "catEye": profile.catEye,
            "extent": CIVector(cgRect: image.extent),
            "taps": taps.map { SIMD4<Float>(Float($0.x), Float($0.y), Float($0.weight), 0) }]
        let output = try DepthPSFProcessor.apply(withExtent: image.extent,
            inputs: [image.clampedToExtent()], arguments: arguments)
        return output.cropped(to: image.extent)
    }
}
