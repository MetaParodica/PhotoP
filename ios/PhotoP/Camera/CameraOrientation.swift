import Foundation

enum CameraOrientation: String, Sendable {
    case portrait, landscapeLeft, landscapeRight
    var rotationAngle: CGFloat {
        switch self { case .portrait: return 90; case .landscapeLeft: return 180; case .landscapeRight: return 0 }
    }
    var imageSize: CGSize { self == .portrait ? CGSize(width: 3, height: 4) : CGSize(width: 4, height: 3) }
}

// One pending value bounds work while a device callback is in flight. Replacing it
// keeps the final slider position instead of dropping input or building a FIFO.
struct PendingCameraSettings {
    private(set) var value: CameraSettings?
    mutating func offer(_ settings: CameraSettings) { value = settings }
    mutating func take() -> CameraSettings? { defer { value = nil }; return value }
}

struct MeteringTarget {
    let id = UUID()
    let point: CGPoint
    let locked: Bool
}

struct CameraSettingsDelta {
    let exposure: Bool
    let focus: Bool
    let whiteBalance: Bool
    init(previous: CameraSettings?, next: CameraSettings) {
        exposure = previous?.exposure != next.exposure
        focus = previous?.focus != next.focus
        whiteBalance = previous?.whiteBalance != next.whiteBalance
    }
}
