import Foundation

// Analysis-executor owned. Transient/unsupported optional inference must not
// recreate a failing Vision backend on every live frame.
struct InferenceRetryBackoff: Sendable {
    private(set) var failures = 0
    private(set) var retryAfter = -Double.infinity
    func canAttempt(at time: Double) -> Bool { time.isFinite && time >= retryAfter }
    mutating func failed(at time: Double) {
        guard time.isFinite else { return }
        failures = min(7, failures + 1)
        let delay = min(30, 0.5 * pow(2, Double(failures - 1)))
        retryAfter = time + delay
    }
    mutating func reset() { failures = 0; retryAfter = -Double.infinity }
}
