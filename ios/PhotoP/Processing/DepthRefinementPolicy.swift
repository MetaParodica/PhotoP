import Foundation

struct NativeDepthRefinement: Codable, Equatable, Sendable {
    static let method = "mps-guided-native-v3"
    let methodID: String
    let outputWidth: Int
    let outputHeight: Int
    let normalizationLower: Float
    let normalizationUpper: Float
    var valid: Bool {
        [Self.method,"mps-guided-native-v1","mps-guided-native-v2"].contains(methodID) && (3...4096).contains(outputWidth) && (3...4096).contains(outputHeight)
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
                            guideEvidence: [UInt8]? = nil,
                            isCancelled: () -> Bool = { false }) -> SoftwareDepthField? {
        guard let info = base.nativeMetadata, info.refinement == nil, let bounds = base.bounds,
              (3...4096).contains(width), (3...4096).contains(height), width*height <= 2_097_152,
              candidate.count == width*height, guideEvidence == nil || guideEvidence?.count == base.inverseDepth.count,
              abs(Double(width)*Double(base.height)/(Double(height)*Double(base.width))-1) < 0.02 else { return nil }
        // Each native neighborhood is reused by several output pixels. Compute
        // its envelope once, rather than scanning 3x3 again per derived pixel.
        var lower = base.inverseDepth, upper = base.inverseDepth
        for y in 0..<base.height {
            if isCancelled() { return nil }
            for x in 0..<base.width where base.inverseDepth[y*base.width+x] > 0 {
                let index = y*base.width+x
                for j in max(0,y-1)...min(base.height-1,y+1) {
                    for i in max(0,x-1)...min(base.width-1,x+1) {
                        let v = base.inverseDepth[j*base.width+i]
                        if v > 0 { lower[index] = min(lower[index],v); upper[index] = max(upper[index],v) }
                    }
                }
            }
        }
        // A strong two-surface jump has no observed middle plane. Without
        // useful RGB contrast the guided filter averages the two surfaces;
        // reject that unsupported center instead of inventing a sloped edge.
        var gapLower = [Float](repeating: 0,count: base.inverseDepth.count)
        var gapUpper = gapLower
        let span = bounds.upper-bounds.lower
        for y in 0..<base.height {
            if isCancelled() { return nil }
            for x in 0..<base.width {
                let index = y*base.width+x, anchor = base.inverseDepth[index]
                let range = upper[index]-lower[index]
                let significant = max(span*0.08,base.units == .inverseMetres ? anchor*0.1 : 0)
                guard anchor > 0, range > significant, guideEvidence?[index] != 1 else { continue }
                let middle = lower[index]+range*0.5
                var low = lower[index], high = upper[index]
                for j in max(0,y-1)...min(base.height-1,y+1) {
                    for i in max(0,x-1)...min(base.width-1,x+1) {
                        let v = base.inverseDepth[j*base.width+i]
                        if v > 0 {
                            if v <= middle { low = max(low,v) } else { high = min(high,v) }
                        }
                    }
                }
                if high-low > range*0.55 { gapLower[index] = low; gapUpper[index] = high }
            }
        }
        var values = [Float](repeating: 0, count: width*height)
        for y in 0..<height {
            if isCancelled() { return nil }
            let sy = min(base.height-1, Int((Double(y)+0.5)*Double(base.height)/Double(height)))
            for x in 0..<width {
                let sx = min(base.width-1, Int((Double(x)+0.5)*Double(base.width)/Double(width)))
                let sourceIndex = sy*base.width+sx
                let anchor = base.inverseDepth[sourceIndex]
                guard anchor > 0 else { continue }
                let v = candidate[y*width+x]
                var value = v.isFinite && v > 0 ? min(upper[sourceIndex],max(lower[sourceIndex],v)) : anchor
                let gap = gapUpper[sourceIndex]-gapLower[sourceIndex]
                if gap > 0, value > gapLower[sourceIndex]+gap*0.2, value < gapUpper[sourceIndex]-gap*0.2 { value = anchor }
                values[y*width+x] = value
            }
        }
        var metadata = info
        metadata.refinement = .init(methodID: NativeDepthRefinement.method, outputWidth: width, outputHeight: height,
            normalizationLower: bounds.lower, normalizationUpper: bounds.upper)
        return SoftwareDepthField(width: width, height: height, inverseDepth: values, units: base.units, nativeMetadata: metadata)
    }
}
