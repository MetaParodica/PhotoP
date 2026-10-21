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
    @Published private(set) var savedToPhotos = false
    @Published var message: String?
    @Published var showGrid = true
    @Published var showControls = false
    @Published private(set) var livePreview: LiveLUTPreview?
    @Published private(set) var liveLUTTitle: String?
    @Published private(set) var liveHasFrame = false
    @Published var liveIntensity = 1.0
    @Published var liveGrain = 0.0
    @Published var liveCompareOriginal = false
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
    var canCapture: Bool { rawUnavailableReason == nil && snapshot.state == .running && !busy && !snapshot.isApplyingSettings && (snapshot.capabilities?.photoFormats.contains(photoFormat) == true) }

    func setActive(_ active: Bool) {
        if !active { liveHasFrame = false }
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
        liveHasFrame = false
        livePreview = preview
        updateLiveIntensity()
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
            updateLiveIntensity()
        } catch { message = error.localizedDescription }
    }

    func disableLiveLUT() {
        livePreview?.setRunning(false)
        livePreview = nil
        liveHasFrame = false
        service.removeLivePreview()
    }

    func updateLiveIntensity() {
        livePreview?.setIntensity(liveCompareOriginal ? 0 : liveIntensity, grain: GrainSettings(amount: liveCompareOriginal ? 0 : liveGrain))
    }

    private func makeLivePreview(_ lut: CubeLUT) async throws -> LiveLUTPreview {
        let onEvent: @Sendable (UUID, LiveLUTPreview.Event) -> Void = { [weak self] id, event in
            Task { @MainActor [weak self] in
                guard let self, let preview = self.livePreview, preview.id == id, preview.isCurrentEvent(event) else { return }
                switch event.kind {
                case .waiting: self.liveHasFrame = false
                case .ready: self.liveHasFrame = true
                case .failed(let reason):
                    self.disableLiveLUT()
                    self.message = "LUT 프리뷰를 해제했습니다: \(reason)"
                }
            }
        }
        return try await Task.detached(priority: .userInitiated) { try LiveLUTPreview(lut: lut, onEvent: onEvent) }.value
    }

    func capture() async {
        guard canCapture else { return }
        busy = true
        defer { busy = false }
        do {
            let photo = try await service.capturePhoto(format: photoFormat, rawMode: rawMode)
            let url = try await PhotoStore.preserveOriginal(photo)
            latestOriginal = url
            savedToPhotos = false
            try await PhotoStore.addToPhotos(url)
            savedToPhotos = true
            message = "원본과 사진 보관함에 저장했습니다."
        } catch { message = error.localizedDescription }
    }

    func saveLatestToPhotos() async {
        guard !busy, !savedToPhotos, let latestOriginal else { return }
        busy = true
        defer { busy = false }
        do {
            try await PhotoStore.addToPhotos(latestOriginal)
            savedToPhotos = true
            message = "사진 보관함에 저장했습니다."
        } catch { message = error.localizedDescription }
    }
}
