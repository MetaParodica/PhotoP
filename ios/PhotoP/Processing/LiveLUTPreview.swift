@preconcurrency import AVFoundation
@preconcurrency import CoreVideo
import Metal
import QuartzCore

// Only the frame queue accesses processor/display. The lock protects UI/lifecycle state.
final class LiveLUTPreview: NSObject, @unchecked Sendable, AVCaptureVideoDataOutputSampleBufferDelegate {
    struct Event: Sendable {
        enum Kind: Sendable { case waiting, ready, failed(String) }
        let revision: UInt64
        let kind: Kind
    }
    let id = UUID()
    let device: MTLDevice
    let frameQueue = DispatchQueue(label: "com.photop.live-lut", qos: .userInteractive)
    private let commandQueue: MTLCommandQueue
    private let processor: LivePreviewImageProcessor
    private let display: MetalPreviewDisplay
    private let lock = NSLock()
    private var state = PreviewFrameState()
    private weak var layer: CAMetalLayer?
    private var intensity = 1.0
    private var announcedGeneration: UInt64?
    private var eventRevision: UInt64 = 0
    private let onEvent: @Sendable (UUID, Event) -> Void

    init(lut: CubeLUT, onEvent: @escaping @Sendable (UUID, Event) -> Void) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue()
        else { throw MetalLUTError.unavailable }
        self.device = device
        commandQueue = queue
        processor = try LivePreviewImageProcessor(lut: lut, device: device)
        display = try MetalPreviewDisplay(device: device)
        self.onEvent = onEvent
        super.init()
    }

    func attach(_ surface: CAMetalLayer) {
        let event = lock.withLock { () -> Event in
            layer = surface; state.invalidate(); announcedGeneration = nil
            return makeEvent(.waiting)
        }
        onEvent(id, event)
    }
    func detach(_ surface: CAMetalLayer) {
        let event: Event? = lock.withLock {
            guard layer === surface else { return nil }
            layer = nil; state.invalidate(); announcedGeneration = nil
            return makeEvent(.waiting)
        }
        if let event { onEvent(id, event) }
    }
    func setRunning(_ running: Bool) {
        let event: Event? = lock.withLock {
            state.setRunning(running); announcedGeneration = nil
            return running ? nil : makeEvent(.waiting)
        }
        if let event { onEvent(id, event) }
    }
    // MainActor deliveries from different queues can arrive in a different order.
    func isCurrentEvent(_ event: Event) -> Bool { lock.withLock { event.revision == eventRevision } }
    private func makeEvent(_ kind: Event.Kind) -> Event {
        eventRevision &+= 1
        return Event(revision: eventRevision, kind: kind)
    }
    func setIntensity(_ value: Double) {
        guard value.isFinite, (0...1).contains(value) else { return }
        lock.withLock { intensity = value }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        render(buffer)
    }

    // The capture delegate calls this only on frameQueue.
    private func render(_ buffer: CVPixelBuffer) {
        let request: (CAMetalLayer, PreviewFrameState.Ticket, Double)? = lock.withLock {
            guard let layer, layer.drawableSize.width > 0, layer.drawableSize.height > 0,
                  let ticket = state.begin() else { return nil }
            return (layer, ticket, intensity)
        }
        guard let (surface, ticket, strength) = request else { return }
        var submitted = false
        defer { if !submitted { _ = lock.withLock { state.complete(ticket) } } }
        autoreleasepool {
            guard let drawable = surface.nextDrawable(), let command = commandQueue.makeCommandBuffer() else { return }
            do {
                let image = try processor.encode(buffer, intensity: strength, command: command)
                try display.encode(image: image, destination: drawable.texture, command: command)
                command.present(drawable)
                command.addCompletedHandler { [self, buffer] completed in
                    // Retain the capture buffer until all CI and Metal reads finish.
                    withExtendedLifetime(buffer) {}
                    let event: Event? = lock.withLock {
                        guard state.complete(ticket) else { return nil }
                        if completed.status != .completed {
                            state.setRunning(false)
                            return makeEvent(.failed(completed.error?.localizedDescription ?? "GPU 프리뷰가 중단됐습니다."))
                        }
                        guard announcedGeneration != ticket.generation else { return nil }
                        announcedGeneration = ticket.generation
                        return makeEvent(.ready)
                    }
                    if let event { onEvent(id, event) }
                }
                submitted = true
                command.commit()
            } catch {
                let event: Event? = lock.withLock {
                    guard state.complete(ticket) else { return nil }
                    state.setRunning(false)
                    return makeEvent(.failed(error.localizedDescription))
                }
                if let event { onEvent(id, event) }
            }
        }
    }
}
