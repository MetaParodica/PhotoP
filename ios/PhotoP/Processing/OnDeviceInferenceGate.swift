import Foundation

// A single synchronous owner for Vision/Core ML batches across composition,
// photo review and depth. Only analysis/processing executors may wait here.
enum OnDeviceInferenceGate {
    static let lock = NSLock()
}
