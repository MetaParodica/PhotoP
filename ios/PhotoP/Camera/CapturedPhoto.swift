import AVFoundation
import ImageIO
import UniformTypeIdentifiers

// Container type is verified before assigning a filename or exporting to Photos.
enum PhotoFileFormat: String, CaseIterable, Identifiable, Sendable {
    case jpeg, heif, dng
    var id: String { rawValue }
    var title: String { switch self { case .jpeg: return "JPEG"; case .heif: return "HEIF"; case .dng: return "DNG" } }
    var fileExtension: String { switch self { case .jpeg: return "jpg"; case .heif: return "heic"; case .dng: return "dng" } }
    var codec: AVVideoCodecType? { switch self { case .jpeg: return .jpeg; case .heif: return .hevc; case .dng: return nil } }

    static func supported(by codecs: [AVVideoCodecType]) -> [Self] {
        allCases.filter { format in format.codec.map { codecs.contains($0) } ?? false }
    }
}

struct CapturedPhoto: Sendable {
    let data: Data
    let format: PhotoFileFormat

    init(data: Data, expectedFormat: PhotoFileFormat) throws {
        if expectedFormat == .dng {
            try DNGContainer.validate(data)
            self.data = data
            self.format = .dng
            return
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let identifier = CGImageSourceGetType(source),
              let type = UTType(identifier as String) else { throw CameraError.invalidPhotoData }
        let actual: PhotoFileFormat
        if type.identifier == AVFileType.dng.rawValue { actual = .dng }
        else if type.conforms(to: .jpeg) { actual = .jpeg }
        else if type.conforms(to: .heic) { actual = .heif }
        else { throw CameraError.invalidPhotoData }
        guard actual == expectedFormat else { throw CameraError.invalidPhotoData }
        self.data = data
        self.format = actual
    }
}

// ProRAW and Bayer RAW share a DNG container; the capture request and delegate
// establish the raw kind. File extensions alone never establish either fact.
enum RawCaptureMode: String, CaseIterable, Identifiable, Sendable {
    case processed, bayer, appleProRAW
    var id: String { rawValue }
    var title: String {
        switch self { case .processed: return "일반 사진"; case .bayer: return "Bayer RAW"; case .appleProRAW: return "Apple ProRAW" }
    }
}

enum RawCapturePolicy {
    static func modes(formats: [UInt32], classify: (UInt32) -> RawCaptureMode?) -> [RawCaptureMode] {
        [.processed] + [RawCaptureMode.bayer, .appleProRAW].filter { mode in formats.contains { classify($0) == mode } }
    }
    static func unavailableReason(mode: RawCaptureMode, available: [RawCaptureMode],
                                  live: Bool, exposureMode: AVCaptureDevice.ExposureMode?) -> String? {
        guard available.contains(mode) else { return "현재 렌즈·구성에서 이 RAW 포맷을 지원하지 않습니다." }
        if mode != .processed && live { return "RAW 촬영 전 실시간 LUT/모니터를 꺼 주세요. 스트림 동시 조합은 아직 검증하지 않았습니다." }
        if mode == .appleProRAW && (exposureMode == .custom || exposureMode == .locked) {
            return "현재 ProRAW는 자동 노출에서 제공합니다. 수동 노출·AE 잠금을 해제하거나 Bayer RAW를 선택해 주세요."
        }
        return nil
    }
}

