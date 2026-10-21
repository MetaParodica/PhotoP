import Foundation

struct CameraMeteringPoint: Sendable {
    let x: Double
    let y: Double
    init(x: Double, y: Double) throws {
        guard x.isFinite, y.isFinite, (0...1).contains(x), (0...1).contains(y)
        else { throw CameraError.invalidSettings }
        self.x = x
        self.y = y
    }
    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

struct PointMeteringActions: Equatable, Sendable {
    let focus: Bool
    let exposure: Bool
    var isEmpty: Bool { !focus && !exposure }
}

enum PointMeteringPolicy {
    static func actions(focusSupported: Bool, exposureSupported: Bool,
                        focusLocked: Bool, exposureLocked: Bool) -> PointMeteringActions {
        PointMeteringActions(focus: focusSupported && !focusLocked,
                             exposure: exposureSupported && !exposureLocked)
    }
}
