import Foundation

enum PhotoDepthPolicy {
    // Photo depth delivery does not require a continuously running AI preview.
    // The preview toggle remains available as an explicit user choice.
    static func startsAIPreview(source: SoftwareDepthSource, nativeAvailable: Bool) -> Bool {
        source == .ai || (source == .automatic && !nativeAvailable)
    }

    // Native observations, including holes, stay native. Automatic only falls
    // back to AI when the photo has no depth attachment at all.
    static func infersDepth(source: SoftwareDepthSource, nativePresent: Bool) -> Bool {
        source == .ai || (source == .automatic && !nativePresent)
    }
}

struct DepthPreviewWorkload: Equatable, Sendable {
    let maximumDimension: Int
    let framesPerSecond: Double
    let analysisInterval: Double
    let allowsDepth: Bool

    // ProcessInfo.ThermalState raw values; kept portable for the same policy's
    // Linux tests. Unknown pressure levels conservatively suspend depth work.
    init(thermalLevel: Int, lowPower: Bool) {
        switch thermalLevel {
        case 0, 1:
            maximumDimension = lowPower ? 480 : 720
            framesPerSecond = lowPower ? 20 : 30
            // Keep the offer interval below the live field's 0.75s expiry.
            // Throttling to 1s would periodically remove valid static bokeh.
            analysisInterval = 0.5
            allowsDepth = true
        case 2:
            maximumDimension = 480; framesPerSecond = 15
            analysisInterval = 0.5; allowsDepth = true
        default:
            maximumDimension = 480; framesPerSecond = 10
            analysisInterval = .infinity; allowsDepth = false
        }
    }
}

// A bounded summary for provenance/re-editing. The complete original depth
// attachment (including calibration) remains in the immutable source photo.
// Intrinsics below describe that attachment, not an arbitrarily resized grid.
struct NativeDepthMetadata: Codable, Equatable, Sendable {
    enum Quality: String, Codable, Sendable { case low, high, unknown }
    let mapWidth: Int
    let mapHeight: Int
    let quality: Quality
    let filtered: Bool
    let absoluteAccuracy: Bool
    let originalPixelFormat: UInt32
    let appliedEXIFOrientation: UInt32
    let hasCameraCalibration: Bool
    var intrinsicMatrix: [Float]? = nil // column-major, when available
    var intrinsicReferenceWidth: Double? = nil
    var intrinsicReferenceHeight: Double? = nil
    var geometry: DepthGeometry? = nil
    var refinement: NativeDepthRefinement? = nil

    var valid: Bool {
        guard (3...4096).contains(mapWidth), (3...4096).contains(mapHeight),
              mapWidth * mapHeight <= 2_097_152, (1...8).contains(appliedEXIFOrientation) else { return false }
        if let geometry {
            guard geometry.valid, geometry.orientation == appliedEXIFOrientation,
                  geometry.orientedDepthWidth == mapWidth, geometry.orientedDepthHeight == mapHeight else { return false }
        }
        if let refinement { guard refinement.valid else { return false } }
        if let matrix = intrinsicMatrix {
            guard hasCameraCalibration, matrix.count == 9, matrix.allSatisfy(\.isFinite),
                  let w = intrinsicReferenceWidth, let h = intrinsicReferenceHeight,
                  w.isFinite, h.isFinite, w > 0, h > 0, w <= 65536, h <= 65536 else { return false }
        } else if intrinsicReferenceWidth != nil || intrinsicReferenceHeight != nil { return false }
        return true
    }
}
