import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

enum AutoFocusDrive: String, Codable, CaseIterable, Identifiable, Sendable {
    case continuous, single
    var id: String { rawValue }
    var title: String { self == .continuous ? "AF-C" : "AF-S" }
}

enum MeteringScope: String, CaseIterable, Identifiable, Sendable {
    case both, focus, exposure
    var id: String { rawValue }
    var title: String {
        switch self { case .both: return "AF+AE"; case .focus: return "AF만"; case .exposure: return "AE만" }
    }
    var focuses: Bool { self != .exposure }
    var exposes: Bool { self != .focus }
}

enum FocusRange: String, Codable, CaseIterable, Identifiable, Sendable {
    case unrestricted, near, far
    var id: String { rawValue }
    var title: String {
        switch self { case .unrestricted: return "전체"; case .near: return "근거리"; case .far: return "원거리" }
    }
}

enum FocusArea: String, Codable, CaseIterable, Identifiable, Sendable {
    case point, small, large
    var id: String { rawValue }
    var title: String { self == .point ? "포인트" : self == .small ? "작은 영역" : "넓은 영역" }
    var size: Double { self == .point ? 0 : self == .small ? 0.12 : 0.32 }
    func rect(x: Double, y: Double, minimumWidth: Double, minimumHeight: Double) -> CGRect? {
        guard [x, y, minimumWidth, minimumHeight].allSatisfy(\.isFinite),
              (0...1).contains(x), (0...1).contains(y),
              (0...1).contains(minimumWidth), (0...1).contains(minimumHeight) else { return nil }
        let w = max(size, minimumWidth), h = max(size, minimumHeight)
        return CGRect(x: min(1 - w, max(0, x - w / 2)), y: min(1 - h, max(0, y - h / 2)), width: w, height: h)
    }
}

enum FocusPhase: String, Sendable {
    case idle, manual, locked, adjusting, settledEstimate, tracking, fixed
    var title: String {
        switch self {
        case .idle: return "AF 대기"; case .manual: return "MF"; case .fixed: return "고정 초점 렌즈"
        case .locked: return "AF 잠금"; case .adjusting: return "AF 조정 중"
        case .settledEstimate: return "AF 안정 추정"; case .tracking: return "피사체 추적 중"
        }
    }
    static func resolve(manual: Bool, locked: Bool, adjusting: Bool, tracking: Bool) -> Self {
        if manual { return .manual }; if tracking { return .tracking }
        if locked { return .locked }; return adjusting ? .adjusting : .settledEstimate
    }
}

// A tap is not AF-ON. Never silently override a user's MF/AF/AE lock.
enum FocusTouchPolicy {
    static func actions(scope: MeteringScope, focusSupported: Bool, exposureSupported: Bool,
                        focusLocked: Bool, exposureLocked: Bool, explicitAFOn: Bool) -> (focus: Bool, exposure: Bool) {
        (scope.focuses && focusSupported && (!focusLocked || explicitAFOn),
         scope.exposes && exposureSupported && !exposureLocked)
    }
}
