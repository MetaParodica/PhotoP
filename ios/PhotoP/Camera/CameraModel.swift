import AVFoundation
import SwiftUI

@MainActor
final class CameraModel: ObservableObject {
    @Published private(set) var snapshot = CameraSnapshot(lenses: [], selectedLens: nil, capabilities: nil,
                                                       state: .stopped, message: nil, revision: 0,
                                                       readout: nil, isApplyingSettings: false)
    @Published private(set) var latestVideo: VideoOriginal?
    @Published private(set) var videoSavedToPhotos = false
    @Published var settings = CameraSettings()
    @Published var rawMode: RawCaptureMode = .processed
    @Published var photoFormat: PhotoFileFormat = .jpeg
    @Published private(set) var busy = false
    @Published private(set) var latestOriginal: URL?
    @Published var longConfiguration = LongExposureConfiguration()
    @Published private(set) var longProgress: LongExposureProgress?
    @Published private(set) var latestComposite: URL?
    @Published private(set) var compositeSavedToPhotos = false
    @Published private(set) var latestOriginals: [URL] = []
    @Published var bracketEnabled = false
    @Published var bracketStep = 1.0
    @Published private(set) var savedToPhotos = false
    @Published var message: String?
    @Published var errorMessage: String?
    @Published var showGrid = true
    @Published var showControls = false
    @Published private(set) var livePreview: LiveLUTPreview?
    @Published private(set) var liveLUTTitle: String?
    @Published private(set) var liveHasFrame = false
    @Published private(set) var previewImageSize: CGSize?
    @Published var guideGrid: GuideGrid = .off
    @Published var guideScene: GuideScene = .general
    @Published var poseTemplate: PoseTemplate = .off
    @Published var guideOpacity = 0.6
    @Published var guideAIEnabled = false
    @Published private(set) var composition: CompositionSnapshot?
    @Published private(set) var aiComposition: LiveCompositionGuide?
    @Published var compositionTarget: CompositionTarget = .automatic
    @Published private(set) var compositionHapticID: UInt64 = 0
    private var compositionEngine = CompositionGuideEngine()
    private var lastCompositionHapticTime = -Double.infinity
    @Published var shootingIntent: ShootingIntent = .balanced
    @Published var intelligentRule: CompositionRule = .automatic
    @Published var cameraCoachEnabled = true
    @Published var photoReviewEnabled = true
    @Published var coachLearningEnabled = false
    @Published private(set) var cameraTilt: CameraTilt?
    @Published private(set) var cameraCoach: CameraCoachResult?
    @Published private(set) var photoReviews: [URL: PhotoReviewReport] = [:]
    @Published private(set) var photoReviewErrors: [URL: String] = [:]
    @Published private(set) var reviewingURL: URL?
    private var learning = CompositionLearning()
    private var coachStabilizer = CoachAdviceStabilizer()
    private var guideViewport = CGSize.zero
    private var compositionCaptureSuspended = false
    private var zoomAdviceSuppressedUntil = -Double.infinity
    private var reviewTask: Task<Void, Never>?
    private var reviewJobID = UUID()
    private var reviewReferences: [URL: CaptureGuideReference] = [:]
    private lazy var motionMonitor: CameraMotionMonitor = {
        let monitor = CameraMotionMonitor()
        monitor.onUpdate = { [weak self] value in self?.cameraTilt = value }
        return monitor
    }()
    @Published var monitoring = MonitoringSettings()
    @Published var focusAssistEnabled = true
    @Published private(set) var histogram: PreviewHistogram?
    @Published private(set) var liveUsesLUT = false
    @Published var liveIntensity = 1.0
    @Published var liveFinish = FilmFinishSettings()
    @Published var liveGrain = 0.0
    @Published var liveGrainSeed: UInt32 = 1
    @Published private(set) var liveCredit: String?
    @Published var photoResolution: PhotoResolution?
    @Published private(set) var latestPhotoResolution: PhotoResolution?
    @Published var liveCompareOriginal = false
    @Published var proMode = false
    @Published var flash: FlashSetting = .off
    @Published var selfTimer: SelfTimer = .off
    @Published var framing: FramingAspect = .native
    @Published var personGuide = PersonGuide()
    @Published var compositionPresetID: String?
    @Published private(set) var liveLookID: String?
    @Published private(set) var countdown: Int?
    @Published private(set) var latestThumbnail: PhotoThumbnailImage?
    @Published var longMode = false
    @Published private(set) var depthEnabled = false
    @Published var depthAperture = 2.8
    @Published private(set) var latestRendered: URL?
    @Published private(set) var latestRenderedSeries: [URL] = []
    private var depthReturnLens: String?
    private var depthFocusPoint = CGPoint(x: 0.5, y: 0.5)
    @Published private(set) var orientation: CameraOrientation = .portrait
    @Published private(set) var applyingSettings = false
    @Published private(set) var recordingRequested = false
    @Published private(set) var switchingMode = false
    @Published var videoPreviewFill = true
    @Published private(set) var sceneSample: LookSceneSample?
    @Published private(set) var installedLooks: [InstalledLook] = []
    @Published private(set) var lookInstallationError: String?
    private var pendingSettings = PendingCameraSettings()
    private var settingsTask: Task<Void, Never>?
    private var previewSamplesWanted = false
    private var active = false
    private var pendingVideo: VideoConfiguration?
    private var changingVideo = false
    private var changingLook = false
    private var lookRequestID = UUID()
    private var pendingLook: (token: UUID, id: String, load: @Sendable () async throws -> ImportedLUT)?
    @Published private(set) var requestedVideo: VideoConfiguration?
    @Published private(set) var meteringTarget: MeteringTarget?
    private var countdownTask: Task<Void, Never>?
    private var longJobID: UUID?
    private var longReprocessTask: Task<URL, Error>?
    private var importedLiveLUT: ImportedLUT?
    init() {
        coachLearningEnabled = UserDefaults.standard.bool(forKey: "coach.learning.enabled")
        if coachLearningEnabled, let data = UserDefaults.standard.data(forKey: "coach.learning.data"), data.count <= 64 * 1024,
           let saved = try? JSONDecoder().decode(CompositionLearning.self, from: data), saved.valid { learning = saved }
    }
    var longExposureRunning: Bool { longJobID != nil }
    private var liveLookForRestoration: ImportedLUT? {
        guard liveUsesLUT, var imported = importedLiveLUT else { return nil }
        imported.preset = ProcessingLookSettings(intensity: liveIntensity, grain: .init(amount: liveGrain, seed: liveGrainSeed), finish: liveFinish)
        return imported
    }

