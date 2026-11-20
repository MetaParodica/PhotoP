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
    var requiresTracking = false
    var valid: Bool {
        time.isFinite && (0...600).contains(time) && SubjectTrackingSelection.valid(focus) &&
            aperture.isFinite && (1.4...16).contains(aperture) && (selection?.valid ?? true)
    }
}

enum VideoDepthInterpolation: String, Codable, CaseIterable, Sendable {
    case hold, linear, smooth
    var title: String { self == .hold ? "시점에서 변경" : self == .linear ? "일정 전환" : "부드러운 전환" }
}

struct VideoDepthIntent: Codable, Equatable, Sendable {
    static let version = 2
    var version = Self.version
    var quality: VideoDepthQuality = .high
    var keyframes: [VideoDepthKeyframe]
    var interpolation: VideoDepthInterpolation? = nil
    var valid: Bool {
        [1, Self.version].contains(version) && (version != 1 || interpolation == nil || interpolation == .hold) && !keyframes.isEmpty && keyframes.count <= 4096 && keyframes[0].time == 0 &&
            keyframes.allSatisfy(\.valid) && zip(keyframes, keyframes.dropFirst()).allSatisfy { $0.time < $1.time }
    }
    func parameters(at time: Double) -> VideoDepthKeyframe? {
        guard valid, time.isFinite, time >= 0 else { return nil }
        // Explicit changes apply at their timestamp; do not anticipate a future tap.
        guard let index = keyframes.lastIndex(where: { $0.time <= time }) else { return nil }
        var left = keyframes[index]
        guard let curve = interpolation, curve != .hold, index+1 < keyframes.count else { return left }
        let right = keyframes[index+1]
        // A new target, profile, or tracking policy is a discrete user action.
        // Never animate a box from the old person onto a different identity.
        guard left.profile == right.profile, left.requiresTracking == right.requiresTracking,
              left.selection == right.selection else { return left }
        var t = min(1,max(0,(time-left.time)/(right.time-left.time)))
        if curve == .smooth { t = t*t*(3-2*t) }
        if left.selection == nil {
            left.focus = CGPoint(x: left.focus.x+(right.focus.x-left.focus.x)*t, y: left.focus.y+(right.focus.y-left.focus.y)*t)
        }
        // CoC is proportional to reciprocal f-number: interpolate optical power.
        left.aperture = 1 / ((1-t)/left.aperture+t/right.aperture)
        return left
    }
    @discardableResult mutating func append(_ value: VideoDepthKeyframe) -> Bool {
        guard value.valid, let last = keyframes.last, value.time >= last.time else { return false }
        if value.time == last.time { keyframes[keyframes.count - 1] = value; return true }
        if value.focus == last.focus && value.aperture == last.aperture && value.profile == last.profile && value.selection == last.selection && value.requiresTracking == last.requiresTracking { return true }
        // Preserve the initial state and taps; coalesce only rapid dial changes.
        if keyframes.count > 1, value.time - last.time < 0.1, value.selection == last.selection, value.requiresTracking == last.requiresTracking, value.focus == last.focus {
            keyframes[keyframes.count - 1] = value; return true
        }
        guard keyframes.count < 4096 else { return false }
        keyframes.append(value); return true
    }
}

enum VideoDepthPolicy {
    // Undo preview mirroring, then rotate into the orientation frozen by the movie output.
    static func recordedPoint(_ point: CGPoint, mirrored: Bool, previewAngle: Int, recordingAngle: Int) -> CGPoint? {
        guard SubjectTrackingSelection.valid(point), [0,90,180,270].contains(previewAngle), [0,90,180,270].contains(recordingAngle) else { return nil }
        let p = CGPoint(x: mirrored ? 1 - point.x : point.x, y: point.y)
        switch (recordingAngle - previewAngle + 360) % 360 {
        case 0: return p
        case 90: return CGPoint(x: 1 - p.y, y: p.x)
        case 180: return CGPoint(x: 1 - p.x, y: 1 - p.y)
        default: return CGPoint(x: p.y, y: 1 - p.x)
        }
    }
    static func recordedSelection(_ selection: SubjectTrackingSelection?, mirrored: Bool, previewAngle: Int, recordingAngle: Int) -> SubjectTrackingSelection? {
        guard let selection, selection.valid, let point = recordedPoint(selection.point, mirrored: mirrored, previewAngle: previewAngle, recordingAngle: recordingAngle) else { return nil }
        var bounds: CGRect?
        if let seed = selection.seedBounds {
            let corners = [CGPoint(x: seed.minX,y: seed.minY),CGPoint(x: seed.maxX,y: seed.minY),CGPoint(x: seed.minX,y: seed.maxY),CGPoint(x: seed.maxX,y: seed.maxY)]
                .compactMap { recordedPoint($0, mirrored: mirrored, previewAngle: previewAngle, recordingAngle: recordingAngle) }
            guard corners.count == 4 else { return nil }
            let xs = corners.map(\.x), ys = corners.map(\.y)
            bounds = CGRect(x: xs.min()!,y: ys.min()!,width: xs.max()! - xs.min()!,height: ys.max()! - ys.min()!)
        }
        return .init(point: point, mode: selection.mode, seedBounds: bounds, id: selection.id)
    }
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
              abs(a * c + b * d) < 0.00001,
              [a,b,c,d].allSatisfy({ min(abs($0), abs(abs($0) - 1)) < 0.00001 }) else { return nil }
        return [a, -b, -c, d, c * inputHeight + tx, outputHeight - d * inputHeight - ty]
    }
}
