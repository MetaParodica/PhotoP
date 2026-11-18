import Foundation

/// Encoded SDR preview analysis, not sensor exposure or HDR/Log scopes.
enum ScopeAnalysisPolicy {
    static let side = 64
    static let histogramCount = 256
    static let waveformOffset = 256
    static let paradeOffset = 256 + 4096
    static let vectorscopeOffset = 256 + 4096 + 12288
    static let count = 256 + 4096 + 12288 + 4096
    static func chroma(red: Double, green: Double, blue: Double) -> (x: Int, y: Int)? {
        guard [red, green, blue].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return nil }
        let y = (54 * red + 183 * green + 19 * blue) / 256
        func bin(_ v: Double) -> Int { min(63, max(0, Int(min(1, max(0, v)) * 64 + 1e-5))) }
        return (bin((blue - y) / 1.8556 + 0.5), bin((red - y) / 1.5748 + 0.5))
    }
    static func falseColor(_ luma: Double) -> [UInt8] {
        switch luma {
        case ..<0.03: return [106, 53, 167]
        case ..<0.10: return [36, 95, 240]
        case ..<0.40: return [89, 89, 89]
        case ..<0.60: return [50, 176, 90]
        case ..<0.90: return [184, 184, 184]
        case ..<0.97: return [244, 207, 69]
        default: return [234, 68, 59]
        }
    }
}

struct PreviewScopeSamples: Sendable {
    let waveform: [UInt32]?
    let parade: [UInt32]?
    let vectorscope: [UInt32]?
}
