@preconcurrency import AVFoundation
@preconcurrency import CoreVideo
import Metal
import QuartzCore
import CoreImage

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
    private let depthAnalyzer = LiveDepthAnalyzer()
    private let subjectTracker = SubjectTrackingAnalyzer()
    private let onTracking: @Sendable (UUID, SubjectTrackingSnapshot) -> Void
    private var depthApplied = false
    private var announcedDepthError: String?
    private var depthSettings = LiveDepthSettings()
    var depthHasFrame: Bool { lock.withLock { depthApplied } }
    var depthError: String? { depthAnalyzer.errorDescription }
    private var processor: LivePreviewImageProcessor
    // Processor is encoded only on frameQueue. A completion retains the exact
    // immutable frame owner until its GPU/readback work has finished.
    private struct FrameOwner: @unchecked Sendable {
        let processor: LivePreviewImageProcessor
        // Retained immutable capture pixels, shared only for GPU reads.
        let buffer: CVPixelBuffer
    }
    private var lookGeneration = PreviewLookGeneration()
    private var pendingLUT: (version: UInt64, lut: CubeLUT)?
    private let display: MetalPreviewDisplay
    private let lock = NSLock()
    private var state = PreviewFrameState()
    private weak var layer: CAMetalLayer?
    private var imageSize: CGSize?
    var sourceImageSize: CGSize? { lock.withLock { imageSize } }
    var lookSettings: ProcessingLookSettings {
        lock.withLock { ProcessingLookSettings(intensity: intensity, grain: grain, finish: effects) }
    }
    private var intensity = 1.0
    private var grain = GrainSettings()
    private var effects = FilmFinishSettings()
    private var monitoring = MonitoringSettings()
    private var lastHistogramTime: TimeInterval = 0
    private var lastFrameTime = -Double.infinity
    private var announcedGeneration: UInt64?
    private var eventRevision: UInt64 = 0
    private let onEvent: @Sendable (UUID, Event) -> Void
    private let onSample: @Sendable (UUID, LookSceneSample) -> Void
    private let sampleContext = CIContext(options: [.cacheIntermediates: false])
    private var samplesWanted = false
    private var fillsViewfinder = false
    private var lastSampleTime = -Double.infinity
    private var latestSampleID: UUID?
    private var recordingBudget = false

    init(lut: CubeLUT, onTracking: @escaping @Sendable (UUID, SubjectTrackingSnapshot) -> Void = { _, _ in }, onSample: @escaping @Sendable (UUID, LookSceneSample) -> Void = { _, _ in }, onGuide: @escaping @Sendable (UUID, CompositionSnapshot) -> Void = { _, _ in }, onEvent: @escaping @Sendable (UUID, Event) -> Void) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue()
        else { throw MetalLUTError.unavailable }
        self.device = device
        commandQueue = queue
        processor = try LivePreviewImageProcessor(lut: lut, device: device)
        display = try MetalPreviewDisplay(device: device)
        self.onEvent = onEvent
        self.onSample = onSample
        self.onTracking = onTracking
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
        subjectTracker.setRunning(running)
        composition.setRunning(running)
        depthAnalyzer.setRunning(running)
        let event: Event? = lock.withLock {
            state.setRunning(running); announcedGeneration = nil
            return running ? nil : makeEvent(.waiting)
        }
        if let event { onEvent(id, event) }
    }
    func invalidateFrames() {
        lock.withLock { state.invalidate(); announcedGeneration = nil; imageSize = nil; latestSampleID = nil }
        composition.invalidate()
        depthAnalyzer.invalidate()
        subjectTracker.invalidate()
    }
    func setSubjectTracking(enabled: Bool, selection: SubjectTrackingSelection?) { subjectTracker.configure(enabled: enabled, selection: selection) }
    func setDepthPreview(_ settings: LiveDepthSettings) {
        depthAnalyzer.configure(settings)
        let event: Event? = lock.withLock {
            defer { depthSettings = settings }
            guard depthSettings.enabled != settings.enabled || depthSettings.comparingOriginal != settings.comparingOriginal else { return nil }
            depthApplied = false; state.invalidate(); announcedGeneration = nil
            return makeEvent(.waiting)
        }
        if let event { onEvent(id, event) }
    }
    func setSampleDelivery(_ enabled: Bool) { lock.withLock { samplesWanted = enabled; if !enabled { latestSampleID = nil } } }
    func isCurrentSample(_ id: UUID) -> Bool { lock.withLock { latestSampleID == id && samplesWanted && state.running } }
    func setViewfinderFill(_ fill: Bool) { lock.withLock { fillsViewfinder = fill } }
    func setRecordingBudget(_ active: Bool) { lock.withLock { recordingBudget = active } }
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
    func setLook(_ lut: CubeLUT, intensity value: Double, grain settings: GrainSettings, effects finishing: FilmFinishSettings) {
        guard value.isFinite, (0...1).contains(value), (try? settings.validate()) != nil, (try? finishing.validate()) != nil else { return }
        let event = lock.withLock { () -> Event in
            pendingLUT = (lookGeneration.request(), lut)
            intensity = value; grain = settings; effects = finishing
            state.invalidate(); announcedGeneration = nil
            return makeEvent(.waiting)
        }
        onEvent(id, event)
    }

    // Replace only GPU processing, not AVCaptureSession/device controls. Latest
    // request wins; no unbounded queue of complete LUT tables or preview frames.
    private func applyPendingLook() {
        let request = lock.withLock { () -> (version: UInt64, lut: CubeLUT)? in
            guard state.running else { return nil }
            defer { pendingLUT = nil }
            return pendingLUT
        }
        guard let request else { return }
        do {
            let next = try LivePreviewImageProcessor(lut: request.lut, device: device)
            lock.withLock {
                guard lookGeneration.install(request.version) else { return }
                processor = next
            }
        } catch {
            let event: Event? = lock.withLock {
                guard lookGeneration.requested == request.version else { return nil }
                state.setRunning(false); return makeEvent(.failed(error.localizedDescription))
            }
            if let event { onEvent(id, event) }
        }
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
        applyPendingLook()
        subjectTracker.offer(buffer, interval: min(0.15, budget.compositionInterval)) { [weak self] value in
            guard let self else { return }; onTracking(id, value)
        }
        depthAnalyzer.offer(buffer, minimumInterval: budget.compositionInterval)
        if lock.withLock({ samplesWanted }), now - lastSampleTime >= 1 {
            let generation = lock.withLock { state.generation }
            lastSampleTime = now
            autoreleasepool {
                guard let space = try? LivePreviewImageProcessor.inputColorSpace(buffer, negotiatedSRGB: true) else { return }
                let source = CIImage(cvPixelBuffer: buffer, options: [.colorSpace: space])
                let scale = min(1, 160 / max(source.extent.width, source.extent.height))
                let small = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                if let cg = sampleContext.createCGImage(small, from: small.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!),
                   let image = try? SDRImage.rasterize(cg) {
                    let sample = LookSceneSample(image: image)
                    let accepted = lock.withLock { () -> Bool in
                        guard samplesWanted, state.running, state.generation == generation else { return false }
                        latestSampleID = sample.id; return true
                    }
                    if accepted { onSample(id, sample) }
                }
            }
        }
        let interval = lock.withLock { recordingBudget ? max(0.4, budget.compositionInterval) : budget.compositionInterval }
        composition.offer(buffer, minimumInterval: interval)
        render(buffer, budget: budget)
    }

    // The capture delegate calls this only on frameQueue.
    private func render(_ buffer: CVPixelBuffer, budget: PreviewBudget) {
        let request: (CAMetalLayer, PreviewFrameState.Ticket, Double, GrainSettings, FilmFinishSettings, MonitoringSettings, Bool)? = lock.withLock {
            guard lookGeneration.ready, let layer, layer.drawableSize.width > 0, layer.drawableSize.height > 0,
                  let ticket = state.begin() else { return nil }
            imageSize = CGSize(width: CGFloat(CVPixelBufferGetWidth(buffer)), height: CGFloat(CVPixelBufferGetHeight(buffer)))
            var sampleSettings = monitoring
            let now = ProcessInfo.processInfo.systemUptime
            if sampleSettings.needsStatistics && now - lastHistogramTime >= budget.histogramInterval { lastHistogramTime = now }
            else { sampleSettings.disableStatistics() }
            return (layer, ticket, intensity, grain, effects, sampleSettings, fillsViewfinder)
        }
        guard let (surface, ticket, strength, grainSettings, finishSettings, monitorSettings, fill) = request else { return }
        var submitted = false
        let owner = FrameOwner(processor: processor, buffer: buffer)
        defer { if !submitted { _ = lock.withLock { state.complete(ticket) } } }
        autoreleasepool {
            guard let drawable = surface.nextDrawable(), let command = commandQueue.makeCommandBuffer() else { return }
            do {
                let source = CIImage(cvPixelBuffer: buffer)
                var depth = depthAnalyzer.current(for: source)
                if subjectTracker.required {
                    if let focus = subjectTracker.current()?.focus(at: ProcessInfo.processInfo.systemUptime), let frame = depth {
                        var settings = frame.settings; settings.focus = focus
                        // A matte for a previous location must not protect the wrong subject.
                        depth = .init(field: frame.field, matte: settings.focus == frame.settings.focus ? frame.matte : nil, settings: settings)
                    } else { depth = nil }
                }
                let image = try owner.processor.encode(buffer, intensity: strength, grain: grainSettings, effects: finishSettings, monitoring: monitorSettings, maximumDimension: budget.maximumDimension, command: command, depth: depth)
                try display.encode(image: image, destination: drawable.texture, command: command, fill: fill)
                command.present(drawable)
                command.addCompletedHandler { [self, owner] completed in
                    // Retain the capture buffer until all CI and Metal reads finish.
                    withExtendedLifetime(owner.buffer) {}
                    // Copy aggregate counters only (up to 81 KiB), never image pixels.
                    let histogram = completed.status == .completed && monitorSettings.needsStatistics ? owner.processor.histogram() : nil
                    let depthError = depthAnalyzer.errorDescription
                    let event: Event? = lock.withLock {
                        guard state.complete(ticket) else { return nil }
                        let previousDepth = depthApplied
                        depthApplied = depth != nil && completed.status == .completed
                        if completed.status != .completed {
                            state.setRunning(false)
                            return makeEvent(.failed(completed.error?.localizedDescription ?? "GPU 프리뷰가 중단됐습니다."))
                        }
                        guard announcedGeneration != ticket.generation || histogram != nil || previousDepth != depthApplied || announcedDepthError != depthError else { return nil }
                        announcedGeneration = ticket.generation
                        announcedDepthError = depthError
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
