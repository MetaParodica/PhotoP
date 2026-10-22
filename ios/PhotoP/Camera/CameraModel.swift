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
    var rawUnavailableReason: String? {
        RawCapturePolicy.unavailableReason(mode: rawMode, available: snapshot.capabilities?.rawModes ?? [.processed],
                                          live: livePreview != nil,
                                          exposureMode: settings.exposure.manual ? .custom : (settings.exposure.locked ? .locked : .continuousAutoExposure))
            ?? ZoomPolicy.rawReason(zoom: snapshot.readout?.zoom ?? 1, raw: rawMode)
    }
    var bracketUnavailableReason: String? {
        guard bracketEnabled else { return nil }
        guard let caps = snapshot.capabilities,
              (try? ExposureBracketPlan.make(center: snapshot.readout?.exposureBias ?? settings.exposure.ev, step: bracketStep,
                    limits: caps.exposureBias, maximumCount: caps.maximumBracketCount, rawMode: rawMode, live: livePreview != nil,
                    exposureMode: settings.exposure.manual ? .custom : (settings.exposure.locked ? .locked : .continuousAutoExposure))) != nil
        else { return "브래킷은 지원 렌즈의 일반 사진·AUTO 노출·모니터 끔에서 제공합니다. EV 중심값과 간격도 장치 범위 안이어야 합니다." }
        return nil
    }
    var canCapture: Bool { !snapshot.video.isVideoMode && bracketUnavailableReason == nil && rawUnavailableReason == nil && snapshot.state == .running && !busy && !switchingMode && !applyingSettings && !snapshot.isApplyingSettings && (snapshot.capabilities?.photoFormats.contains(photoFormat) == true) }

    func setActive(_ active: Bool) {
        self.active = active
        if !active {
            cancelCountdown(); liveHasFrame = false; histogram = nil; composition = nil; sceneSample = nil
            livePreview?.setSampleDelivery(false)
            Task { await LookThumbnailRenderer.shared.clear() }
        } else { livePreview?.setSampleDelivery(previewSamplesWanted) }
        service.setActive(active)
    }
    func selectLens(_ id: String) {
        guard !snapshot.video.isVideoMode, !busy, !applyingSettings, !snapshot.isApplyingSettings else { return }
        guard id != snapshot.selectedLens else { return }
        let previous = liveLookForRestoration
        let restorationRequest = lookRequestID
        if livePreview != nil { tearDownLivePreview() }
        busy = true; meteringTarget = nil; sceneSample = nil
        Task {
            do {
                try await service.selectLens(id)
                if let previous, restorationRequest == lookRequestID { try await activateLiveLUT(previous) }
            } catch { report(error) }
            busy = false
            if previous == nil || restorationRequest != lookRequestID { await enableMonitoring() }
        }
    }

    private func receive(_ value: CameraSnapshot) {
        guard value.revision > snapshot.revision else { return }
        let resetControls = value.selectedLens != snapshot.selectedLens || value.video.isVideoMode != snapshot.video.isVideoMode || value.video.configuration?.resolution != snapshot.video.configuration?.resolution
        let resuming = value.state == .running && snapshot.state != .running
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
        orientation = value; sceneSample = nil; composition = nil; meteringTarget = nil; previewImageSize = nil
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
        guard !snapshot.video.isVideoMode, !busy, !snapshot.isApplyingSettings, livePreview == nil else { return }
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
        if livePreview != nil { tearDownLivePreview() }
        try await activateLiveLUT(imported)
    }

    private func activateLiveLUT(_ imported: ImportedLUT) async throws {
        let preview = try await makeLivePreview(imported.lut)
        try await service.setLivePreview(preview)
        if let settings = imported.preset {
            liveIntensity = settings.intensity
            liveGrain = settings.grain.amount
            liveGrainSeed = settings.grain.seed
            liveFinish = settings.finish
        }
        importedLiveLUT = imported
        let identifier = imported.provenance?.identifier
        liveLookID = FilmStyle.all.first(where: { identifier == "photop.\($0.id).v1" })?.id
            ?? ProceduralLook.all.first(where: { identifier == "photop.spatial.\($0.id).v1" })?.id
            ?? installedLooks.first(where: { identifier == $0.id })?.id
        liveLUTTitle = imported.displayName
        liveCredit = imported.provenance?.requiredCredit
        liveUsesLUT = true
        liveCompareOriginal = false
        liveHasFrame = false
        livePreview = preview
        updateLiveIntensity()
        updateMonitoring()
        updateComposition()
        message = "LUT는 미리보기에만 적용합니다. 촬영 사진은 원본 색상으로 저장합니다."
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
        guard !snapshot.video.isVideoMode, !busy, !snapshot.isApplyingSettings, livePreview == nil, let importedLiveLUT else { return }
        busy = true
        defer { busy = false }
        do {
            let preview = try await makeLivePreview(importedLiveLUT.lut)
            try await service.setLivePreview(preview)
            liveHasFrame = false
            livePreview = preview
            liveUsesLUT = true
            updateLiveIntensity()
            updateMonitoring()
            updateComposition()
        } catch { report(error) }
    }

    var compositionPreset: CompositionPreset? { CompositionPreset.preset(compositionPresetID) }

    // Annotated presets replace the plain grid and silhouettes so only one guide is drawn.
    func selectCompositionPreset(_ id: String?) {
        compositionPresetID = id
        if id != nil { guideGrid = .off; showGrid = false; personGuide.framing = .off; poseTemplate = .off }
        if compositionPreset?.subject != nil { guideScene = .portrait; updateComposition() }
    }

    // Carousel selection: swap the preview look while keeping monitoring and AI guide settings.
    func selectLook(id: String, load: @escaping @Sendable () async throws -> ImportedLUT) async {
        guard !snapshot.video.isVideoMode, snapshot.state == .running else { return }
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
                    guard request.token == lookRequestID, active, snapshot.state == .running else { continue requests }
                    try await Task.sleep(nanoseconds: 20_000_000)
                }
                guard request.token == lookRequestID, active, !snapshot.video.isVideoMode, snapshot.state == .running else { continue }
                busy = true
                ownsCamera = true
                if livePreview != nil { tearDownLivePreview() }
                try await activateLiveLUT(imported)
                if request.token == lookRequestID { liveLookID = request.id }
                else { tearDownLivePreview(); liveLookID = nil }
                busy = false
                if request.token != lookRequestID, pendingLook == nil { await enableMonitoring() }
            } catch { if ownsCamera { busy = false }; if request.token == lookRequestID { report(error) } }
        }
    }

    func selectOriginalLook() async {
        lookRequestID = UUID(); pendingLook = nil
        liveLookID = nil
        guard !busy else { return }
        guard liveUsesLUT else { liveLookID = nil; return }
        let keepAnalysis = needsAnalysis
        tearDownLivePreview()
        liveLookID = nil
        if keepAnalysis { await enableMonitoring() }
    }

    private func tearDownLivePreview() {
        livePreview?.setRunning(false)
        livePreview = nil
        liveHasFrame = false
        liveUsesLUT = false
        liveLUTTitle = nil
        liveCredit = nil
        previewImageSize = nil
        histogram = nil
        composition = nil
        service.removeLivePreview()
    }

    func disableLiveLUT() {
        liveLookID = nil
        livePreview?.setRunning(false)
        livePreview = nil
        liveHasFrame = false
        liveUsesLUT = false
        previewImageSize = nil
        histogram = nil
        monitoring = MonitoringSettings()
        focusAssistEnabled = false
        composition = nil
        guideAIEnabled = false
        service.removeLivePreview()
    }

    func updateLiveIntensity() {
        livePreview?.setIntensity(!liveUsesLUT || liveCompareOriginal ? 0 : liveIntensity, grain: GrainSettings(amount: !liveUsesLUT || liveCompareOriginal ? 0 : liveGrain, seed: liveGrainSeed), effects: !liveUsesLUT || liveCompareOriginal ? FilmFinishSettings() : liveFinish)
    }

    func updateMonitoring() {
        if !monitoring.histogram { histogram = nil }
        var effective = monitoring
        if settings.focus.manual && focusAssistEnabled { effective.peaking = true; if !monitoring.peaking { effective.peakingThreshold = 0.08 } }
        livePreview?.setMonitoring(effective)
    }

    private var needsAnalysis: Bool { monitoring.enabled || guideAIEnabled || settings.focus.manual && focusAssistEnabled || previewSamplesWanted }

    func monitoringChanged() {
        updateMonitoring()
        if needsAnalysis { Task { await enableMonitoring() } }
        else if livePreview != nil && !liveUsesLUT { tearDownLivePreview() }
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
            liveUsesLUT = false
            updateMonitoring(); updateComposition()
            message = "SDR 프리뷰 기준 보조 도구입니다. 원본에 표시를 굽지 않습니다."
        } catch { report(error) }
    }

    func updateComposition() {
        composition = nil
        livePreview?.setComposition(enabled: guideAIEnabled, scene: guideScene)
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
                guard let self, let preview = self.livePreview, preview.id == id, self.guideAIEnabled,
                      preview.isCurrentComposition(snapshot) else { return }
                self.composition = snapshot
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
        preview.setViewfinderFill(snapshot.video.isVideoMode && videoPreviewFill)
        return preview
    }

    func captureLongExposure() async {
        guard canCapture, rawMode == .processed, !bracketEnabled else { message = "합성 전 RAW·브래킷을 꺼 주세요."; return }
        let restoreLook = liveLookForRestoration
        let restorationRequest = lookRequestID
        if livePreview != nil { tearDownLivePreview() }
        busy = true; longProgress = nil
        let id = UUID(); longJobID = id
        var completed = false
        defer {
            busy = false; longJobID = nil
            if completed, let progress = longProgress {
                longProgress = LongExposureProgress(fraction: 1, accepted: progress.accepted, rejected: progress.rejected, previewJPEG: progress.previewJPEG)
            }
            Task {
                guard active, snapshot.state == .running else { return }
                if let restoreLook, restorationRequest == lookRequestID { do { try await activateLiveLUT(restoreLook) } catch { report(error) } }
                else if needsAnalysis { await enableMonitoring() }
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
            latestThumbnail = await Task.detached(priority: .utility) { PhotoThumbnail.make(url, maxPixel: 240) }.value
            message = "SDR 합성 결과와 재처리 프레임을 저장했습니다."
            try await PhotoStore.addToPhotos(url); compositeSavedToPhotos = true; savedToPhotos = true
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
                latestThumbnail = await Task.detached(priority: .utility) { PhotoThumbnail.make(url, maxPixel: 240) }.value
            }
            message = "저장한 프레임으로 새 합성본을 만들었습니다."
        }
        catch { report(error) }
    }
    func saveCompositeToPhotos() async {
        guard !busy, let result = latestComposite, !compositeSavedToPhotos else { return }
        busy = true; defer { busy = false }
        do { try await PhotoStore.addToPhotos(result); compositeSavedToPhotos = true; if latestOriginal == result { savedToPhotos = true } }
        catch { report(error) }
    }

    var canRecordVideo: Bool {
        snapshot.video.isVideoMode && snapshot.state == .running && !busy && !switchingMode && !changingVideo && !applyingSettings && !recordingRequested && !snapshot.isApplyingSettings
            && snapshot.video.phase == .idle
    }

    func setVideoMode(_ enabled: Bool, configuration: VideoConfiguration? = nil) async {
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
        busy = true
        defer { busy = false }
        do {
            let series = try await service.captureSeries(format: photoFormat, rawMode: rawMode, bracketStep: bracketEnabled ? bracketStep : nil,
                resolution: rawMode == .processed && !bracketEnabled ? photoResolution : nil, flash: effectiveFlash)
            latestPhotoResolution = series.photos.first?.pixelDimensions
            let urls = try await CaptureSeriesStore.preserve(series)
            latestOriginals = urls
            latestOriginal = urls[urls.count / 2]
            let center = urls[urls.count / 2]
            latestThumbnail = await Task.detached(priority: .utility) { PhotoThumbnail.make(center, maxPixel: 240) }.value
            savedToPhotos = false
            try await PhotoStore.addToPhotos(urls)
            savedToPhotos = true
            message = "원본 \(urls.count)장과 사진 보관함에 저장했습니다."
        } catch { report(error) }
    }

    func saveLatestToPhotos() async {
        guard !busy, !savedToPhotos, let latestOriginal else { return }
        busy = true
        defer { busy = false }
        do {
            try await PhotoStore.addToPhotos(latestOriginals.isEmpty ? [latestOriginal] : latestOriginals)
            savedToPhotos = true
            message = "사진 보관함에 저장했습니다."
        } catch { report(error) }
    }
}
