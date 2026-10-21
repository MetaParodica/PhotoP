import Foundation

enum VideoResolution: String, CaseIterable, Codable, Identifiable, Sendable {
    case hd720, hd1080, uhd4K
    var id: String { rawValue }
    var title: String { switch self { case .hd720: return "720p"; case .hd1080: return "1080p"; case .uhd4K: return "4K" } }
    var longEdge: Int { switch self { case .hd720: return 1280; case .hd1080: return 1920; case .uhd4K: return 3840 } }
    var shortEdge: Int { switch self { case .hd720: return 720; case .hd1080: return 1080; case .uhd4K: return 2160 } }
}

enum VideoCodec: String, CaseIterable, Codable, Identifiable, Sendable {
    case h264, hevc
    var id: String { rawValue }
    var title: String { self == .h264 ? "H.264" : "HEVC" }
}

enum VideoStabilization: String, CaseIterable, Codable, Identifiable, Sendable {
    case off, standard, cinematic, cinematicExtended
    var id: String { rawValue }
    var title: String {
        switch self { case .off: return "끔"; case .standard: return "표준"; case .cinematic: return "시네마틱"; case .cinematicExtended: return "확장" }
    }
}

struct VideoConfiguration: Equatable, Codable, Sendable {
    var resolution: VideoResolution = .hd1080
    var framesPerSecond = 30
    var codec: VideoCodec = .h264
    var audio = false
    // nil means the request is unknown (version 1 manifests, recovered pending files).
    var stabilization: VideoStabilization? = .off
}

extension VideoConfiguration {
    // Version 1 manifests predate audio/stabilization. Synthesized decoding would reject them.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        resolution = try c.decode(VideoResolution.self, forKey: .resolution)
        framesPerSecond = try c.decode(Int.self, forKey: .framesPerSecond)
        codec = try c.decode(VideoCodec.self, forKey: .codec)
        audio = try c.decodeIfPresent(Bool.self, forKey: .audio) ?? false
        stabilization = try c.decodeIfPresent(VideoStabilization.self, forKey: .stabilization)
    }
}

struct VideoCapabilities: Equatable, Sendable {
    // Resolution presets are probed separately. FPS/codecs/stabilization describe ONLY the active preset.
    let resolutions: [VideoResolution]
    let frameRates: [Int]
    let codecs: [VideoCodec]
    var stabilizationModes: [VideoStabilization] = [.off]
    var audio = false
}

enum VideoRecordingPhase: String, Sendable {
    case idle, starting, recording, stopping
    var isActive: Bool { self != .idle }
}

struct VideoSnapshot: Sendable {
    var configuration: VideoConfiguration?
    var capabilities: VideoCapabilities?
    var phase: VideoRecordingPhase = .idle
    var elapsedSeconds = 0.0
    var isVideoMode: Bool { configuration != nil }
}

enum VideoCapturePolicy {
    // Conservative first release: standard integer rates, capped at 60; no high-speed claim.
    static func frameRates(in ranges: [ClosedRange<Double>]) -> [Int] {
        [24, 25, 30, 50, 60].filter { fps in ranges.contains { $0.contains(Double(fps)) } }
    }
    static func validate(_ configuration: VideoConfiguration, capabilities: VideoCapabilities) throws {
        guard capabilities.resolutions.contains(configuration.resolution),
              capabilities.frameRates.contains(configuration.framesPerSecond),
              capabilities.codecs.contains(configuration.codec),
              capabilities.stabilizationModes.contains(configuration.stabilization ?? .off),
              !configuration.audio || capabilities.audio else { throw CameraError.invalidSettings }
    }
    // Cinematic modes add latency and crop; only modes the active format reports are offered.
    static func stabilizationModes(supported: (VideoStabilization) -> Bool) -> [VideoStabilization] {
        [.off] + VideoStabilization.allCases.filter { $0 != .off && supported($0) }
    }
    static func audioLabel(_ configuration: VideoConfiguration?) -> String { configuration?.audio == true ? "오디오" : "무음" }
    static func shutterLimit(sensor: ClosedRange<Double>, fps: Int) throws -> ClosedRange<Double> {
        guard fps > 0, sensor.lowerBound.isFinite, sensor.upperBound.isFinite,
              sensor.lowerBound > 0, sensor.lowerBound <= 1 / Double(fps) else { throw CameraError.invalidSettings }
        return sensor.lowerBound...min(sensor.upperBound, 1 / Double(fps))
    }
    static func suggestedShutter(fps: Int, limits: ClosedRange<Double>) -> Double {
        min(max(1 / (2 * Double(max(1, fps))), limits.lowerBound), limits.upperBound)
    }
    static func finishedSuccessfully(hasError: Bool, successfulFinishFlag: Bool) -> Bool {
        !hasError || successfulFinishFlag
    }
}

// Delegate callbacks may arrive after a stop request, interruption, or an older job.
struct VideoRecordingLifecycle {
    private(set) var url: URL?
    private(set) var phase: VideoRecordingPhase = .idle
    mutating func begin(_ url: URL) throws {
        guard self.url == nil else { throw CameraError.busy }
        self.url = url; phase = .starting
    }
    @discardableResult mutating func requestStop() -> Bool {
        guard phase.isActive else { return false }
        let shouldStop = phase == .recording
        phase = .stopping
        return shouldStop
    }
    // Return true if a stop arrived before didStart, so the adapter must stop immediately.
    mutating func didStart(_ url: URL) -> Bool {
        guard self.url == url else { return false }
        if phase == .stopping { return true }
        if phase == .starting { phase = .recording }
        return false
    }
    mutating func finish(_ url: URL) -> Bool {
        guard self.url == url else { return false }
        self.url = nil; phase = .idle
        return true
    }
}
