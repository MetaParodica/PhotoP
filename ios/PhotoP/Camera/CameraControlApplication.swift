import Foundation

// Completion callbacks may arrive out of order, twice, or after interruption.
// An application ID keeps an old callback from completing a newer operation.
struct CameraControlApplication {
    enum Step: Hashable { case exposure, focus, whiteBalance }

    private(set) var id: UUID?
    private var pending: Set<Step> = []
    var isPending: Bool { id != nil }

    mutating func begin(steps: Set<Step>) throws -> UUID {
        guard !isPending else { throw CameraError.busy }
        precondition(!steps.isEmpty)
        let next = UUID()
        id = next
        pending = steps
        return next
    }

    mutating func acknowledge(_ step: Step, id: UUID) -> Bool {
        guard self.id == id, pending.remove(step) != nil else { return false }
        guard pending.isEmpty else { return false }
        self.id = nil
        return true
    }

    @discardableResult
    mutating func cancel(id: UUID? = nil) -> Bool {
        guard self.id != nil, id == nil || self.id == id else { return false }
        self.id = nil
        pending.removeAll()
        return true
    }
}