    private lazy var service = CameraService { [weak self] value in
        Task { @MainActor [weak self] in self?.receive(value) }
    }
    var previewSession: AVCaptureSession { service.session }
    var viewfinderFill: Bool { !snapshot.video.isVideoMode || videoPreviewFill }
    var coachMode: CoachCaptureMode {
        if snapshot.video.isVideoMode { return .video }
        if longMode { return .longExposure }
        if rawMode != .processed { return .raw }
        return proMode ? .pro : .photo
    }
    var motionAvailable: Bool { motionMonitor.available }
    var coachAvailability: String {
        if longExposureRunning { return "장노출 합성 중 분석 일시 중지 · 종료 후 복구" }
        if busy { return "촬영/처리 중 분석 대기" }
        if reviewingURL != nil { return "촬영 후 리뷰 분석 중 · 실시간 추론 잠시 대기" }
        if snapshot.state != .running { return "카메라 연결 후 실영상 분석" }
        if livePreview == nil { return snapshot.video.isVideoMode ? "이 영상 구성의 동시 분석 출력을 확인하세요. 해상도·FPS를 낮추거나 수동 가이드를 사용하세요." : "분석 프리뷰 대기 · 수동 촬영 가능" }
        return "최신 측정 프레임 대기 · 수동 촬영 가능"
    }
    var depthModeAllowed: Bool {
        CaptureWorkflowPolicy.depthAllowed(pro: proMode, long: longMode, video: snapshot.video.isVideoMode,
                                          raw: rawMode != .processed, bracket: bracketEnabled)
    }
    var rawUnavailableReason: String? {
        RawCapturePolicy.unavailableReason(mode: rawMode, available: snapshot.capabilities?.rawModes ?? [.processed],
                                          live: false,
                                          exposureMode: settings.exposure.manual ? .custom : (settings.exposure.locked ? .locked : .continuousAutoExposure))
            ?? ZoomPolicy.rawReason(zoom: snapshot.readout?.zoom ?? 1, raw: rawMode)
    }
    var bracketUnavailableReason: String? {
        guard bracketEnabled else { return nil }
        guard let caps = snapshot.capabilities,
              (try? ExposureBracketPlan.make(center: snapshot.readout?.exposureBias ?? settings.exposure.ev, step: bracketStep,
                    limits: caps.exposureBias, maximumCount: caps.maximumBracketCount, rawMode: rawMode, live: false,
                    exposureMode: settings.exposure.manual ? .custom : (settings.exposure.locked ? .locked : .continuousAutoExposure))) != nil
        else { return "브래킷은 지원 렌즈의 일반 사진·AUTO 노출에서 제공합니다. 촬영 동안 분석을 일시 중지합니다. EV와 간격은 장치 범위 안이어야 합니다." }
        return nil
    }
    var canCapture: Bool { !snapshot.video.isVideoMode && (!depthEnabled || depthModeAllowed && snapshot.capabilities?.depthDeliveryEnabled == true) && bracketUnavailableReason == nil && rawUnavailableReason == nil && snapshot.state == .running && !busy && !switchingMode && !applyingSettings && !snapshot.isApplyingSettings && (snapshot.capabilities?.photoFormats.contains(photoFormat) == true) }

    func setActive(_ active: Bool) {
        self.active = active
        updateMotion()
        if !active {
            cancelCountdown(); liveHasFrame = false; histogram = nil; resetComposition(); sceneSample = nil
            livePreview?.setSampleDelivery(false)
            Task { await LookThumbnailRenderer.shared.clear() }
        } else { livePreview?.setSampleDelivery(previewSamplesWanted) }
        service.setActive(active)
    }
    func selectLens(_ id: String) {
        guard !snapshot.video.isVideoMode, !busy, !applyingSettings, !snapshot.isApplyingSettings else { return }
        guard id != snapshot.selectedLens else { return }
        zoomAdviceSuppressedUntil = ProcessInfo.processInfo.systemUptime + 8; cameraCoach = nil
        let hadDepth = depthEnabled
        depthEnabled = false; depthReturnLens = nil
        let previous = liveLookForRestoration
        let restorationRequest = lookRequestID
        if livePreview != nil { tearDownLivePreview() }
        busy = true; meteringTarget = nil; sceneSample = nil
        Task {
            do {
                if hadDepth { await service.disablePhotoDepth() }
                try await service.selectLens(id)
                if let previous, restorationRequest == lookRequestID { try await activateLiveLUT(previous) }
            } catch { report(error) }
            busy = false
            await enableMonitoring()
        }
    }

