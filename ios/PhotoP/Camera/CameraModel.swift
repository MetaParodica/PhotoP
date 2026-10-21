import AVFoundation
import SwiftUI

@MainActor
final class CameraModel: ObservableObject {
    @Published private(set) var snapshot = CameraSnapshot(lenses: [], selectedLens: nil, capabilities: nil,
                                                       state: .stopped, message: nil, revision: 0,
                                                       readout: nil, isApplyingSettings: false)
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
    @Published var showGrid = true
    @Published var showControls = false
    @Published private(set) var livePreview: LiveLUTPreview?
    @Published private(set) var liveLUTTitle: String?
    @Published private(set) var liveHasFrame = false
    @Published var monitoring = MonitoringSettings()
    @Published private(set) var histogram: PreviewHistogram?
    @Published private(set) var liveUsesLUT = false
    @Published var liveIntensity = 1.0
    @Published var liveGrain = 0.0
    @Published var liveCompareOriginal = false
    private var longJobID: UUID?
    private var longReprocessTask: Task<URL, Error>?
    private var importedLiveLUT: ImportedLUT?

    private lazy var service = CameraService { [weak self] value in
        Task { @MainActor [weak self] in self?.receive(value) }
    }
    var previewSession: AVCaptureSession { service.session }
    var rawUnavailableReason: String? {
        RawCapturePolicy.unavailableReason(mode: rawMode, available: snapshot.capabilities?.rawModes ?? [.processed],
                                          live: livePreview != nil,
                                          exposureMode: settings.exposure.manual ? .custom : (settings.exposure.locked ? .locked : .continuousAutoExposure))
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
    var canCapture: Bool { bracketUnavailableReason == nil && rawUnavailableReason == nil && snapshot.state == .running && !busy && !snapshot.isApplyingSettings && (snapshot.capabilities?.photoFormats.contains(photoFormat) == true) }

    func setActive(_ active: Bool) {
        if !active { liveHasFrame = false; histogram = nil }
        service.setActive(active)
    }
    func selectLens(_ id: String) {
        guard !busy, !snapshot.isApplyingSettings, livePreview == nil else { return }
        service.selectLens(id)
    }

    private func receive(_ value: CameraSnapshot) {
        guard value.revision > snapshot.revision else { return }
        if value.selectedLens != snapshot.selectedLens, let caps = value.capabilities {
            settings = CameraSettings()
            settings.exposure.iso = min(max(100, caps.iso.lowerBound), caps.iso.upperBound)
            settings.exposure.shutterSeconds = min(max(1.0 / 125, caps.shutterSeconds.lowerBound), caps.shutterSeconds.upperBound)
        }
        if let formats = value.capabilities?.photoFormats, !formats.contains(photoFormat), let first = formats.first {
            photoFormat = first
            message = "현재 렌즈에서 지원하지 않는 포맷이므로 \(first.title)로 전환했습니다."
        }
        if let modes = value.capabilities?.rawModes, !modes.contains(rawMode) { rawMode = .processed }
        snapshot = value
        if let text = value.message { message = text }
    }

    func applySettings() async {
        guard !busy, !snapshot.isApplyingSettings else { return }
        busy = true
        defer { busy = false }
        do {
            _ = try await service.apply(settings)
            message = "카메라의 설정 변경 완료를 확인했습니다. 현재값을 확인해 주세요."
        } catch { message = error.localizedDescription }
    }

    func focusAndMeter(_ point: CameraMeteringPoint, lensID: String) async {
        guard canCapture, livePreview == nil else { return }
        busy = true
        defer { busy = false }
        do {
            let actions = try await service.focusAndMeter(at: point, lensID: lensID)
            if actions.focus && actions.exposure { message = "터치 위치를 초점·노출 기준으로 지정했습니다." }
            else if actions.focus { message = "터치 초점 기준을 지정했습니다. 노출은 변경하지 않았습니다." }
            else { message = "터치 노출 기준을 지정했습니다. 초점은 변경하지 않았습니다." }
        } catch { message = error.localizedDescription }
    }

    func importLiveLUT(_ url: URL) async {
        guard !busy, !snapshot.isApplyingSettings, livePreview == nil else { return }
        busy = true
        defer { busy = false }
        do {
            let imported = try await Task.detached(priority: .userInitiated) { try ImportedLUT.read(url) }.value
            try await activateLiveLUT(imported)
        } catch { message = error.localizedDescription }
    }

    func useLiveLUT(_ imported: ImportedLUT) async throws {
        guard !busy, !snapshot.isApplyingSettings, livePreview == nil else { throw CameraError.busy }
        busy = true
        defer { busy = false }
        try await activateLiveLUT(imported)
    }

    private func activateLiveLUT(_ imported: ImportedLUT) async throws {
        let preview = try await makeLivePreview(imported.lut)
        try await service.setLivePreview(preview)
        importedLiveLUT = imported
        liveLUTTitle = imported.displayName
        liveUsesLUT = true
        liveHasFrame = false
        livePreview = preview
        updateLiveIntensity()
        updateMonitoring()
        message = "LUT는 미리보기에만 적용합니다. 촬영 사진은 원본 색상으로 저장합니다."
    }

    func favoriteLiveLUT() async {
        guard let importedLiveLUT else { return }
        do { try await LUTLibrary.shared.save(importedLiveLUT); message = "LUT 즐겨찾기에 저장했습니다." }
        catch { message = error.localizedDescription }
    }

    func enableLiveLUT() async {
        guard !busy, !snapshot.isApplyingSettings, livePreview == nil, let importedLiveLUT else { return }
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
        } catch { message = error.localizedDescription }
    }

