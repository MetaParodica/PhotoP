@preconcurrency import AVFoundation
@preconcurrency import CoreVideo
import Metal
import QuartzCore

// Only the frame queue accesses processor/display. The lock protects UI/lifecycle state.
final class LiveLUTPreview: NSObject, @unchecked Sendable, AVCaptureVideoDataOutputSampleBufferDelegate {
    struct Event: Sendable {
        enum Kind: Sendable { case waiting, ready(PreviewHistogram?), failed(String) }
        let revision: UInt64
        let kind: Kind
    }
    let id = UUID()
    let device: MTLDevice
    let frameQueue = DispatchQueue(label: "com.photop.live-lut", qos: .userInteractive)
    private let commandQueue: MTLCommandQueue
    private var composition: CompositionAnalyzer!
    private let processor: LivePreviewImageProcessor
    private let display: MetalPreviewDisplay
    private let lock = NSLock()
    private var state = PreviewFrameState()
    private weak var layer: CAMetalLayer?
    private var imageSize: CGSize?
    var sourceImageSize: CGSize? { lock.withLock { imageSize } }
    private var intensity = 1.0
    private var grain = GrainSettings()
    private var effects = FilmFinishSettings()
    private var monitoring = MonitoringSettings()
    private var lastHistogramTime: TimeInterval = 0
    private var lastFrameTime = -Double.infinity
    private var announcedGeneration: UInt64?
    private var eventRevision: UInt64 = 0
    private let onEvent: @Sendable (UUID, Event) -> Void

    init(lut: CubeLUT, onGuide: @escaping @Sendable (UUID, CompositionSnapshot) -> Void = { _, _ in }, onEvent: @escaping @Sendable (UUID, Event) -> Void) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue()
        else { throw MetalLUTError.unavailable }
        self.device = device
        commandQueue = queue
        processor = try LivePreviewImageProcessor(lut: lut, device: device)
        display = try MetalPreviewDisplay(device: device)
        self.onEvent = onEvent
        super.init()
        composition = CompositionAnalyzer { [weak self] snapshot in guard let self else { return }; onGuide(self.id, snapshot) }
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
        composition.setRunning(running)
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
    func setIntensity(_ value: Double, grain settings: GrainSettings = GrainSettings(), effects finishing: FilmFinishSettings = FilmFinishSettings()) {
        guard value.isFinite, (0...1).contains(value) else { return }
        guard (try? settings.validate()) != nil else { return }
        guard (try? finishing.validate()) != nil else { return }
        lock.withLock { intensity = value; grain = settings; effects = finishing }
    }

    func setMonitoring(_ settings: MonitoringSettings) {
        guard (try? settings.validate()) != nil else { return }
        lock.withLock { monitoring = settings }
    }

    func setComposition(enabled: Bool, scene: GuideScene) { composition.configure(enabled: enabled, scene: scene) }
    func isCurrentComposition(_ snapshot: CompositionSnapshot) -> Bool { composition.isCurrent(snapshot) }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let budget = PreviewBudget(thermal: ProcessInfo.processInfo.thermalState, lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
        let now = ProcessInfo.processInfo.systemUptime
        guard budget.admits(time: now, after: lastFrameTime) else { return }
        lastFrameTime = now
        composition.offer(buffer, minimumInterval: budget.analysisInterval)
        render(buffer, budget: budget)
    }

    // The capture delegate calls this only on frameQueue.
    private func render(_ buffer: CVPixelBuffer, budget: PreviewBudget) {
        let request: (CAMetalLayer, PreviewFrameState.Ticket, Double, GrainSettings, FilmFinishSettings, MonitoringSettings)? = lock.withLock {
            guard let layer, layer.drawableSize.width > 0, layer.drawableSize.height > 0,
                  let ticket = state.begin() else { return nil }
            imageSize = CGSize(width: CGFloat(CVPixelBufferGetWidth(buffer)), height: CGFloat(CVPixelBufferGetHeight(buffer)))
            var sampleSettings = monitoring
            let now = ProcessInfo.processInfo.systemUptime
            if sampleSettings.histogram && now - lastHistogramTime >= budget.histogramInterval { lastHistogramTime = now }
            else { sampleSettings.histogram = false }
            return (layer, ticket, intensity, grain, effects, sampleSettings)
        }
        guard let (surface, ticket, strength, grainSettings, finishSettings, monitorSettings) = request else { return }
        var submitted = false
        defer { if !submitted { _ = lock.withLock { state.complete(ticket) } } }
        autoreleasepool {
            guard let drawable = surface.nextDrawable(), let command = commandQueue.makeCommandBuffer() else { return }
            do {
                let image = try processor.encode(buffer, intensity: strength, grain: grainSettings, effects: finishSettings, monitoring: monitorSettings, maximumDimension: budget.maximumDimension, command: command)
                try display.encode(image: image, destination: drawable.texture, command: command)
                command.present(drawable)
                command.addCompletedHandler { [self, buffer] completed in
                    // Retain the capture buffer until all CI and Metal reads finish.
                    withExtendedLifetime(buffer) {}
                    // Copy only 1 KiB of histogram counts before freeing this frame's resources.
                    let histogram = completed.status == .completed && monitorSettings.histogram ? processor.histogram() : nil
                    let event: Event? = lock.withLock {
                        guard state.complete(ticket) else { return nil }
                        if completed.status != .completed {
                            state.setRunning(false)
                            return makeEvent(.failed(completed.error?.localizedDescription ?? "GPU 프리뷰가 중단됐습니다."))
                        }
                        guard announcedGeneration != ticket.generation || histogram != nil else { return nil }
                        announcedGeneration = ticket.generation
                        return makeEvent(.ready(histogram))
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
