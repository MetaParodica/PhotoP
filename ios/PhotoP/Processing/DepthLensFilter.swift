@preconcurrency import CoreImage
import Foundation

// Unrolled Core Image kernel: avoids unsupported dynamic loops and uses the
// same normalized taps as the portable reference. Cache is deliberately bounded.
final class DepthLensFilter {
    private var key: String?
    private var kernel: CIKernel?
    func blur(_ image: CIImage, radius: Double, profile: DepthLensProfile, aperture: Double, pairs: Int = 16) throws -> CIImage {
        guard radius > 0.3 else { return image }
        let n = min(24, max(4, pairs))
        let nextKey = "\(profile.rawValue):\(n)"
        if key != nextKey || kernel == nil {
            let taps = DepthLensKernel.taps(profile: profile == .classic ? .natural : profile, aperture: aperture, pairs: n)
            let closed = DepthLensKernel.taps(profile: .classic, aperture: 8, pairs: n)
            func number(_ value: Double) -> String { String(format: "%.9f", locale: Locale(identifier: "en_US_POSIX"), value) }
            var source = "kernel vec4 photopLens(sampler s, float radius, vec2 center, float longEdge, float aperture) { vec2 p=destCoord(); vec4 sum=vec4(0.0);"
            if profile == .classic {
                source += "vec2 radial=(p-center)/max(1.0,longEdge); float rr=length(radial); vec2 axis=radial/max(0.0001,rr); float squeeze=1.0-min(0.40,rr*rr*1.2);"
            }
            for (i, tap) in taps.enumerated() {
                source += "{vec2 o=vec2(\(number(tap.x)),\(number(tap.y)));"
                if profile == .classic {
                    let radius = sqrt(tap.x * tap.x + tap.y * tap.y)
                    let ratio = radius > 0.00001 ? sqrt(closed[i].x * closed[i].x + closed[i].y * closed[i].y) / radius : 1
                    source += "o*=mix(1.0,\(number(ratio)),clamp((aperture-1.4)/6.6,0.0,1.0));o+=axis*dot(o,axis)*(squeeze-1.0);"
                }
                source += "sum+=sample(s,samplerTransform(s,p+o*radius))*\(number(tap.weight));}"
            }
            source += "return sum;}"
            guard let compiled = CIKernel(source: source) else { throw CameraError.configuration }
            kernel = compiled; key = nextKey
        }
        let extent = image.extent, halo = CGFloat(ceil(radius) + 2)
        guard let result = kernel?.apply(extent: extent, roiCallback: { _, rect in rect.insetBy(dx: -halo, dy: -halo) },
            arguments: [image.clampedToExtent(), radius, CIVector(x: extent.midX, y: extent.midY), max(extent.width, extent.height), aperture]) else { throw CameraError.configuration }
        return result.cropped(to: extent)
    }
}
