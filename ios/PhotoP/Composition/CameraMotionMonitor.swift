@preconcurrency import CoreMotion
import Foundation

@MainActor
final class CameraMotionMonitor {
    private let manager = CMMotionManager()
    private let queue = OperationQueue()
    private var generation = UUID()
    var orientation = "portrait"
    var onUpdate: ((CameraTilt?) -> Void)?
    var available: Bool { manager.isDeviceMotionAvailable }
    init() { queue.maxConcurrentOperationCount = 1; queue.qualityOfService = .utility }
    deinit { manager.stopDeviceMotionUpdates() }
    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        generation = UUID(); let token = generation
        manager.deviceMotionUpdateInterval = 0.25
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            let x = motion?.gravity.x, y = motion?.gravity.y, z = motion?.gravity.z
            let time = ProcessInfo.processInfo.systemUptime
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                guard let x, let y, let z else { self.onUpdate?(nil); return }
                self.onUpdate?(CameraTilt.measure(x: x, y: y, z: z, orientation: self.orientation, time: time))
            }
        }
    }
    func stop() { generation = UUID(); manager.stopDeviceMotionUpdates(); onUpdate?(nil) }
}