    private func receive(_ value: CameraSnapshot) {
        guard value.revision > snapshot.revision else { return }
        let resetControls = value.selectedLens != snapshot.selectedLens || value.video.isVideoMode != snapshot.video.isVideoMode || value.video.configuration?.resolution != snapshot.video.configuration?.resolution
        let resuming = value.state == .running && snapshot.state != .running
        if resetControls || value.state != .running { resetComposition() }
        if resetControls, let caps = value.capabilities {
            pendingSettings = PendingCameraSettings()
            settings = CameraSettings()
            settings.exposure.iso = min(max(100, caps.iso.lowerBound), caps.iso.upperBound)
            settings.exposure.shutterSeconds = min(max(1.0 / 125, caps.shutterSeconds.lowerBound), caps.shutterSeconds.upperBound)
        }
        if let formats = value.capabilities?.photoFormats, !formats.contains(photoFormat), let first = formats.first {
            photoFormat = first
            message = "현재 렌즈에서 지원하지 않는 포맷이므로 \(first.title)로 전환했습니다."
        }
        if let modes = value.capabilities?.rawModes, !modes.contains(rawMode) { rawMode = .processed }
        if let requested = photoResolution, value.capabilities?.photoResolutions.contains(requested) != true {
            photoResolution = nil
            message = "해상도 요청이 현재 구성에서 지원되지 않아 최대 상한으로 복귀했습니다."
        }
        snapshot = value
        livePreview?.setRecordingBudget(value.video.phase.isActive)
        if let text = value.message { message = text; if active { errorMessage = text }; meteringTarget = nil }
        if resetControls || resuming { monitoringChanged() }
    }

    private func report(_ error: Error) {
        guard !(error is CancellationError) else { return }
        if !active, case CameraError.interrupted = error { return }
        message = error.localizedDescription; errorMessage = error.localizedDescription
    }

    func showMeteringTarget(_ point: CGPoint, locked: Bool) {
        let target = MeteringTarget(point: point, locked: locked)
        meteringTarget = target
        Task {
            try? await Task.sleep(nanoseconds: locked ? 3_000_000_000 : 2_000_000_000)
            guard meteringTarget?.id == target.id else { return }
            if !locked || snapshot.readout?.focusLocked != true && snapshot.readout?.exposureLocked != true { meteringTarget = nil }
        }
    }

    func suspendForDepth() async {
        setActive(false)
        await service.waitUntilStopped()
    }

    func validateDepthMode() {
        guard depthEnabled, !depthModeAllowed else { return }
        depthEnabled = false; depthReturnLens = nil
        Task { await service.disablePhotoDepth() }
    }

    func setDepthEnabled(_ enabled: Bool) async {
        guard !busy, !switchingMode, snapshot.state == .running, !recordingRequested else { return }
        guard !enabled || depthModeAllowed else { return }
        guard enabled != depthEnabled else { return }
        await settingsTask?.value
        guard !busy, !switchingMode, snapshot.state == .running, !enabled || depthModeAllowed else { return }
        busy = true
        let originalLens = snapshot.selectedLens
        let returnLens = depthReturnLens
        if livePreview != nil { tearDownLivePreview() }
        defer { busy = false; monitoringChanged() }
        do {
            if enabled {
                try await service.enablePhotoDepth()
                depthReturnLens = originalLens; depthEnabled = true
                // The new input may have different manual-control capabilities;
                // use the actual snapshot/readout rather than guessing support.
            } else {
                await service.disablePhotoDepth(); depthEnabled = false; depthReturnLens = nil
                if let returnLens { try await service.selectLens(returnLens) }
            }
        } catch {
            depthEnabled = false; depthReturnLens = nil
            await service.disablePhotoDepth()
            if let originalLens { try? await service.selectLens(originalLens) }
            report(error)
        }
    }

    func applySettings() async {
        requestSettings()
        await settingsTask?.value
    }

    func requestSettings() {
        guard !busy, snapshot.state == .running else { return }
        pendingSettings.offer(settings)
        updateMonitoring()
        guard settingsTask == nil else { return }
        applyingSettings = true
        settingsTask = Task { [weak self] in
            guard let self else { return }
            defer { self.settingsTask = nil; self.applyingSettings = false; self.monitoringChanged() }
            while !Task.isCancelled, let next = self.pendingSettings.take() {
                do {
                    while self.snapshot.isApplyingSettings {
                        try await Task.sleep(nanoseconds: 10_000_000)
                        guard self.snapshot.state == .running else { throw CameraError.interrupted }
                    }
                    _ = try await self.service.apply(next)
                } catch { self.message = error.localizedDescription; self.errorMessage = error.localizedDescription; self.pendingSettings = PendingCameraSettings(); break }
            }
        }
    }

    func setOrientation(_ value: CameraOrientation) {
        guard value != orientation else { return }
        orientation = value; sceneSample = nil; resetComposition(); meteringTarget = nil; previewImageSize = nil
        motionMonitor.orientation = value.rawValue; cameraTilt = nil
        depthFocusPoint = CGPoint(x: 0.5, y: 0.5)
        videoPreviewFill = value == .portrait
        service.setOrientation(value)
    }

    func focusAndMeter(_ point: CameraMeteringPoint, lensID: String, locked: Bool = false) async {
        guard snapshot.state == .running, !busy, !applyingSettings, !snapshot.isApplyingSettings else { return }
        do {
            let actions = try await service.focusAndMeter(at: point, lensID: lensID, locked: locked)
            if actions.focus { settings.focus.manual = false; settings.focus.locked = locked }
            if actions.exposure { settings.exposure.locked = locked }
            monitoringChanged()
        } catch { report(error) }
    }

    func importLiveLUT(_ url: URL) async {
        guard !snapshot.video.isVideoMode, !busy, !snapshot.isApplyingSettings else { return }
        busy = true
        defer { busy = false }
        do {
            let imported = try await Task.detached(priority: .userInitiated) { try ImportedLUT.read(url) }.value
            try await activateLiveLUT(imported)
        } catch { report(error) }
    }

    func useLiveLUT(_ imported: ImportedLUT) async throws {
        guard !snapshot.video.isVideoMode, !busy, !snapshot.isApplyingSettings else { throw CameraError.busy }
        busy = true
        defer { busy = false }
        try await activateLiveLUT(imported)
    }

