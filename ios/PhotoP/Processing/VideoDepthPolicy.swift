import Foundation

enum VideoDepthQuality: String, Codable, CaseIterable, Identifiable, Sendable {
    case balanced, high
    var id: String { rawValue }
    var title: String { self == .high ? "고품질" : "균형" }
    var pairs: Int { self == .high ? 16 : 8 }
}

struct VideoDepthKeyframe: Codable, Equatable, Sendable {
    let time: Double
    var focus: CGPoint
    var aperture: Double
    var profile: DepthLensProfile
    var selection: SubjectTrackingSelection?
    var valid: Bool {
        time.isFinite && (0...600).contains(time) && SubjectTrackingSelection.valid(focus) &&
            aperture.isFinite && (1.4...16).contains(aperture) && (selection?.valid ?? true)
    }
}

struct VideoDepthIntent: Codable, Equatable, Sendable {
    static let version = 1
    var version = Self.version
    var quality: VideoDepthQuality = .high
    var keyframes: [VideoDepthKeyframe]
    var valid: Bool {
        version == Self.version && !keyframes.isEmpty && keyframes.count <= 4096 && keyframes[0].time == 0 &&
            keyframes.allSatisfy(\.valid) && zip(keyframes, keyframes.dropFirst()).allSatisfy { $0.time < $1.time }
    }
    func parameters(at time: Double) -> VideoDepthKeyframe? {
        guard valid, time.isFinite, time >= 0 else { return nil }
        // Explicit changes apply at their timestamp; do not anticipate a future tap.
        return keyframes.last(where: { $0.time <= time })
    }
    @discardableResult mutating func append(_ value: VideoDepthKeyframe) -> Bool {
        guard value.valid, let last = keyframes.last, value.time >= last.time else { return false }
        if value.time == last.time { keyframes[keyframes.count - 1] = value; return true }
        if value.focus == last.focus && value.aperture == last.aperture && value.profile == last.profile && value.selection == last.selection { return true }
        // Preserve the initial state and taps; coalesce only rapid dial changes.
        if keyframes.count > 1, value.time - last.time < 0.1, value.selection == last.selection, value.focus == last.focus {
            keyframes[keyframes.count - 1] = value; return true
        }
        guard keyframes.count < 4096 else { return false }
        keyframes.append(value); return true
    }
}

enum VideoDepthPolicy {
    static func supports(width: Int, height: Int, fps: Double, duration: Double) -> Bool {
        width >= 16 && height >= 16 && width <= 4096 && height <= 4096 && width * height <= 9_437_184 &&
            width % 2 == 0 && height % 2 == 0 && fps.isFinite && (1...60.1).contains(fps) &&
            duration.isFinite && duration > 0 && duration <= 600.1
    }
    static func bitrate(width: Int, height: Int, fps: Double, original: Double, hevc: Bool) -> Int? {
        guard supports(width: width, height: height, fps: fps, duration: 1), original.isFinite, original >= 0 else { return nil }
        let quality = Double(width * height) * fps * (hevc ? 0.22 : 0.35)
        return Int(min(240_000_000, max(2_000_000, original, quality)))
    }
    // AV preferredTransform is in top-left coordinates. Core Image is bottom-left.
    // Conjugate the transform with the input/output vertical flips, preserving PTS.
    static func coreImageTransform(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double,
                                   inputHeight: Double, outputHeight: Double) -> [Double]? {
        guard [a,b,c,d,tx,ty,inputHeight,outputHeight].allSatisfy(\.isFinite), inputHeight > 0, outputHeight > 0,
              abs(abs(a * d - b * c) - 1) < 0.00001,
              abs(a * a + b * b - 1) < 0.00001, abs(c * c + d * d - 1) < 0.00001,
              abs(a * c + b * d) < 0.00001 else { return nil }
        return [a, -b, -c, d, c * inputHeight + tx, outputHeight - d * inputHeight - ty]
    }
}
