import AVFoundation
import SwiftUI

@MainActor
final class CameraModel: ObservableObject {
    @Published private(set) var snapshot = CameraSnapshot(lenses: [], selectedLens: nil, capabilities: nil,
                                                       state: .stopped, message: nil, revision: 0,
                                                       readout: nil, isApplyingSettings: false)
    @Published var settings = CameraSettings()
    @Published var photoFormat: PhotoFileFormat = .jpeg
    @Published private(set) var busy = false
    @Published private(set) var latestOriginal: URL?
    @Published private(set) var savedToPhotos = false
    @Published var message: String?
    @Published var showGrid = true
    @Published var showControls = false

    private lazy var service = CameraService { [weak self] value in
        Task { @MainActor [weak self] in self?.receive(value) }
    }
    var previewSession: AVCaptureSession { service.session }
    var canCapture: Bool { snapshot.state == .running && !busy && !snapshot.isApplyingSettings && (snapshot.capabilities?.photoFormats.contains(photoFormat) == true) }

    func setActive(_ active: Bool) { service.setActive(active) }
    func selectLens(_ id: String) {
        guard !busy, !snapshot.isApplyingSettings else { return }
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
        guard canCapture else { return }
        busy = true
        defer { busy = false }
        do {
            let actions = try await service.focusAndMeter(at: point, lensID: lensID)
            if actions.focus && actions.exposure { message = "터치 위치를 초점·노출 기준으로 지정했습니다." }
            else if actions.focus { message = "터치 초점 기준을 지정했습니다. 노출은 변경하지 않았습니다." }
            else { message = "터치 노출 기준을 지정했습니다. 초점은 변경하지 않았습니다." }
        } catch { message = error.localizedDescription }
    }

    func capture() async {
        guard canCapture else { return }
        busy = true
        defer { busy = false }
        do {
            let photo = try await service.capturePhoto(format: photoFormat)
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