    private func activateLiveLUT(_ imported: ImportedLUT) async throws {
        // Legacy live* property names now describe a selected CAPTURE look.
        // Choosing a LUT never creates/replaces the camera's analysis preview.
        let settings = imported.preset ?? ProcessingLookSettings()
        try settings.validate()
        liveIntensity = settings.intensity; liveGrain = settings.grain.amount
        liveGrainSeed = settings.grain.seed; liveFinish = settings.finish
        importedLiveLUT = imported
        let identifier = imported.provenance?.identifier
        liveLookID = FilmStyle.all.first(where: { identifier == "photop.\($0.id).v1" })?.id
            ?? ProceduralLook.all.first(where: { identifier == "photop.spatial.\($0.id).v1" })?.id
            ?? installedLooks.first(where: { identifier == $0.id })?.id
        liveLUTTitle = imported.displayName
        liveCredit = imported.provenance?.requiredCredit
        liveUsesLUT = true
        liveCompareOriginal = false
        updateLiveIntensity()
        message = "선택한 룩은 촬영 결과에만 적용합니다. 미리보기 없이 원본을 별도 보존합니다."
    }

    func favoriteLiveLUT() async {
        guard let importedLiveLUT else { return }
        do { try await LUTLibrary.shared.save(importedLiveLUT); message = "LUT 즐겨찾기에 저장했습니다." }
        catch { report(error) }
    }

    func saveLivePreset(name: String) async {
        guard let importedLiveLUT, liveUsesLUT else { return }
        do {
            let settings = ProcessingLookSettings(intensity: liveIntensity, grain: .init(amount: liveGrain, seed: liveGrainSeed), finish: liveFinish)
            try await FilterPresetLibrary.shared.save(importedLiveLUT, settings: settings, name: name)
            message = "전체 룩을 사용자 프리셋에 저장했습니다."
        } catch { report(error) }
    }

    func enableLiveLUT() async {
        guard !snapshot.video.isVideoMode, !busy, let importedLiveLUT else { return }
        do { try await activateLiveLUT(importedLiveLUT) } catch { report(error) }
    }

    var compositionPreset: CompositionPreset? { CompositionPreset.preset(compositionPresetID) }

    // Annotated presets replace the plain grid and silhouettes so only one guide is drawn.
    func selectCompositionPreset(_ id: String?) {
        compositionPresetID = id
        if id != nil { guideGrid = .off; showGrid = false; personGuide.framing = .off; poseTemplate = .off }
        if compositionPreset?.subject != nil { guideScene = .portrait; updateComposition() }
    }

    // Load only the selected capture look. No camera frame or thumbnail rendering.
    func selectLook(id: String, load: @escaping @Sendable () async throws -> ImportedLUT) async {
        guard !snapshot.video.isVideoMode else { return }
        lookRequestID = UUID()
        pendingLook = (lookRequestID, id, load)
        guard !changingLook else { return }
        changingLook = true
        defer { changingLook = false }
        requests: while let request = pendingLook {
            pendingLook = nil
            var ownsCamera = false
            do {
                let imported = try await request.load()
                guard request.token == lookRequestID else { continue }
                await settingsTask?.value
                while busy || applyingSettings || snapshot.isApplyingSettings || switchingMode {
                    guard request.token == lookRequestID else { continue requests }
                    try await Task.sleep(nanoseconds: 20_000_000)
                }
                guard request.token == lookRequestID, !snapshot.video.isVideoMode else { continue }
                busy = true
                ownsCamera = true
                try await activateLiveLUT(imported)
                if request.token == lookRequestID { liveLookID = request.id }
                busy = false
            } catch { if ownsCamera { busy = false }; if request.token == lookRequestID { report(error) } }
        }
    }

    func selectOriginalLook() async {
        guard !busy else { return }
        lookRequestID = UUID(); pendingLook = nil
        liveLookID = nil; liveUsesLUT = false; liveLUTTitle = nil; liveCredit = nil
        importedLiveLUT = nil
        updateLiveIntensity()
    }

    private func tearDownLivePreview() {
        livePreview?.setRunning(false)
        livePreview = nil
        liveHasFrame = false
        previewImageSize = nil
        histogram = nil
        resetComposition()
        service.removeLivePreview()
    }

    func disableLiveLUT() {
        livePreview?.setRunning(false)
        livePreview = nil
        liveHasFrame = false
        previewImageSize = nil
        histogram = nil
        monitoring = MonitoringSettings()
        focusAssistEnabled = false
        resetComposition()
        guideAIEnabled = false
        service.removeLivePreview()
    }

    func updateLiveIntensity() {
        // Monitoring/AI may still use Metal, but the camera image is ungraded.
        livePreview?.setIntensity(0)
    }

    func updateMonitoring() {
        livePreview?.setViewfinderFill(viewfinderFill)
        if !monitoring.histogram { histogram = nil }
        var effective = monitoring
        if settings.focus.manual && focusAssistEnabled { effective.peaking = true; if !monitoring.peaking { effective.peakingThreshold = 0.08 } }
        livePreview?.setMonitoring(effective)
    }

    private var needsAnalysis: Bool { monitoring.enabled || guideAIEnabled || settings.focus.manual && focusAssistEnabled || previewSamplesWanted }

    func monitoringChanged() {
        updateMonitoring()
        if needsAnalysis { Task { await enableMonitoring() } }
        else if livePreview != nil { tearDownLivePreview() }
    }

    func setPreviewSamplesWanted(_ wanted: Bool) {
        previewSamplesWanted = wanted
        livePreview?.setSampleDelivery(wanted)
        if !wanted { Task { await LookThumbnailRenderer.shared.clear() } }
        monitoringChanged()
    }

