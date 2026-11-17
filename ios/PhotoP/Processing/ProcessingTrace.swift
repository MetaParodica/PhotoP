import os

// Instruments intervals only: no image content, persistent user logs or UI.
enum ProcessingTrace {
    private static let poster = OSSignposter(subsystem: "com.photop.camera", category: "Processing")
    static func begin(_ name: StaticString) -> OSSignpostIntervalState {
        poster.beginInterval(name, id: poster.makeSignpostID())
    }
    static func end(_ name: StaticString, _ state: OSSignpostIntervalState) { poster.endInterval(name, state) }
}
