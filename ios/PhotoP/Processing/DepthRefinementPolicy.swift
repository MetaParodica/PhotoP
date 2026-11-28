import Foundation

struct NativeDepthRefinement: Codable, Equatable, Sendable {
    static let method = "mps-guided-native-v1"
    let methodID: String
    let outputWidth: Int
    let outputHeight: Int
    let normalizationLower: Float
    let normalizationUpper: Float
    var valid: Bool {
        methodID == Self.method && (3...4096).contains(outputWidth) && (3...4096).contains(outputHeight)
        && outputWidth * outputHeight <= 2_097_152 && normalizationLower.isFinite && normalizationUpper.isFinite
        && normalizationLower > 0 && normalizationUpper > normalizationLower
    }
}

enum DepthRefinementPolicy {
    static func outputSize(colorWidth: Int, colorHeight: Int, depthWidth: Int, depthHeight: Int) -> (width: Int, height: Int)? {
        guard (3...16384).contains(colorWidth), (3...16384).contains(colorHeight),
              colorWidth * colorHeight <= 64_000_000,
              (3...4096).contains(depthWidth), (3...4096).contains(depthHeight) else { return nil }
        let scale = min(1, 1536 / Double(max(colorWidth, colorHeight)),
            sqrt(2_097_152 / (Double(colorWidth) * Double(colorHeight))))
        let w = Int(floor(Double(colorWidth)*scale)), h = Int(floor(Double(colorHeight)*scale))
        guard w > depthWidth, h > depthHeight, w*h <= 2_097_152,
              abs(Double(w)*Double(depthHeight)/(Double(h)*Double(depthWidth))-1) < 0.02 else { return nil }
        return (w, h)
    }

    // Guided estimates remain derived data. Constant surfaces are anchored,
    // ringing is clamped to LOCAL observed depths, missing nearest cells stay
    // missing. No neural inference, invented metres or cross-edge hole filling.
    static func constrained(base: SoftwareDepthField, candidate: [Float], width: Int, height: Int,
                            isCancelled: () -> Bool = { false }) -> SoftwareDepthField? {
        guard let info = base.nativeMetadata, info.refinement == nil, let bounds = base.bounds,
              (3...4096).contains(width), (3...4096).contains(height), width*height <= 2_097_152,
              candidate.count == width*height,
              abs(Double(width)*Double(base.height)/(Double(height)*Double(base.width))-1) < 0.02 else { return nil }
        var values = [Float](repeating: 0, count: width*height)
        for y in 0..<height {
            if isCancelled() { return nil }
            let sy = min(base.height-1, Int((Double(y)+0.5)*Double(base.height)/Double(height)))
            for x in 0..<width {
                let sx = min(base.width-1, Int((Double(x)+0.5)*Double(base.width)/Double(width)))
                let anchor = base.inverseDepth[sy*base.width+sx]
                guard anchor > 0 else { continue }
                var lo = anchor, hi = anchor
                for j in max(0,sy-1)...min(base.height-1,sy+1) {
                    for i in max(0,sx-1)...min(base.width-1,sx+1) {
                        let v = base.inverseDepth[j*base.width+i]
                        if v > 0 { lo = min(lo,v); hi = max(hi,v) }
                    }
                }
                let v = candidate[y*width+x]
                values[y*width+x] = v.isFinite && v > 0 ? min(hi,max(lo,v)) : anchor
            }
        }
        var metadata = info
        metadata.refinement = .init(methodID: NativeDepthRefinement.method, outputWidth: width, outputHeight: height,
            normalizationLower: bounds.lower, normalizationUpper: bounds.upper)
        return SoftwareDepthField(width: width, height: height, inverseDepth: values, units: base.units, nativeMetadata: metadata)
    }
}