    func prepareInstalledLooks() async {
        lookInstallationError = nil
        do { installedLooks = try await InstalledLookCatalog.shared.install() }
        catch { lookInstallationError = error.localizedDescription }
    }

    func enableMonitoring() async {
        guard active, snapshot.state == .running, !busy, !applyingSettings, !switchingMode, !changingVideo, !snapshot.isApplyingSettings, needsAnalysis else { return }
        if livePreview != nil { updateMonitoring(); return }
        busy = true
        defer { busy = false }
        do {
            var lines = ["LUT_3D_SIZE 2"]
            for b in 0...1 { for g in 0...1 { for r in 0...1 { lines.append("\(r) \(g) \(b)") } } }
            let identity = try CubeLUT.parse(lines.joined(separator: "\n"))
            let preview = try await makeLivePreview(identity)
            preview.setIntensity(0)
            var effective = monitoring
            if settings.focus.manual && focusAssistEnabled { effective.peaking = true; if !monitoring.peaking { effective.peakingThreshold = 0.08 } }
            preview.setMonitoring(effective)
            preview.setComposition(enabled: guideAIEnabled, scene: guideScene)
            try await service.setLivePreview(preview)
            guard active, needsAnalysis else { preview.setRunning(false); service.removeLivePreview(); return }
            livePreview = preview
            liveHasFrame = false
            updateMonitoring(); updateComposition()
            message = "SDR 프리뷰 기준 보조 도구입니다. 원본에 표시를 굽지 않습니다."
        } catch { report(error) }
    }

    func updateComposition() {
        resetComposition()
        updateMotion()
        livePreview?.setComposition(enabled: guideAIEnabled && active && !compositionCaptureSuspended && reviewingURL == nil, scene: guideScene)
    }

    private func resetComposition() {
        composition = nil; aiComposition = nil; compositionEngine = CompositionGuideEngine()
        cameraCoach = nil; coachStabilizer = CoachAdviceStabilizer()
    }

    func compositionTargetChanged() { aiComposition = nil }

    func intelligentOptionsChanged() {
        aiComposition = nil; cameraCoach = nil; coachStabilizer = CoachAdviceStabilizer(); updateMotion()
    }
    private func updateMotion() {
        if active && guideAIEnabled && cameraCoachEnabled { motionMonitor.start() } else { motionMonitor.stop() }
    }
    func updateGuideViewport(_ size: CGSize) {
        guard size != guideViewport else { return }
        guideViewport = size; aiComposition = nil; cameraCoach = nil
    }
    private func guideRegion(_ size: CGSize) -> CGRect {
        var region = GuideGeometry.visibleRegion(image: size, viewport: guideViewport, fill: viewfinderFill)
        if !snapshot.video.isVideoMode, framing != .native {
            let box = framing.rect(in: CGRect(origin: .zero, size: size))
            let normalized = CGRect(x: box.minX / size.width, y: box.minY / size.height, width: box.width / size.width, height: box.height / size.height)
            region = region.intersection(normalized)
        }
        return region.isNull ? CGRect(x: 0, y: 0, width: 1, height: 1) : region
    }
    func learningChanged() {
        UserDefaults.standard.set(coachLearningEnabled, forKey: "coach.learning.enabled")
        if !coachLearningEnabled { resetCoachLearning() }
    }
    func resetCoachLearning() { learning = CompositionLearning(); UserDefaults.standard.removeObject(forKey: "coach.learning.data") }
    private func recordCoachPreference() {
        guard coachLearningEnabled, guideAIEnabled, intelligentRule != .automatic else { return }
        learning.record(intent: shootingIntent, rule: intelligentRule)
        if let data = try? JSONEncoder().encode(learning) { UserDefaults.standard.set(data, forKey: "coach.learning.data") }
    }
    private func coachContext() -> CoachCameraContext {
        let selected = snapshot.lenses.first { $0.id == snapshot.selectedLens }
        let lenses = snapshot.lenses.filter { $0.isFront == selected?.isFront && !$0.depthCamera }
        return CoachCameraContext(mode: coachMode, lensID: snapshot.selectedLens ?? "", zoom: snapshot.readout?.zoom ?? 1,
            maximumZoom: snapshot.capabilities?.maxZoom ?? 1, lensEquivalent: selected?.zoomEquivalent ?? 1,
            opticalLenses: depthEnabled ? [] : lenses.compactMap { lens in lens.zoomEquivalent.map { CoachLens(id: lens.id, equivalent: $0) } },
            exposureManual: settings.exposure.manual, exposureLocked: settings.exposure.locked || snapshot.readout?.exposureLocked == true,
            ev: snapshot.readout?.exposureBias ?? settings.exposure.ev, minimumEV: snapshot.capabilities?.exposureBias.lowerBound ?? 0,
            maximumEV: snapshot.capabilities?.exposureBias.upperBound ?? 0,
            zoomSuppressed: ProcessInfo.processInfo.systemUptime < zoomAdviceSuppressedUntil)
    }
    func applyCoachZoom() {
        guard !busy, !switchingMode, !applyingSettings, !snapshot.isApplyingSettings, snapshot.state == .running,
              let result = cameraCoach, result.isFresh(at: ProcessInfo.processInfo.systemUptime), result.lensID == snapshot.selectedLens,
              abs(result.baseZoom - (snapshot.readout?.zoom ?? 1)) < 0.02,
              let proposal = result.advice.compactMap(\.zoom).first else { return }
        cameraCoach = nil; zoomAdviceSuppressedUntil = ProcessInfo.processInfo.systemUptime + 8
        if let lens = proposal.lensID { selectLens(lens) } else { setZoom(proposal.factor) }
    }
    private func captureGuideReference() -> CaptureGuideReference? {
        guard let guide = aiComposition else { return nil }
        let mirrored = snapshot.lenses.first { $0.id == snapshot.selectedLens }?.isFront == true
        return CaptureGuideReference.make(guide: guide, intent: shootingIntent, mode: coachMode, mirrored: mirrored,
                                          tilt: cameraTilt, now: ProcessInfo.processInfo.systemUptime)
    }
    func requestPhotoReview(_ url: URL) {
        guard !busy, !snapshot.video.phase.isActive, photoReviews[url] == nil, reviewingURL != url else { return }
        reviewTask?.cancel(); reviewJobID = UUID(); let job = reviewJobID
        if photoReviewErrors.count >= 8 { photoReviewErrors.removeAll() }
        reviewingURL = url; photoReviewErrors[url] = nil
        // Share the Vision budget: still review must not compete with live
        // inference. Native preview/Metal monitoring continue unchanged.
        updateComposition()
        let reference = reviewReferences[url]
        reviewTask = Task { [weak self] in
            do {
                let worker = Task.detached(priority: .utility) { try await PhotoReviewService.shared.review(url, reference: reference) }
                let result = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                guard let self, !Task.isCancelled, self.reviewJobID == job else { return }
                if self.photoReviews.count >= 8 { self.photoReviews.removeAll() }
                self.photoReviews[url] = result; self.reviewingURL = nil; self.updateComposition()
            } catch {
                guard let self, self.reviewJobID == job else { return }
                self.reviewingURL = nil; self.photoReviewErrors[url] = error.localizedDescription; self.updateComposition()
            }
        }
    }
    func photoReviewSettingChanged() {
        if !photoReviewEnabled { pausePhotoReview() }
    }
    func pausePhotoReview() {
        let hadReview = reviewingURL != nil
        reviewTask?.cancel(); reviewJobID = UUID(); reviewingURL = nil
        if hadReview { updateComposition() }
    }
    func selectIntelligentRule(_ rule: CompositionRule) {
        compositionPresetID = nil; personGuide.framing = .off; poseTemplate = .off; guideGrid = .off
        intelligentRule = rule; guideAIEnabled = true; intelligentOptionsChanged()
    }

