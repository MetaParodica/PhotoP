@preconcurrency import Vision
@preconcurrency import CoreImage
@preconcurrency import CoreVideo
import Foundation

// Owned by one analysis executor. Coordinates at this boundary are top-left,
// matching delivered upright pixels and saved depth grids, not device AF points.
final class SubjectTrackingVisionEngine {
    private var sequence = VNSequenceRequestHandler()
    private var request: VNTrackObjectRequest?
    private var selectionID: UUID?
    private var epoch: UInt64?
    private var state = SubjectTrackingState()
    func reset() { sequence = VNSequenceRequestHandler(); request = nil; selectionID = nil; state = SubjectTrackingState() }
    func update(_ image: CIImage, selection: SubjectTrackingSelection, time: Double, generation: UInt64 = 0) throws -> SubjectTrackingSnapshot {
        state.configure(enabled: true, selection: selection, generation: generation)
        if selectionID != selection.id || epoch != generation {
            epoch = generation
            sequence = VNSequenceRequestHandler(); request = nil; selectionID = selection.id
            let region: CGRect
            switch selection.mode {
            case .object: region = selection.region
            case .person, .face:
                let detector: VNImageBasedRequest = selection.mode == .face ? VNDetectFaceRectanglesRequest() : VNDetectHumanRectanglesRequest()
                try VNImageRequestHandler(ciImage: image).perform([detector])
                let matches = (detector.results as? [VNDetectedObjectObservation] ?? []).map { Self.topLeft($0.boundingBox) }
                    .filter { $0.contains(selection.point) }.sorted { $0.width * $0.height < $1.width * $1.height }
                guard let detected = matches.first else {
                    _ = state.observe(bounds: nil, confidence: 0, time: time, generation: generation)
                    // Detection failed: do not silently switch to a nearby person.
                    selectionID = nil
                    return state.snapshot(at: time)
                }
                region = detected
            }
            request = VNTrackObjectRequest(detectedObjectObservation: VNDetectedObjectObservation(boundingBox: Self.topLeft(region)))
            request?.trackingLevel = .accurate
        }
        if let request {
            try sequence.perform([request], on: image)
            let result = request.results?.first as? VNDetectedObjectObservation
            _ = state.observe(bounds: result.map { Self.topLeft($0.boundingBox) }, confidence: result?.confidence ?? 0, time: time, generation: generation)
            if let result { request.inputObservation = result }
        }
        return state.snapshot(at: time)
    }
    static func topLeft(_ rect: CGRect) -> CGRect { CGRect(x: rect.minX, y: 1 - rect.maxY, width: rect.width, height: rect.height) }
}

private struct TrackingPixelOwner: @unchecked Sendable { let buffer: CVPixelBuffer }
final class SubjectTrackingAnalyzer: @unchecked Sendable {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.photop.subject-tracking", qos: .userInitiated)
    private let engine = SubjectTrackingVisionEngine()
    private var enabled = false
    private var selection: SubjectTrackingSelection?
    private var running = false
    private var generation: UInt64 = 0
    private var busy = false
    private var lastTime = -Double.infinity
    private var latest: SubjectTrackingSnapshot?
    func configure(enabled: Bool, selection: SubjectTrackingSelection?) {
        lock.withLock {
            if self.enabled != enabled || self.selection != selection { generation &+= 1; latest = nil }
            self.enabled = enabled; self.selection = selection
        }
    }
    func setRunning(_ running: Bool) { lock.withLock { if self.running != running { generation &+= 1; latest = nil }; self.running = running } }
    func invalidate() { lock.withLock { generation &+= 1; latest = nil } }
    var required: Bool { lock.withLock { enabled } }
    func current() -> SubjectTrackingSnapshot? { lock.withLock { latest } }
    func offer(_ buffer: CVPixelBuffer, interval: Double, completion: @escaping @Sendable (SubjectTrackingSnapshot) -> Void) {
        let time = ProcessInfo.processInfo.systemUptime
        let job = lock.withLock { () -> (UInt64, SubjectTrackingSelection)? in
            guard running, enabled, !busy, interval.isFinite, time - lastTime >= max(0.08, interval), let selection else { return nil }
            busy = true; lastTime = time; return (generation, selection)
        }
        guard let (epoch, selection) = job else { return }
        let owner = TrackingPixelOwner(buffer: buffer)
        queue.async { [self, owner] in
            defer { lock.withLock { busy = false } }
            let result: SubjectTrackingSnapshot = autoreleasepool {
                // tryLock: never wait behind a long offline movie job on this live queue.
                guard OnDeviceInferenceGate.lock.try() else { return .init(selectionID: selection.id, generation: epoch, phase: .uncertain, bounds: nil, confidence: 0, time: time) }
                defer { OnDeviceInferenceGate.lock.unlock() }
                do { return try engine.update(CIImage(cvPixelBuffer: owner.buffer), selection: selection, time: time, generation: epoch) }
                catch { return .init(selectionID: selection.id, generation: epoch, phase: .uncertain, bounds: nil, confidence: 0, time: time) }
            }
            let accepted = lock.withLock { () -> Bool in
                guard running, generation == epoch, self.selection?.id == selection.id else { return false }
                latest = result; return true
            }
            if accepted { completion(result) }
        }
    }
}
