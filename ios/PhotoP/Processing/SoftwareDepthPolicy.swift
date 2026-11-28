import Foundation

enum SoftwareDepthSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic, measured, ai
    var id: String { rawValue }
    var title: String {
        switch self { case .automatic: return "센서 우선·AI 대체"; case .measured: return "사진 깊이만"; case .ai: return "AI 상대 깊이" }
    }
}

struct SoftwareDepthField: Sendable {
    enum Units: String, Codable, Sendable { case inverseMetres, relativeInverse }
    let width: Int
    let height: Int
    // Top-left rows. Larger means nearer. Zero means invalid, not infinity.
    let inverseDepth: [Float]
    let units: Units
    let nativeMetadata: NativeDepthMetadata?
    let bounds: (lower: Float, upper: Float)?
    init?(width: Int, height: Int, inverseDepth: [Float], units: Units, nativeMetadata: NativeDepthMetadata? = nil) {
        guard width >= 3, height >= 3, width <= 4096, height <= 4096, width * height <= 2_097_152,
              width * height == inverseDepth.count, inverseDepth.contains(where: { $0.isFinite && $0 > 0 }),
              nativeMetadata?.valid != false,
              nativeMetadata.map({ $0.absoluteAccuracy == (units == .inverseMetres) }) != false else { return nil }
        self.width = width; self.height = height; self.units = units
        self.nativeMetadata = nativeMetadata
        self.inverseDepth = inverseDepth.map { $0.isFinite && $0 > 0 ? $0 : 0 }
        if let refinement = nativeMetadata?.refinement {
            self.bounds = (refinement.normalizationLower, refinement.normalizationUpper)
        } else { self.bounds = Self.normalizationBounds(self.inverseDepth) }
    }
    private init(width: Int, height: Int, validDepth: [Float], units: Units, bounds: (lower: Float, upper: Float)?, nativeMetadata: NativeDepthMetadata?) {
        self.width = width; self.height = height; self.inverseDepth = validDepth; self.units = units; self.bounds = bounds
        self.nativeMetadata = nativeMetadata
    }
    // Current-frame motion invalidation must not re-sort/re-normalize a model
    // frame. Removing a foreground pixel cannot stretch the background blur.
    func invalidating(where invalid: (Int) -> Bool) -> Self? {
        var data = inverseDepth
        for i in data.indices where invalid(i) { data[i] = 0 }
        guard data.contains(where: { $0 > 0 }) else { return nil }
        return Self(width: width, height: height, validDepth: data, units: units, bounds: bounds, nativeMetadata: nativeMetadata)
    }
    // Manual correction keeps the original scale; brush size cannot renormalize
    // the untouched background or mutate the saved base map.
    func replacingDepthPreservingBounds(_ values: [Float]) -> Self? {
        guard values.count == inverseDepth.count, values.allSatisfy({ $0.isFinite && $0 >= 0 }), values.contains(where: { $0 > 0 }) else { return nil }
        return Self(width: width, height: height, validDepth: values, units: units, bounds: bounds, nativeMetadata: nativeMetadata)
    }
    func resampled(width: Int, height: Int, inverseDepth: [Float]) -> Self? {
        guard (3...4096).contains(width), (3...4096).contains(height), width*height <= 2_097_152,
              inverseDepth.count == width*height, inverseDepth.allSatisfy({ $0.isFinite && $0 >= 0 }),
              inverseDepth.contains(where: { $0 > 0 }) else { return nil }
        return Self(width: width,height: height,validDepth: inverseDepth,units: units,bounds: bounds,nativeMetadata: nativeMetadata)
    }
    func focusValue(x: Double, y: Double) -> Float? {
        DepthFocusEstimator.value(in: self, x: x, y: y)
    }
    private static func normalizationBounds(_ depth: [Float]) -> (lower: Float, upper: Float)? {
        let valid = depth.filter { $0 > 0 }.sorted()
        guard valid.count >= 9 else { return nil }
        var lo = valid[Int(Double(valid.count - 1) * 0.02)]
        var hi = valid[Int(Double(valid.count - 1) * 0.98)]
        // A narrow foreground object can occupy less than 2% of the frame.
        // Preserve it if at least three samples agree, while still rejecting
        // a single isolated depth spike and genuinely uniform depth.
        if hi - lo <= max(0.0001, abs(hi) * 0.001) {
            lo = valid[2]; hi = valid[valid.count - 3]
        }
        guard hi - lo > max(0.0001, abs(hi) * 0.001) else { return nil }
        return (lo, hi)
    }
}