    func selectCompositionSubject(_ id: Int?) {
        compositionEngine.select(id)
        // Never leave the old target or completed status on screen after a tap.
        aiComposition = nil
    }

    func selectCompositionSubject(at imagePoint: CGPoint) {
        depthFocusPoint = imagePoint
        guard guideAIEnabled, let guide = aiComposition,
              guide.isFresh(at: ProcessInfo.processInfo.systemUptime),
              let id = CompositionSubjectTracker.subject(at: imagePoint, in: guide.subjects) else { return }
        selectCompositionSubject(id)
    }

    private func makeLivePreview(_ lut: CubeLUT) async throws -> LiveLUTPreview {
        let onEvent: @Sendable (UUID, LiveLUTPreview.Event) -> Void = { [weak self] id, event in
            Task { @MainActor [weak self] in
                guard let self, let preview = self.livePreview, preview.id == id, preview.isCurrentEvent(event) else { return }
                switch event.kind {
                case .waiting: self.liveHasFrame = false; self.histogram = nil
                case .ready(let histogram):
                    self.liveHasFrame = true
                    self.previewImageSize = preview.sourceImageSize
                    if self.monitoring.histogram, let histogram { self.histogram = histogram }
                case .failed(let reason):
                    // Keep the user's look/analysis choices so Retry can restore them.
                    self.tearDownLivePreview()
                    self.message = "프리뷰 입력 오류: \(reason)"
                    self.errorMessage = self.message
                }
            }
        }
        let onGuide: @Sendable (UUID, CompositionSnapshot) -> Void = { [weak self] id, snapshot in
            Task { @MainActor [weak self] in
                guard let self, self.active, !self.busy, self.snapshot.state == .running,
                      let preview = self.livePreview, preview.id == id, self.guideAIEnabled,
                      preview.isCurrentComposition(snapshot) else { return }
                self.composition = snapshot
                if let (guide, haptic) = self.compositionEngine.update(snapshot, target: self.compositionTarget,
                    now: ProcessInfo.processInfo.systemUptime, rule: self.intelligentRule, intent: self.shootingIntent,
                    mode: self.coachMode, region: self.guideRegion(CGSize(width: snapshot.width, height: snapshot.height)),
                    learning: self.coachLearningEnabled ? self.learning : CompositionLearning()) {
                    self.aiComposition = guide
                    let now = ProcessInfo.processInfo.systemUptime
                    if self.cameraCoachEnabled {
                        let context = self.coachContext()
                        let advice = CameraCoachEngine.evaluate(guide: guide, intent: self.shootingIntent, camera: context, tilt: self.cameraTilt, now: now)
                        let stable = self.coachStabilizer.update(advice, at: snapshot.generatedAt)
                        self.cameraCoach = CameraCoachResult(generatedAt: snapshot.generatedAt, lensID: context.lensID, baseZoom: context.zoom, advice: stable)
                    } else { self.cameraCoach = nil }
                    if haptic, self.liveHasFrame, now - self.lastCompositionHapticTime >= 3 {
                        self.lastCompositionHapticTime = now; self.compositionHapticID &+= 1
                    }
                }
            }
        }
        let onSample: @Sendable (UUID, LookSceneSample) -> Void = { [weak self] id, sample in
            Task { @MainActor [weak self] in
                guard let self, let preview = self.livePreview, preview.id == id, preview.isCurrentSample(sample.id), self.previewSamplesWanted else { return }
                self.sceneSample = sample
            }
        }
        let preview = try await Task.detached(priority: .userInitiated) { try LiveLUTPreview(lut: lut, onSample: onSample, onGuide: onGuide, onEvent: onEvent) }.value
        preview.setSampleDelivery(previewSamplesWanted)
        preview.setViewfinderFill(viewfinderFill)
        preview.setRecordingBudget(snapshot.video.phase.isActive)
        return preview
    }

