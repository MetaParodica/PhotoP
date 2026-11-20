import Foundation

enum ExperimentalDepthMode: String, Sendable { case photo, savedVideo, live }

/// Only newly introduced experiments live here. Baseline depth/AI/AF preferences
/// are neither read nor written by this store.
struct ExperimentalDepthPreferences: Codable, Equatable, Sendable {
    var version = 1
    var photoSubjectSelection = false
    var photoPortraitMatte = false
    init() {}
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        photoSubjectSelection = try values.decodeIfPresent(Bool.self, forKey: .photoSubjectSelection) ?? false
        photoPortraitMatte = try values.decodeIfPresent(Bool.self, forKey: .photoPortraitMatte) ?? false
    }
    var hasPhotoExperiment: Bool { photoSubjectSelection || photoPortraitMatte }
    var valid: Bool { version == 1 }
}

final class ExperimentalDepthRuntime: @unchecked Sendable {
    static let shared = ExperimentalDepthRuntime()
    static let preferenceKey = "photop.experimental.depth.preferences.v1"
    private let lock = NSLock()
    private let defaults: UserDefaults
    private var preferences: ExperimentalDepthPreferences
    private var generation: UInt64 = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.preferenceKey), data.count <= 4096,
           let value = try? JSONDecoder().decode(ExperimentalDepthPreferences.self, from: data), value.valid {
            preferences = value
        } else { preferences = .init() }
    }
    var current: ExperimentalDepthPreferences { lock.withLock { preferences } }
    func setPhotoSelection(_ enabled: Bool) {
        lock.withLock {
            guard preferences.photoSubjectSelection != enabled else { return }
            preferences.photoSubjectSelection = enabled
            generation &+= 1
            if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: Self.preferenceKey) }
        }
    }
    func setPortraitMatte(_ enabled: Bool) {
        lock.withLock {
            guard preferences.photoPortraitMatte != enabled else { return }
            preferences.photoPortraitMatte = enabled; generation &+= 1
            if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: Self.preferenceKey) }
        }
    }
    func request(for mode: ExperimentalDepthMode) -> ExperimentalPhotoRequest? {
        lock.withLock {
            guard mode == .photo, preferences.hasPhotoExperiment else { return nil }
            return ExperimentalPhotoRequest(owner: self, generation: generation, preferences: preferences)
        }
    }
    fileprivate func current(_ epoch: UInt64) -> Bool {
        lock.withLock { preferences.hasPhotoExperiment && generation == epoch }
    }
    fileprivate func publish(_ epoch: UInt64, _ action: () throws -> Void) rethrows -> Bool {
        try lock.withLock {
            guard preferences.hasPhotoExperiment, generation == epoch else { return false }
            try action()
            return true
        }
    }
}

struct ExperimentalPhotoRequest: Sendable {
    fileprivate let owner: ExperimentalDepthRuntime
    fileprivate let generation: UInt64
    let preferences: ExperimentalDepthPreferences
    var isCurrent: Bool { owner.current(generation) }
    func publishIfCurrent(_ action: () throws -> Void) rethrows -> Bool { try owner.publish(generation, action) }
}

enum ExperimentalSelectionFailure: String, Codable, Sendable, Error {
    case unavailable, noSubject, invalidOutput, inferenceFailed, disabled, notPerson, ambiguousPerson
    var title: String {
        switch self {
        case .unavailable: return "정밀 선택 모델을 준비하지 못했습니다."
        case .noSubject: return "터치한 피사체를 확실하게 선택하지 못했습니다."
        case .invalidOutput: return "정밀 선택 결과를 사용할 수 없습니다."
        case .inferenceFailed: return "정밀 선택 처리를 완료하지 못했습니다."
        case .disabled: return "실험 기능을 꺼 기존 방식으로 처리했습니다."
        case .notPerson: return "선택한 위치에서 인물을 확인하지 못했습니다."
        case .ambiguousPerson: return "인물이 겹쳐 경계를 확실하게 구분하지 못했습니다."
        }
    }
}