    func disableLiveLUT() {
        livePreview?.setRunning(false)
        livePreview = nil
        liveHasFrame = false
        liveUsesLUT = false
        histogram = nil
        monitoring = MonitoringSettings()
        service.removeLivePreview()
    }

    func updateLiveIntensity() {
        livePreview?.setIntensity(!liveUsesLUT || liveCompareOriginal ? 0 : liveIntensity, grain: GrainSettings(amount: !liveUsesLUT || liveCompareOriginal ? 0 : liveGrain))
    }

    func updateMonitoring() {
        if !monitoring.histogram { histogram = nil }
        livePreview?.setMonitoring(monitoring)
    }

    func enableMonitoring() async {
        guard !busy, !snapshot.isApplyingSettings, monitoring.enabled else { return }
        if livePreview != nil { updateMonitoring(); return }
        busy = true
        defer { busy = false }
        do {
            var lines = ["LUT_3D_SIZE 2"]
            for b in 0...1 { for g in 0...1 { for r in 0...1 { lines.append("\(r) \(g) \(b)") } } }
            let identity = try CubeLUT.parse(lines.joined(separator: "\n"))
            let preview = try await makeLivePreview(identity)
            preview.setIntensity(0)
            preview.setMonitoring(monitoring)
            try await service.setLivePreview(preview)
            livePreview = preview
            liveHasFrame = false
            liveUsesLUT = false
            message = "SDR 프리뷰 기준 보조 도구입니다. 원본에 표시를 굽지 않습니다."
        } catch { message = error.localizedDescription }
    }

    private func makeLivePreview(_ lut: CubeLUT) async throws -> LiveLUTPreview {
        let onEvent: @Sendable (UUID, LiveLUTPreview.Event) -> Void = { [weak self] id, event in
            Task { @MainActor [weak self] in
                guard let self, let preview = self.livePreview, preview.id == id, preview.isCurrentEvent(event) else { return }
                switch event.kind {
                case .waiting: self.liveHasFrame = false; self.histogram = nil
                case .ready(let histogram):
                    self.liveHasFrame = true
                    if self.monitoring.histogram, let histogram { self.histogram = histogram }
                case .failed(let reason):
                    self.disableLiveLUT()
                    self.message = "LUT 프리뷰를 해제했습니다: \(reason)"
                }
            }
        }
        return try await Task.detached(priority: .userInitiated) { try LiveLUTPreview(lut: lut, onEvent: onEvent) }.value
    }

    func captureLongExposure() async {
        guard canCapture, rawMode == .processed, !bracketEnabled, livePreview == nil else { message = "합성 전 RAW·브래킷·LUT/모니터를 꺼 주세요."; return }
        busy = true; longProgress = nil; latestComposite = nil; compositeSavedToPhotos = false
        let id = UUID(); longJobID = id
        defer { busy = false; longJobID = nil }
        do {
            let url = try await service.captureLongExposure(longConfiguration) { [weak self] value in
                Task { @MainActor [weak self] in
                    guard let self, self.longJobID == id else { return }
                    self.longProgress = LongExposureProgress(fraction: value.fraction, accepted: value.accepted, rejected: value.rejected,
                                                            previewJPEG: value.previewJPEG ?? self.longProgress?.previewJPEG)
                }
            }
            latestComposite = url
            message = "SDR 합성 결과와 재처리 프레임을 저장했습니다."
            try await PhotoStore.addToPhotos(url); compositeSavedToPhotos = true
        } catch { message = error.localizedDescription }
    }
    func cancelLongExposure() { longReprocessTask?.cancel(); service.cancelLongExposure() }
    func reprocessLongExposure() async {
        guard !busy, let result = latestComposite else { return }
        busy = true
        let configuration = longConfiguration
        let task = Task { try await LongExposureArchive.reprocess(result, configuration: configuration) }
        longReprocessTask = task
        defer { busy = false; longReprocessTask = nil }
        do { latestComposite = try await task.value; compositeSavedToPhotos = false; message = "저장한 프레임으로 새 합성본을 만들었습니다." }
        catch { message = error.localizedDescription }
    }
    func saveCompositeToPhotos() async {
        guard !busy, let result = latestComposite, !compositeSavedToPhotos else { return }
        busy = true; defer { busy = false }
        do { try await PhotoStore.addToPhotos(result); compositeSavedToPhotos = true }
        catch { message = error.localizedDescription }
    }

    func capture() async {
        guard canCapture else { return }
        busy = true
        defer { busy = false }
        do {
            let series = try await service.captureSeries(format: photoFormat, rawMode: rawMode, bracketStep: bracketEnabled ? bracketStep : nil)
            let urls = try await CaptureSeriesStore.preserve(series)
            latestOriginals = urls
            latestOriginal = urls[urls.count / 2]
            savedToPhotos = false
            try await PhotoStore.addToPhotos(urls)
            savedToPhotos = true
            message = "원본 \(urls.count)장과 사진 보관함에 저장했습니다."
        } catch { message = error.localizedDescription }
    }

    func saveLatestToPhotos() async {
        guard !busy, !savedToPhotos, let latestOriginal else { return }
        busy = true
        defer { busy = false }
        do {
            try await PhotoStore.addToPhotos(latestOriginals.isEmpty ? [latestOriginal] : latestOriginals)
            savedToPhotos = true
            message = "사진 보관함에 저장했습니다."
        } catch { message = error.localizedDescription }
    }
}