    func captureLongExposure() async {
        guard canCapture, rawMode == .processed, !bracketEnabled else { message = "합성 전 RAW·브래킷을 꺼 주세요."; return }
        pausePhotoReview()
        let restoreLook = liveLookForRestoration
        let restorationRequest = lookRequestID
        let reference = captureGuideReference()
        if livePreview != nil { tearDownLivePreview() }
        busy = true; longProgress = nil
        let id = UUID(); longJobID = id
        var completed = false
        defer {
            busy = false; longJobID = nil
            if photoReviewEnabled, let url = latestComposite, completed { requestPhotoReview(url) }
            if completed, let progress = longProgress {
                longProgress = LongExposureProgress(fraction: 1, accepted: progress.accepted, rejected: progress.rejected, previewJPEG: progress.previewJPEG)
            }
            Task {
                guard active, snapshot.state == .running else { return }
                if let restoreLook, restorationRequest == lookRequestID { do { try await activateLiveLUT(restoreLook) } catch { report(error) } }
                if needsAnalysis { await enableMonitoring() }
            }
        }
        do {
            let url = try await service.captureLongExposure(longConfiguration) { [weak self] value in
                Task { @MainActor [weak self] in
                    guard let self, self.longJobID == id else { return }
                    self.longProgress = LongExposureProgress(fraction: value.fraction, accepted: value.accepted, rejected: value.rejected,
                                                            previewJPEG: value.previewJPEG ?? self.longProgress?.previewJPEG)
                }
            }
            latestComposite = url
            completed = true; compositeSavedToPhotos = false
            latestOriginal = url; latestOriginals = [url]; latestPhotoResolution = nil; savedToPhotos = false
            reviewReferences = [:]; reviewReferences[url] = reference
            recordCoachPreference()
            latestRendered = nil; latestRenderedSeries = []
            latestThumbnail = await Task.detached(priority: .utility) { PhotoThumbnail.make(url, maxPixel: 240) }.value
            message = "SDR 합성 결과와 재처리 프레임을 저장했습니다."
            await renderCaptureResults([url], look: restoreLook, aperture: nil, focus: CGPoint(x: 0.5, y: 0.5))
            try await PhotoStore.addToPhotos([url] + latestRenderedSeries); compositeSavedToPhotos = true; savedToPhotos = true
        } catch { report(error) }
    }
    func cancelLongExposure() { longReprocessTask?.cancel(); service.cancelLongExposure() }
    func reprocessLongExposure() async {
        guard !busy, let result = latestComposite else { return }
        busy = true
        let configuration = longConfiguration
        let task = Task { try await LongExposureArchive.reprocess(result, configuration: configuration) }
        longReprocessTask = task
        defer { busy = false; longReprocessTask = nil }
        do {
            let url = try await task.value
            latestComposite = url; compositeSavedToPhotos = false
            if latestOriginal == result {
                latestOriginal = url; latestOriginals = [url]; savedToPhotos = false
                latestRendered = nil; latestRenderedSeries = []
                latestThumbnail = await Task.detached(priority: .utility) { PhotoThumbnail.make(url, maxPixel: 240) }.value
            }
            message = "저장한 프레임으로 새 합성본을 만들었습니다."
        }
        catch { report(error) }
    }
    func saveCompositeToPhotos() async {
        guard !busy, let result = latestComposite, !compositeSavedToPhotos else { return }
        busy = true; defer { busy = false }
        do { try await PhotoStore.addToPhotos([result] + (latestOriginal == result ? latestRenderedSeries : [])); compositeSavedToPhotos = true; if latestOriginal == result { savedToPhotos = true } }
        catch { report(error) }
    }

    var canRecordVideo: Bool {
        snapshot.video.isVideoMode && snapshot.state == .running && !busy && !switchingMode && !changingVideo && !applyingSettings && !recordingRequested && !snapshot.isApplyingSettings
            && snapshot.video.phase == .idle
    }

    func setVideoMode(_ enabled: Bool, configuration: VideoConfiguration? = nil) async {
        guard !busy, !switchingMode else { return }
        if enabled, depthEnabled { await setDepthEnabled(false) }
        guard !busy, !switchingMode else { return }
        switchingMode = true
        defer { switchingMode = false; if !changingVideo { monitoringChanged() } }
        do {
            await settingsTask?.value
            while snapshot.isApplyingSettings {
                try await Task.sleep(nanoseconds: 10_000_000)
                guard snapshot.state == .running else { throw CameraError.interrupted }
            }
            if livePreview != nil { tearDownLivePreview() }
            sceneSample = nil
            longMode = false
            if enabled, configuration?.audio == true, !(await AVCaptureDevice.requestAccess(for: .audio)) {
                throw CameraError.microphonePermission
            }
            try await service.setVideoMode(enabled, configuration: configuration)
        } catch { report(error) }
    }

    func changeVideo(_ update: (inout VideoConfiguration) -> Void) {
        guard !recordingRequested, var value = requestedVideo ?? snapshot.video.configuration else { return }
        update(&value)
        requestedVideo = value; pendingVideo = value
        guard !changingVideo else { return }
        changingVideo = true
        Task {
            defer { changingVideo = false; requestedVideo = nil; monitoringChanged() }
            while let next = pendingVideo {
                pendingVideo = nil
                await setVideoMode(true, configuration: next)
            }
        }
    }

    func recordVideo() async {
        guard canRecordVideo, let configuration = snapshot.video.configuration else { return }
        pausePhotoReview()
        recordingRequested = true; defer { recordingRequested = false; busy = false }
        do {
            let pending = try await service.recordVideo()
            busy = true
            let original = try await VideoStore.finalize(pending, configuration: configuration)
            let sound = VideoCapturePolicy.audioLabel(configuration)
            latestVideo = original; videoSavedToPhotos = false
            message = "\(sound) SDR 영상 원본을 앱에 보관했습니다."
            try await VideoStore.addToPhotos(original.url)
            videoSavedToPhotos = true
            message = "\(sound) SDR 영상 원본과 사진 보관함에 저장했습니다."
        } catch { report(error) }
    }

