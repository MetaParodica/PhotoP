import Foundation

enum CameraTool: String, CaseIterable, Identifiable, Sendable {
    case iso, shutter, ev, whiteBalance, focus, aperture, looks, guide, monitor, format, longExposure, video
    var id: String { rawValue }
    var title: String {
        switch self {
        case .iso: return "ISO"; case .shutter: return "셔터"; case .ev: return "노출 보정"
        case .whiteBalance: return "화이트밸런스"; case .focus: return "초점"; case .aperture: return "심도 · f값"
        case .looks: return "룩"; case .guide: return "구도"; case .monitor: return "노출 보조"
        case .format: return "촬영 포맷"; case .longExposure: return "장노출 시간"; case .video: return "영상 촬영"
        }
    }
    var symbol: String {
        switch self {
        case .iso: return "camera.aperture"; case .shutter: return "timer"; case .ev: return "plusminus"
        case .whiteBalance: return "thermometer.medium"; case .focus: return "viewfinder"; case .aperture: return "f.cursive"
        case .looks: return "camera.filters"; case .guide: return "square.split.2x2"; case .monitor: return "waveform.path"
        case .format: return "photo"; case .longExposure: return "timer"; case .video: return "video"
        }
    }
}

enum CaptureWorkflowPolicy {
    static let apertures: [Double] = [1.4, 2, 2.8, 4, 5.6, 8, 11, 16]
    static func controls(pro: Bool, long: Bool, video: Bool) -> [CameraTool] {
        if long && !video { return [.longExposure, .iso, .shutter, .ev, .whiteBalance, .focus] }
        if video { return [.iso, .shutter, .ev, .whiteBalance, .focus, .video] }
        return pro ? [.iso, .shutter, .ev, .whiteBalance, .focus, .aperture] : [.ev]
    }
    static func duration(from text: String) -> Double? {
        guard let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")),
              value.isFinite, (1...300).contains(value) else { return nil }
        return value
    }
    static func durationLabel(_ seconds: Double) -> String {
        guard seconds.isFinite, (1...300).contains(seconds) else { return "—" }
        return String(format: "%g s", seconds)
    }
    static func depthAllowed(pro: Bool, long: Bool, video: Bool, raw: Bool, bracket: Bool) -> Bool {
        pro && !long && !video && !raw && !bracket
    }
}

enum CaptureReviewRouting {
    static func original(for selected: URL, originals: [URL], renderedSources: [URL: URL]) -> URL? {
        let source = renderedSources[selected] ?? selected
        guard originals.contains(source), source.pathExtension.lowercased() != "dng" else { return nil }
        return source
    }
}

// A software blur-strength scale, NOT physical aperture simulation. The mask
// uses measured inverse depth and leaves invalid/uncertain pixels unblurred.
enum DepthBlurPolicy {
    static func focusDistance(_ samples: [Float]) -> Float? {
        let valid = samples.filter { $0.isFinite && (0.05...100).contains($0) }.sorted()
        guard valid.count >= 3 else { return nil }
        return valid[valid.count / 2]
    }
    static func mask(depth: Float, focus: Float) -> UInt8 {
        guard depth.isFinite, focus.isFinite, (0.05...100).contains(depth), (0.05...100).contains(focus) else { return 0 }
        let difference = abs(1 / depth - 1 / focus) / max(0.01, 1 / focus)
        return UInt8((min(1, max(0, (difference - 0.08) / 0.5)) * 255).rounded())
    }
    static func radius(aperture: Double, longEdge: Int) -> Double? {
        guard aperture.isFinite, (1.4...16).contains(aperture), longEdge > 0 else { return nil }
        return min(80, Double(longEdge) / 60) * pow(1.4 / aperture, 1.3)
    }
}