enum SoftwareDepthPolicy {
    static let maximumPixels = 64_000_000
    static let modelID = "apple-depth-anything-v2-small-f16-cfef6f6"
    static func maximumRadius(longEdge: Int) -> Double { 48 * Double(longEdge) / 4032 }
    // Store signed circle of confusion instead of clipping depth percentiles.
    // 0=far blur limit, 0.5=focus, 1=near blur limit. Invalid stays separate.
    static func blurCoordinate(radius: Double, longEdge: Int) -> Float? {
        guard radius.isFinite, longEdge > 0 else { return nil }
        return Float(min(1, max(0, 0.5 - radius / (2 * maximumRadius(longEdge: longEdge)))))
    }
    static func layerCenters(qualityPairs: Int) -> [Double] {
        let half = qualityPairs <= 8 ? 4 : 8
        return (-half...half).map { index in
            let t = Double(index) / Double(half)
            return 0.5 + 0.5 * t * abs(t)
        }
    }
    static let sharpRadius = 0.5
    static let softRadius = 1.5
    static func supports(width: Int, height: Int) -> Bool {
        width >= 3 && height >= 3 && width <= 16384 && height <= 16384 && width * height <= maximumPixels
    }
    static func halo(width: Int, height: Int, fieldWidth: Int, fieldHeight: Int,
                     matteWidth: Int? = nil, matteHeight: Int? = nil) -> Int? {
        guard supports(width: width, height: height), fieldWidth >= 3, fieldHeight >= 3 else { return nil }
        let edge = Double(max(width, height)), scale = edge / 4032
        var cell = max(Double(width) / Double(fieldWidth), Double(height) / Double(fieldHeight))
        if let mw = matteWidth, let mh = matteHeight, mw >= 3, mh >= 3 {
            cell = max(cell, Double(width) / Double(mw), Double(height) / Double(mh))
        }
        // PSF pyramid prefilter/reconstruction + local background extension +
        // interpolated map/matte support. Crop only AFTER evaluating this halo.
        let value = ceil(240 * scale + 2 * cell + 8)
        guard value <= Double(HighResolutionPlan.maximumHalo) else { return nil }
        return Int(value)
    }
    // Signed RADIUS in output pixels; negative=near foreground, positive=far.
    // Absolute input uses a virtual 50mm lens / 36mm long edge, not phone aperture.
    static func radius(inverse: Double, focus: Double, span: Double, absolute: Bool,
                       aperture: Double, longEdge: Int, focalLengthMM: Double = 50) -> Double? {
        guard [inverse, focus, span, aperture, focalLengthMM].allSatisfy(\.isFinite), inverse > 0, focus > 0,
              span > 0, (20...120).contains(focalLengthMM), (1.4...16).contains(aperture), longEdge > 0 else { return nil }
        let value: Double
        if absolute {
            let distance = 1 / focus, focal = focalLengthMM / 1000
            guard distance > focal else { return nil }
            value = focal * focal * distance / (aperture * (distance - focal)) * (focus - inverse) * Double(longEdge) / 0.036 / 2
        } else {
            value = (focus - inverse) / span * Double(longEdge) / 120 * (2.8 / aperture) * pow(focalLengthMM / 50, 2)
        }
        let limit = maximumRadius(longEdge: longEdge)
        return min(limit, max(-limit, value))
    }
}

// Fit and edge-pad into the fixed Core ML input, then crop output depth back
// to this top-left ROI. Portrait photos must not be distorted into landscape.
struct DepthModelGeometry: Sendable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
    init?(sourceWidth: Int, sourceHeight: Int) {
        guard sourceWidth > 0, sourceHeight > 0, sourceWidth <= 16384, sourceHeight <= 16384 else { return nil }
        let scale = min(518 / Double(sourceWidth), 392 / Double(sourceHeight))
        width = min(518, Int((Double(sourceWidth) * scale).rounded(.down)))
        height = min(392, Int((Double(sourceHeight) * scale).rounded(.down)))
        guard width >= 3, height >= 3 else { return nil }
        x = (518 - width) / 2; y = (392 - height) / 2
    }
}