    func stopVideo() { service.stopVideo() }

    func saveVideoToPhotos() async {
        guard !busy, !videoSavedToPhotos, let latestVideo else { return }
        busy = true; defer { busy = false }
        do { try await VideoStore.addToPhotos(latestVideo.url); videoSavedToPhotos = true }
        catch { report(error) }
    }

    var effectiveFlash: FlashSetting {
        PhotoFlashPolicy.resolve(flash, supported: snapshot.capabilities?.flashModes ?? [.off], raw: rawMode, bracket: bracketEnabled)
    }
    func cycleFlash() { flash = PhotoFlashPolicy.next(after: flash, supported: snapshot.capabilities?.flashModes ?? [.off]) }

    func setZoom(_ factor: Double) {
        resetComposition()
        zoomAdviceSuppressedUntil = ProcessInfo.processInfo.systemUptime + 8
        depthFocusPoint = CGPoint(x: 0.5, y: 0.5)
        service.setZoom(ZoomPolicy.clamp(factor, maxAvailable: snapshot.capabilities?.maxZoom ?? 1))
    }

    // Shutter entry point: runs the self-timer first. A second press during the countdown cancels it.
    func shutterPressed() {
        if countdownTask != nil { cancelCountdown(); return }
        guard canCapture else { return }
        guard selfTimer != .off else { Task { if longMode { await captureLongExposure() } else { await capture() } }; return }
        countdown = selfTimer.rawValue
        countdownTask = Task { [weak self] in
            guard let self else { return }
            while let remaining = self.countdown, remaining > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                self.countdown = remaining - 1
            }
            self.countdown = nil; self.countdownTask = nil
            await self.settingsTask?.value
            while self.snapshot.isApplyingSettings, self.active {
                try? await Task.sleep(nanoseconds: 10_000_000)
                guard !Task.isCancelled else { return }
            }
            guard self.active else { return }
            if self.longMode { await self.captureLongExposure() } else { await self.capture() }
        }
    }
    func cancelCountdown() {
        countdownTask?.cancel(); countdownTask = nil; countdown = nil
    }

    func capture() async {
        guard canCapture else { return }
        pausePhotoReview()
        let reference = captureGuideReference()
        var capturedReviewURL: URL?
        let look = rawMode == .processed ? liveLookForRestoration : nil
        let aperture = depthEnabled ? depthAperture : nil
        let front = snapshot.lenses.first { $0.id == snapshot.selectedLens }?.isFront == true
        let focus = CGPoint(x: front ? 1 - depthFocusPoint.x : depthFocusPoint.x, y: depthFocusPoint.y)
        busy = true
        compositionCaptureSuspended = true
        livePreview?.setComposition(enabled: false, scene: guideScene); cameraCoach = nil
        if (rawMode != .processed || bracketEnabled) && livePreview != nil { tearDownLivePreview() }
        defer {
            busy = false; compositionCaptureSuspended = false; updateComposition(); monitoringChanged()
            if photoReviewEnabled, let url = capturedReviewURL { requestPhotoReview(url) }
        }
        do {
            let series = try await service.captureSeries(format: photoFormat, rawMode: rawMode, bracketStep: bracketEnabled ? bracketStep : nil,
                resolution: rawMode == .processed && !bracketEnabled ? photoResolution : nil, flash: effectiveFlash, depth: aperture != nil)
            latestPhotoResolution = series.photos.first?.pixelDimensions
            let urls = try await CaptureSeriesStore.preserve(series)
            latestOriginals = urls
            latestOriginal = urls[urls.count / 2]
            capturedReviewURL = latestOriginal
            reviewReferences = [:]
            for url in urls { reviewReferences[url] = reference }
            recordCoachPreference()
            latestRendered = nil; latestRenderedSeries = []
            let center = urls[urls.count / 2]
            latestThumbnail = await Task.detached(priority: .utility) { PhotoThumbnail.make(center, maxPixel: 240) }.value
            savedToPhotos = false
            await renderCaptureResults(urls, look: look, aperture: aperture, focus: focus)
            try await PhotoStore.addToPhotos(urls + latestRenderedSeries)
            savedToPhotos = true
            message = "원본 \(urls.count)장과 사진 보관함에 저장했습니다."
        } catch { report(error) }
    }

    private func renderCaptureResults(_ urls: [URL], look: ImportedLUT?, aperture: Double?, focus: CGPoint) async {
        guard look != nil || aperture != nil else { return }
        for (index, url) in urls.enumerated() {
            do {
                let rendered = try await CaptureResultProcessor.shared.render(original: url, look: look, aperture: aperture, focus: focus)
                latestRenderedSeries.append(rendered)
                reviewReferences[rendered] = reviewReferences[url]
                if index == urls.count / 2 {
                    latestRendered = rendered
                    latestThumbnail = await Task.detached(priority: .utility) { PhotoThumbnail.make(rendered, maxPixel: 240) }.value
                }
            } catch {
                report(ImageEditingError.invalid("원본은 보존했습니다. 효과 결과 처리 실패: \(error.localizedDescription)"))
            }
        }
    }

    func saveLatestToPhotos() async {
        guard !busy, !savedToPhotos, let latestOriginal else { return }
        busy = true
        defer { busy = false }
        do {
            try await PhotoStore.addToPhotos((latestOriginals.isEmpty ? [latestOriginal] : latestOriginals) + latestRenderedSeries)
            savedToPhotos = true
            message = "사진 보관함에 저장했습니다."
        } catch { report(error) }
    }
}
