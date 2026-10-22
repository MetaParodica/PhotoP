import CoreGraphics
import Foundation

enum FlashSetting: String, CaseIterable, Identifiable, Sendable {
    case off, auto, on
    var id: String { rawValue }
    var title: String { switch self { case .off: return "플래시 끔"; case .auto: return "플래시 자동"; case .on: return "플래시 켬" } }
    var symbol: String { switch self { case .off: return "bolt.slash"; case .auto: return "bolt.badge.automatic"; case .on: return "bolt.fill" } }
}

enum PhotoFlashPolicy {
    // Bracketed and RAW captures are requested without flash. Unsupported modes fall back to off.
    static func resolve(_ requested: FlashSetting, supported: [FlashSetting], raw: RawCaptureMode, bracket: Bool) -> FlashSetting {
        guard raw == .processed, !bracket, supported.contains(requested) else { return .off }
        return requested
    }
    static func next(after current: FlashSetting, supported: [FlashSetting]) -> FlashSetting {
        let order = FlashSetting.allCases.filter { $0 == .off || supported.contains($0) }
        guard let index = order.firstIndex(of: current) else { return .off }
        return order[(index + 1) % order.count]
    }
}

enum SelfTimer: Int, CaseIterable, Identifiable, Sendable {
    case off = 0, three = 3, ten = 10
    var id: Int { rawValue }
    var title: String { self == .off ? "타이머 끔" : "\(rawValue)초 타이머" }
    var next: SelfTimer { switch self { case .off: return .three; case .three: return .ten; case .ten: return .off } }
}

// A framing guide drawn over the native 3:4 preview. The saved original keeps the sensor aspect.
enum FramingAspect: String, CaseIterable, Identifiable, Sendable {
    case native, square, wide
    var id: String { rawValue }
    var title: String { switch self { case .native: return "4:3"; case .square: return "1:1"; case .wide: return "16:9" } }
    // Portrait width / height.
    var ratio: CGFloat { switch self { case .native: return 3 / 4; case .square: return 1; case .wide: return 9 / 16 } }
    var next: FramingAspect { switch self { case .native: return .square; case .square: return .wide; case .wide: return .native } }
    // Largest centered rect of this aspect inside the image rect.
    func rect(in image: CGRect) -> CGRect {
        guard image.width > 0, image.height > 0 else { return .zero }
        let targetRatio = image.width > image.height ? 1 / ratio : ratio
        var size = CGSize(width: image.width, height: image.width / targetRatio)
        if size.height > image.height { size = CGSize(width: image.height * targetRatio, height: image.height) }
        return CGRect(x: image.midX - size.width / 2, y: image.midY - size.height / 2, width: size.width, height: size.height)
    }
}

enum ZoomPolicy {
    // Digital zoom is capped well below the device maximum to avoid presenting heavy upscaling as a lens.
    static let digitalCeiling = 5.0
    static func range(maxAvailable: Double) -> ClosedRange<Double> {
        1...max(1, min(maxAvailable.isFinite ? maxAvailable : 1, digitalCeiling))
    }
    static func clamp(_ factor: Double, maxAvailable: Double) -> Double {
        let limits = range(maxAvailable: maxAvailable)
        return factor.isFinite ? min(max(factor, limits.lowerBound), limits.upperBound) : 1
    }
    // Equivalent magnification relative to the back wide lens, from horizontal field of view in degrees.
    static func equivalent(fieldOfView: Double, wideFieldOfView: Double) -> Double? {
        guard fieldOfView > 0, fieldOfView < 180, wideFieldOfView > 0, wideFieldOfView < 180 else { return nil }
        let value = tan(wideFieldOfView * .pi / 360) / tan(fieldOfView * .pi / 360)
        guard value.isFinite, value > 0 else { return nil }
        // Snap to one decimal so 0.49/0.51 both read as the familiar lens label.
        return (value * 10).rounded() / 10
    }
    static func label(_ factor: Double) -> String {
        let rounded = (factor * 10).rounded() / 10
        return rounded == rounded.rounded() ? "\(Int(rounded))×" : String(format: "%.1f×", rounded)
    }
    static func rawReason(zoom: Double, raw: RawCaptureMode) -> String? {
        raw != .processed && zoom > 1.01 ? "RAW는 디지털 줌을 적용하지 않습니다. 1×로 돌아가거나 일반 사진을 선택해 주세요." : nil
    }
}