struct ExperimentalPortraitRecord: Codable, Equatable, Sendable {
    static let modelID = "MatAnyone2Kit-photo-d85a029"
    var version = 1
    var model = Self.modelID
    var revision = "d85a029870b5149af6aa122cbc13c90db11e5b35"
    var resourceSHA256 = "7e970a2ad50c5bf91b9df155d2bcc54151d496ce3fc5431bfcc3b6877be05b32"
    var outcome: ExperimentalDepthRecord.Outcome
    var failure: ExperimentalSelectionFailure?
    var focusX: Double
    var focusY: Double
    var workingWidth = 288
    var workingHeight = 512
    var warmupPredictions = 10
    var seedModel = "Vision-person-instance"
    var diagnosticCode: String?
    var valid: Bool {
        guard version == 1, model == Self.modelID, revision == "d85a029870b5149af6aa122cbc13c90db11e5b35",
              resourceSHA256 == "7e970a2ad50c5bf91b9df155d2bcc54151d496ce3fc5431bfcc3b6877be05b32",
              workingWidth == 288, workingHeight == 512, warmupPredictions == 10,
              ["Vision-person-instance", ExperimentalDepthRecord.modelID].contains(seedModel), focusX.isFinite, focusY.isFinite,
              (0...1).contains(focusX), (0...1).contains(focusY), (diagnosticCode?.count ?? 0) <= 160 else { return false }
        return outcome == .applied ? failure == nil : failure != nil
    }
    var title: String {
        outcome == .applied ? "실험적 사진 인물 경계 개선 적용" : "인물 경계는 기존 방식으로 처리 · " + (failure?.title ?? "")
    }
}

struct ExperimentalPortraitGeometry: Equatable, Sendable {
    let x: Int, y: Int, width: Int, height: Int
    init?(sourceWidth: Int, sourceHeight: Int) {
        guard sourceWidth > 0, sourceHeight > 0, sourceWidth <= 16384, sourceHeight <= 16384 else { return nil }
        let scale = min(288 / Double(sourceWidth), 512 / Double(sourceHeight))
        width = max(1, min(288, Int((Double(sourceWidth) * scale).rounded())))
        height = max(1, min(512, Int((Double(sourceHeight) * scale).rounded())))
        x = (288 - width) / 2; y = (512 - height) / 2
    }
}

struct ExperimentalDepthRecord: Codable, Equatable, Sendable {
    enum Outcome: String, Codable, Sendable { case applied, fallback }
    static let modelID = "EdgeTAM-photo-jutsu-v1.2"
    static let modelFingerprint = "9c35c1b6667a0dd80b093bbc20747628f304133ad2a531de049307beb3ae1401"
    static let decoderGraphFingerprint = "a3e0ca6334727c633e3185262f4b2dca888a5ebaec6349166dff4fa9b167f373"
    var version = 1
    var outcome: Outcome
    var failure: ExperimentalSelectionFailure?
    var model = Self.modelID
    var archiveSHA256 = Self.modelFingerprint
    var decoderGraphSHA256: String? = Self.decoderGraphFingerprint
    var focusX: Double
    var focusY: Double
    var analysisWidth = 256
    var analysisHeight = 256
    var predictedIoU: Float?
    var objectScore: Float?
    var valid: Bool {
        version == 1 && model == Self.modelID && archiveSHA256 == Self.modelFingerprint &&
        (decoderGraphSHA256 == nil || decoderGraphSHA256 == Self.decoderGraphFingerprint) &&
        focusX.isFinite && focusY.isFinite && (0...1).contains(focusX) && (0...1).contains(focusY) &&
        analysisWidth == 256 && analysisHeight == 256 &&
        (predictedIoU.map { $0.isFinite && (0...1).contains($0) } ?? true) &&
        (objectScore.map(\.isFinite) ?? true) &&
        (outcome == .applied ? failure == nil && (predictedIoU ?? 0) >= 0.5 && (objectScore ?? 0) > 0 : failure != nil)
    }
    var title: String {
        outcome == .applied ? "실험적 사진 정밀 선택 적용" : "정밀 선택은 기존 방식으로 처리 · " + (failure?.title ?? "")
    }
}

/// Segmentation logits are a coarse prior, not measured optical alpha or depth.
enum ExperimentalPhotoMaskPolicy {
    static func alpha(logits: [Float], width: Int, height: Int, x: Double, y: Double,
                      predictedIoU: Float, objectScore: Float) -> [Float]? {
        guard width == 256, height == 256, logits.count == width * height,
              x.isFinite, y.isFinite, (0...1).contains(x), (0...1).contains(y),
              predictedIoU.isFinite, (0.5...1).contains(predictedIoU), objectScore.isFinite, objectScore > 0,
              logits.allSatisfy(\.isFinite) else { return nil }
        let px = min(width - 1, Int(x * Double(width))), py = min(height - 1, Int(y * Double(height)))
        let count = logits.reduce(0) { $0 + ($1 > 0 ? 1 : 0) }
        guard logits[py * width + px] > 0, count >= 9, Double(count) / Double(logits.count) < 0.995 else { return nil }
        return logits.map { 1 / (1 + exp(-min(32, max(-32, $0)))) }
    }
}
