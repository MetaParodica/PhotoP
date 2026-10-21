import Foundation

struct CameraLens: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let isFront: Bool
}

struct CameraCapabilities: Equatable, Sendable {
    let lensID: String
    let iso: ClosedRange<Double>
    let shutterSeconds: ClosedRange<Double>
    let exposureBias: ClosedRange<Double>
    let manualExposure: Bool
    let manualFocus: Bool
    let manualWhiteBalance: Bool
    var exposureLock = false
    var focusLock = false
    var whiteBalanceLock = false
    var photoFormats: [PhotoFileFormat] = [.jpeg]
    var rawModes: [RawCaptureMode] = [.processed]
    var maximumBracketCount = 0
    var photoResolutions: [PhotoResolution] = []
}

struct ExposureSettings: Equatable, Sendable {
    var manual = false
    var locked = false
    var iso: Double = 100
    var shutterSeconds: Double = 1.0 / 125
    var ev: Double = 0
}

struct FocusSettings: Equatable, Sendable {
    var manual = false
    var locked = false
    // Normalized lens position, not a distance in metres.
    var lensPosition: Double = 0.5
}

struct WhiteBalanceSettings: Equatable, Sendable {
    var manual = false
    var locked = false
    var kelvin: Double = 5000
    var tint: Double = 0
}

struct CameraSettings: Equatable, Sendable {
    var exposure = ExposureSettings()
    var focus = FocusSettings()
    var whiteBalance = WhiteBalanceSettings()
}

enum CaptureSessionState: Equatable, Sendable {
    case stopped, running, interrupted
}

struct CameraReadout: Sendable {
    let iso: Double
    let shutterSeconds: Double
    let exposureBias: Double
    let lensPosition: Double
    let kelvin: Double?
    let tint: Double?
    let isAdjusting: Bool
    let exposureLocked: Bool
    let focusLocked: Bool
    let whiteBalanceLocked: Bool
}

struct CameraSnapshot: Sendable {
    let lenses: [CameraLens]
    let selectedLens: String?
    let capabilities: CameraCapabilities?
    let state: CaptureSessionState
    let message: String?
    let revision: UInt64
    let readout: CameraReadout?
    let isApplyingSettings: Bool
    var video = VideoSnapshot()
}

enum CameraError: LocalizedError {
    case permission, unavailable, configuration, busy, interrupted, invalidSettings, missingPhoto, settingsTimedOut, invalidPhotoData, captureTimedOut, videoTimedOut
    var errorDescription: String? {
        switch self {
        case .permission: return "설정에서 카메라 접근을 허용해 주세요."
        case .unavailable: return "사용 가능한 카메라가 없습니다. 실제 iPhone에서 실행해 주세요."
        case .configuration: return "카메라 구성을 적용하지 못했습니다."
        case .busy: return "진행 중인 촬영이 끝난 뒤 다시 시도해 주세요."
        case .interrupted: return "카메라 사용이 중단되었습니다. 촬영 화면에서 다시 시작해 주세요."
        case .invalidSettings: return "현재 렌즈에서 지원하지 않는 설정입니다."
        case .missingPhoto: return "촬영한 사진 데이터를 받지 못했습니다."
        case .invalidPhotoData: return "받은 사진의 파일 포맷이 요청한 포맷과 다릅니다."
        case .videoTimedOut: return "영상 기록 완료가 지연되어 카메라를 중단했습니다. Pending 파일은 보관합니다. 다시 연결해 주세요."
        case .captureTimedOut: return "사진 촬영이 지연되어 카메라를 중단했습니다. 다시 시작해 주세요."
        case .settingsTimedOut: return "카메라 설정 변경이 지연되어 중단했습니다. 다시 시작해 주세요."
        }
    }
}

// Shared by UI validation and the adapter; testable without camera hardware.
enum CameraSettingsValidator {
    static func validate(_ settings: CameraSettings, for capabilities: CameraCapabilities) throws {
        let e = settings.exposure
        let f = settings.focus
        let w = settings.whiteBalance
        guard [e.iso, e.shutterSeconds, e.ev, f.lensPosition, w.kelvin, w.tint].allSatisfy(\.isFinite)
        else { throw CameraError.invalidSettings }
        guard !(e.manual && e.locked), !(f.manual && f.locked), !(w.manual && w.locked),
              !e.locked || capabilities.exposureLock,
              !f.locked || capabilities.focusLock,
              !w.locked || capabilities.whiteBalanceLock else { throw CameraError.invalidSettings }
        if e.manual {
            guard capabilities.manualExposure, capabilities.iso.contains(e.iso),
                  capabilities.shutterSeconds.contains(e.shutterSeconds) else { throw CameraError.invalidSettings }
        } else if !e.locked && !capabilities.exposureBias.contains(e.ev) { throw CameraError.invalidSettings }
        if f.manual && (!capabilities.manualFocus || !(0...1).contains(f.lensPosition)) {
            throw CameraError.invalidSettings
        }
        if w.manual && (!capabilities.manualWhiteBalance || !(2000...10000).contains(w.kelvin) || !(-150...150).contains(w.tint)) {
            throw CameraError.invalidSettings
        }
    }
}
