@preconcurrency import AVFoundation
@preconcurrency import CoreVideo
import Metal
import QuartzCore

// Only the frame queue accesses processor/display. The lock protects UI/lifecycle state.
final class LiveLUTPreview: NSObject, @unchecked Sendable, AVCaptureVideoDataOutputSampleBufferDelegate {
    enum Event: Sendable { case waiting, ready, failed(String) }
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
        lock.withLock { layer = surface; state.invalidate(); announcedGeneration = nil }
        onEvent(id, .waiting)
    }
    func detach(_ surface: CAMetalLayer) {
        lock.withLock {
            if layer === surface { layer = nil; state.invalidate(); announcedGeneration = nil }
        }
    }
    func setRunning(_ running: Bool) {
        lock.withLock { state.setRunning(running); announcedGeneration = nil }
        if !running { onEvent(id, .waiting) }
    }
    func setIntensity(_ value: Double) {
        guard value.isFinite, (0...1).contains(value) else { return }
        lock.withLock { intensity = value }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        render(buffer)
    }

    // Also used by the synthetic-frame integration test; caller uses frameQueue.
    func render(_ buffer: CVPixelBuffer) {
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
                            return .failed(completed.error?.localizedDescription ?? "GPU 프리뷰가 중단됐습니다.")
                        }
                        guard announcedGeneration != ticket.generation else { return nil }
                        announcedGeneration = ticket.generation
                        return .ready
                    }
                    if let event { onEvent(id, event) }
                }
                submitted = true
                command.commit()
            } catch {
                let report = lock.withLock { () -> Bool in
                    guard state.complete(ticket) else { return false }
                    state.setRunning(false)
                    return true
                }
                if report { onEvent(id, .failed(error.localizedDescription)) }
            }
        }
    }
}
