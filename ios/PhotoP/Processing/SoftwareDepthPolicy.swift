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
    init?(width: Int, height: Int, inverseDepth: [Float], units: Units) {
        guard width >= 3, height >= 3, width <= 4096, height <= 4096, width * height <= 2_097_152,
              width * height == inverseDepth.count, inverseDepth.contains(where: { $0.isFinite && $0 > 0 }) else { return nil }
        self.width = width; self.height = height; self.units = units
        self.inverseDepth = inverseDepth.map { $0.isFinite && $0 > 0 ? $0 : 0 }
    }
    func focusValue(x: Double, y: Double) -> Float? {
        guard x.isFinite, y.isFinite, (0...1).contains(x), (0...1).contains(y) else { return nil }
        let cx = min(width - 1, Int(x * Double(width))), cy = min(height - 1, Int(y * Double(height)))
        var values: [Float] = []
        for row in max(0, cy - 1)...min(height - 1, cy + 1) {
            for col in max(0, cx - 1)...min(width - 1, cx + 1) {
                let d = inverseDepth[row * width + col]; if d > 0 { values.append(d) }
            }
        }
        values.sort(); return values.count >= 3 ? values[values.count / 2] : nil
    }
    var bounds: (lower: Float, upper: Float)? {
        let valid = inverseDepth.filter { $0 > 0 }.sorted()
        guard valid.count >= 9 else { return nil }
        let lo = valid[Int(Double(valid.count - 1) * 0.02)]
        let hi = valid[Int(Double(valid.count - 1) * 0.98)]
        guard hi - lo > max(0.0001, abs(hi) * 0.001) else { return nil }
        return (lo, hi)
    }
}

enum SoftwareDepthPolicy {
    static let maximumPixels = 64_000_000
    static let modelID = "apple-depth-anything-v2-small-f16-cfef6f6"
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
                       aperture: Double, longEdge: Int) -> Double? {
        guard [inverse, focus, span, aperture].allSatisfy(\.isFinite), inverse > 0, focus > 0,
              span > 0, (1.4...16).contains(aperture), longEdge > 0 else { return nil }
        let value: Double
        if absolute {
            let distance = 1 / focus, focal = 0.05
            guard distance > focal else { return nil }
            value = focal * focal * distance / (aperture * (distance - focal)) * (focus - inverse) * Double(longEdge) / 0.036 / 2
        } else {
            value = (focus - inverse) / span * Double(longEdge) / 120 * (2.8 / aperture)
        }
        let limit = 48 * Double(longEdge) / 4032
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
