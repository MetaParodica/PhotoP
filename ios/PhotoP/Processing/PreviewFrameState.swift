import Foundation

// The caller holds a lock. A GPU-owned frame remains in flight across resets.
struct PreviewFrameState {
    struct Ticket: Equatable {
        let id = UUID()
        let generation: UInt64
    }
    private(set) var running = false
    private(set) var generation: UInt64 = 0
    private var inFlight: Ticket?

    mutating func setRunning(_ value: Bool) {
        guard value != running else { return }
        running = value
        invalidate()
    }
    mutating func invalidate() { generation &+= 1 }
    mutating func begin() -> Ticket? {
        guard running, inFlight == nil else { return nil }
        let ticket = Ticket(generation: generation)
        inFlight = ticket
        return ticket
    }
    // False means resources were released, but this frame is stale or stopped.
    mutating func complete(_ ticket: Ticket) -> Bool {
        guard inFlight == ticket else { return false }
        inFlight = nil
        return running && ticket.generation == generation
    }
}
