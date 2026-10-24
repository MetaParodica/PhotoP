import Foundation

enum LiveLookPolicy {
    static func gradesFrame(selected: Bool, comparingOriginal: Bool) -> Bool { selected && !comparingOriginal }
    static func needsOutput(selected: Bool, monitoring: Bool, guide: Bool, focusAssist: Bool, samples: Bool) -> Bool {
        selected || monitoring || guide || focusAssist || samples
    }
}

// Caller owns synchronization. A late shader/table preparation must never
// publish an obsolete look or let it satisfy a newer selection's ready state.
struct PreviewLookGeneration {
    private(set) var requested: UInt64 = 0
    private(set) var installed: UInt64 = 0
    var ready: Bool { requested == installed }
    mutating func request() -> UInt64 { requested &+= 1; return requested }
    mutating func install(_ version: UInt64) -> Bool {
        guard version == requested else { return false }
        installed = version; return true
    }
}
