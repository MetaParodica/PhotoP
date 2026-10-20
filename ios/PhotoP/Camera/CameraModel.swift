import AVFoundation
import SwiftUI

@MainActor
final class CameraModel: ObservableObject {
    @Published private(set) var snapshot = CameraSnapshot(lenses: [], selectedLens: nil, capabilities: nil,
                                                       state: .stopped, message: nil)
    @Published var settings = CameraSettings()
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
    var canCapture: Bool { snapshot.state == .running && !busy }

    func setActive(_ active: Bool) { service.setActive(active) }
    func selectLens(_ id: String) {
        guard !busy else { return }
        service.selectLens(id)
    }

    private func receive(_ value: CameraSnapshot) {
        if value.selectedLens != snapshot.selectedLens, let caps = value.capabilities {
            settings = CameraSettings()
            settings.exposure.iso = min(max(100, caps.iso.lowerBound), caps.iso.upperBound)
            settings.exposure.shutterSeconds = min(max(1.0 / 125, caps.shutterSeconds.lowerBound), caps.shutterSeconds.upperBound)
        }
        snapshot = value
        if let text = value.message { message = text }
    }

    func applySettings() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await service.apply(settings)
            message = "설정을 카메라에 전달했습니다. 자동 모드의 실제 값은 촬영 파일에서 확인하세요."
        } catch { message = error.localizedDescription }
    }

    func capture() async {
        guard canCapture else { return }
        busy = true
        defer { busy = false }
        do {
            let data = try await service.capturePhoto()
            let url = try await PhotoStore.preserveOriginal(data)
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
