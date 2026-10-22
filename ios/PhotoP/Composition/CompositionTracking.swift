import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// All coordinates here are normalized in the delivered, rotated/mirrored image,
// with a TOP-left origin. No UI, camera mutation, identity recognition or ML model.
struct DetectedPerson: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case person, face }
    let bounds: CGRect
    let faceCenter: CGPoint?
    let confidence: Float
    var kind: Kind = .person

    var valid: Bool {
        let values = [bounds.minX, bounds.minY, bounds.width, bounds.height]
        return values.allSatisfy(\.isFinite) && bounds.width > 0.015 && bounds.height > 0.015 &&
            bounds.minX >= 0 && bounds.minY >= 0 && bounds.maxX <= 1 && bounds.maxY <= 1 &&
            confidence.isFinite && confidence >= 0.5 &&
            (faceCenter.map { $0.x.isFinite && $0.y.isFinite && bounds.contains($0) } ?? true)
    }
}

struct TrackedPerson: Identifiable, Equatable, Sendable {
    let id: Int
    let detection: DetectedPerson
    let lastSeen: Double
    var bounds: CGRect { detection.bounds }
    var anchor: CGPoint { detection.faceCenter ?? CGPoint(x: bounds.midX, y: bounds.midY) }
}

struct CompositionSubjectTracker {
    private var tracks: [TrackedPerson] = []
    private var nextID = 1
    private var previousTime = -Double.infinity
    private(set) var selectedID: Int?

    mutating func select(_ id: Int?) { selectedID = id }
    func containsTrack(_ id: Int?) -> Bool { tracks.contains { $0.id == id } }

    mutating func update(_ detections: [DetectedPerson], at time: Double) -> [TrackedPerson] {
        guard time.isFinite, time > previousTime else { return [] }
        previousTime = time
        tracks.removeAll { time - $0.lastSeen > 0.8 }
        let detections = Array(detections.filter(\.valid).prefix(12))
        // Greedy GLOBAL best pairing, not detection-order pairing. No track can
        // match twice. Ambiguous crossings/occlusions are not biometric identity.
        var pairs: [(track: Int, detection: Int, cost: CGFloat)] = []
        for (ti, track) in tracks.enumerated() {
            for (di, detection) in detections.enumerated() where track.detection.kind == detection.kind {
                let a = track.bounds, b = detection.bounds
                let distance = hypot(a.midX - b.midX, a.midY - b.midY)
                let areaRatio = (b.width * b.height) / (a.width * a.height)
                let intersection = a.intersection(b)
                let overlap = intersection.isNull ? 0 : intersection.width * intersection.height
                let iou = overlap / max(0.0001, a.width * a.height + b.width * b.height - overlap)
                guard (0.4...2.5).contains(areaRatio), distance < 0.18, iou > 0.1 || distance < 0.075 else { continue }
                pairs.append((ti, di, distance + (1 - iou) * 0.1))
            }
        }
        pairs.sort { $0.cost < $1.cost }
        var usedTracks = Set<Int>(), usedDetections = Set<Int>(), visible: [TrackedPerson] = []
        for pair in pairs where !usedTracks.contains(pair.track) && !usedDetections.contains(pair.detection) {
            let old = tracks[pair.track], new = detections[pair.detection]
            let distance = hypot(old.bounds.midX - new.bounds.midX, old.bounds.midY - new.bounds.midY)
            // Catch up immediately on motion/recovery; gently suppress small jitter.
            let alpha: CGFloat = time - old.lastSeen > 0.4 || distance > 0.05 ? 0.9 : 0.65
            func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * alpha }
            let bounds = CGRect(x: mix(old.bounds.minX, new.bounds.minX), y: mix(old.bounds.minY, new.bounds.minY),
                                width: mix(old.bounds.width, new.bounds.width), height: mix(old.bounds.height, new.bounds.height))
            let face: CGPoint?
            if let a = old.detection.faceCenter, let b = new.faceCenter {
                face = CGPoint(x: mix(a.x, b.x), y: mix(a.y, b.y))
            } else { face = new.faceCenter }
            let value = TrackedPerson(id: old.id, detection: DetectedPerson(bounds: bounds, faceCenter: face,
                                        confidence: new.confidence, kind: new.kind), lastSeen: time)
            tracks[pair.track] = value; visible.append(value)
            usedTracks.insert(pair.track); usedDetections.insert(pair.detection)
        }
        for (di, detection) in detections.enumerated() where !usedDetections.contains(di) {
            let value = TrackedPerson(id: nextID, detection: detection, lastSeen: time)
            nextID += 1; tracks.append(value); visible.append(value)
        }
        // Missing tracks remain briefly for association, NEVER as visible ghosts.
        return visible.sorted { $0.id < $1.id }
    }

    static func subject(at point: CGPoint, in subjects: [TrackedPerson]) -> Int? {
        subjects.filter { $0.bounds.contains(point) }
            .min { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }?.id
    }
}

enum CompositionTarget: String, CaseIterable, Identifiable, Sendable {
    case automatic, left, right
    var id: String { rawValue }
    var title: String { switch self { case .automatic: return "가까운 삼분할"; case .left: return "왼쪽 삼분할"; case .right: return "오른쪽 삼분할" } }
}

struct LiveCompositionGuide: Sendable {
    let generatedAt: Double
    let imageSize: CGSize
    let subjects: [TrackedPerson]
    let selectedID: Int?
    let targetBounds: CGRect?
    let targetPoint: CGPoint?
    let aligned: Bool
    let advice: String
    var rule: CompositionRule = .thirds
    var candidates: [CompositionCandidate] = []
    var measuredPoint: CGPoint?
    var measuredBounds: CGRect?
    var evidence = SceneEvidence()
    var subjectLabel = "인물 중심"
    var framingRegion = CGRect(x: 0, y: 0, width: 1, height: 1)
    var subject: TrackedPerson? { subjects.first { $0.id == selectedID } }
    func isFresh(at time: Double) -> Bool { time >= generatedAt && time - generatedAt <= 0.65 }
}

struct CompositionAlignment {
    private var enteredAt: Double?
    private var lastTime = -Double.infinity
    private var lastHaptic = -Double.infinity
    private(set) var aligned = false

    mutating func reset() { enteredAt = nil; aligned = false; lastTime = -.infinity }
    mutating func update(error: CGFloat?, at time: Double) -> Bool {
        guard time.isFinite, time > lastTime else { return false }
        if time - lastTime > 0.45 { enteredAt = nil; aligned = false }
        lastTime = time
        guard let error, error.isFinite else { enteredAt = nil; aligned = false; return false }
        if aligned {
            if error > 0.075 { aligned = false; enteredAt = nil }
            return false
        }
        guard error <= 0.045 else { enteredAt = nil; return false }
        if enteredAt == nil { enteredAt = time }
        guard time - (enteredAt ?? time) >= 0.6 else { return false }
        aligned = true
        guard time - lastHaptic >= 3 else { return false }
        lastHaptic = time; return true
    }
}

struct CompositionGuideEngine {
    private var tracker = CompositionSubjectTracker()
    private var alignment = CompositionAlignment()
    private var epoch: UInt64?
    private var automaticID: Int?
    private var previousTarget: CompositionTarget?
    private var targetX: CGFloat?
    private var lastTime = -Double.infinity
    private var previousSubjectID: Int?
    private var previousRule: CompositionRule?
    private var previousIntent: ShootingIntent?
    private var autoRule: CompositionRule?
    private var pendingRule: CompositionRule?
    private var pendingRuleTime = 0.0
    private var previousRegion: CGRect?

    mutating func select(_ id: Int?) {
        tracker.select(id); automaticID = nil; targetX = nil; alignment.reset()
    }

    mutating func update(_ snapshot: CompositionSnapshot, target: CompositionTarget, now: Double,
                         rule requestedRule: CompositionRule = .thirds, intent: ShootingIntent = .balanced,
                         mode: CoachCaptureMode = .photo, region: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1),
                         learning: CompositionLearning = CompositionLearning()) -> (LiveCompositionGuide, Bool)? {
        guard snapshot.generatedAt <= now, now - snapshot.generatedAt <= 0.65,
              snapshot.generatedAt > lastTime, snapshot.width > 0, snapshot.height > 0,
              [region.minX, region.minY, region.width, region.height].allSatisfy(\.isFinite), region.width > 0, region.height > 0 else { return nil }
        if previousRegion != region { alignment.reset(); targetX = nil; previousRegion = region }
        if epoch != snapshot.epoch {
            tracker = CompositionSubjectTracker(); alignment.reset(); automaticID = nil; targetX = nil; previousSubjectID = nil
            epoch = snapshot.epoch
            autoRule = nil; pendingRule = nil
        }
        if snapshot.generatedAt - lastTime > 0.65 { alignment.reset(); targetX = nil }
        lastTime = snapshot.generatedAt
        let subjects = tracker.update(snapshot.people, at: snapshot.generatedAt)
        if tracker.selectedID == nil, !tracker.containsTrack(automaticID) {
            automaticID = subjects.max { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }?.id
        }
        let id = tracker.selectedID ?? automaticID
        let subject = subjects.first { $0.id == id }
        let candidates = SceneCompositionEngine.recommend(snapshot: snapshot, intent: intent, mode: mode, selected: subject, learning: learning)
        let proposed = candidates.first?.rule ?? .center
        if autoRule == nil { autoRule = proposed }
        if proposed != autoRule {
            if pendingRule != proposed { pendingRule = proposed; pendingRuleTime = snapshot.generatedAt }
            if snapshot.generatedAt - pendingRuleTime >= 0.8 { autoRule = proposed; pendingRule = nil }
        } else { pendingRule = nil }
        let rule = requestedRule == .automatic ? (autoRule ?? .center) : requestedRule
        if rule != previousRule || intent != previousIntent {
            alignment.reset(); targetX = nil; previousRule = rule; previousIntent = intent
        }
        if previousSubjectID != id || previousTarget != target {
            alignment.reset(); targetX = nil; previousSubjectID = id; previousTarget = target
        }
        let size = CGSize(width: snapshot.width, height: snapshot.height)
        let evidence = snapshot.evidence.isFresh(at: snapshot.generatedAt) ? snapshot.evidence : SceneEvidence()
        var box = subject?.bounds
        var observedPoint = subject?.anchor
        var label = subject?.detection.faceCenter == nil ? "인물 중심" : "얼굴 중심"
        if rule == .group, tracker.selectedID == nil, subjects.count >= 2 {
            box = subjects.dropFirst().reduce(subjects[0].bounds) { $0.union($1.bounds) }
            observedPoint = box.map { CGPoint(x: $0.midX, y: $0.midY) }; label = "단체 영역 중심"
        }
        if rule == .landscape || rule == .nightLong, let angle = evidence.horizonDegrees, angle.isFinite {
            let pulse = alignment.update(error: CGFloat(abs(angle) * 0.03), at: snapshot.generatedAt)
            var guide = LiveCompositionGuide(generatedAt: snapshot.generatedAt, imageSize: size, subjects: subjects,
                selectedID: id, targetBounds: nil, targetPoint: nil, aligned: alignment.aligned,
                advice: alignment.aligned ? "추정 수평 방향 정렬 완료" : String(format: "추정 수평 방향 %.1f° · 기준선과 맞추세요. 높이는 미검출입니다.", angle))
            guide.rule = rule; guide.candidates = candidates; guide.evidence = evidence; guide.framingRegion = region
            return (guide, pulse)
        }
        if tracker.selectedID == nil, automaticID == nil {
            if [.leadingLines, .vanishingPoint].contains(rule), let intersection = evidence.intersection {
                box = nil; observedPoint = intersection; label = "추정 직선 교차점"
            } else if let area = evidence.saliency.max(by: { $0.width * $0.height < $1.width * $1.height }) {
                box = area; observedPoint = CGPoint(x: area.midX, y: area.midY); label = "관심 영역 중심(종류 미분류)"
            } else if let area = evidence.rectangleBounds.max(by: { $0.width * $0.height < $1.width * $1.height }), rule.category != "인물" {
                box = area; observedPoint = CGPoint(x: area.midX, y: area.midY); label = "검출 사각형 중심"
            }
        }
        guard let measured = observedPoint else {
            _ = alignment.update(error: nil, at: snapshot.generatedAt)
            var guide = LiveCompositionGuide(generatedAt: snapshot.generatedAt, imageSize: size, subjects: subjects, selectedID: id,
                        targetBounds: nil, targetPoint: nil, aligned: false,
                        advice: tracker.selectedID == nil ? "측정 대상 없음 · \(rule.title) 수동 기준선을 사용할 수 있습니다." : "선택한 인물을 찾지 못했습니다. 인물을 다시 탭하거나 자동 선택을 누르세요.")
            guide.rule = rule; guide.candidates = candidates; guide.evidence = evidence; guide.framingRegion = region
            return (guide, false)
        }
        if targetX == nil {
            targetX = measured.x <= region.midX ? 1.0 / 3 : 2.0 / 3
        }
        let fixedSide: CompositionTarget = target == .automatic ? ((targetX ?? 0.3) < 0.5 ? .left : .right) : target
        var desired = SceneCompositionEngine.anchor(rule: rule, point: measured, side: fixedSide, region: region)
        if rule == .portraitFull, subject?.detection.faceCenter == nil { desired.y = region.midY }
        let anchor = measured
        let bounds = box ?? CGRect(x: anchor.x - 0.005, y: anchor.y - 0.005, width: 0.01, height: 0.01)
        // Preserve observed size, not a fictional desired distance/zoom. Clamp the
        // translated box so a full body is not guided outside the actual image.
        let marginX = min(0.02, max(0, (region.width - bounds.width) / 2))
        let marginY = min(0.02, max(0, (region.height - bounds.height) / 2))
        let dx = min(max(desired.x - anchor.x, region.minX + marginX - bounds.minX), region.maxX - marginX - bounds.maxX)
        let dy = min(max(desired.y - anchor.y, region.minY + marginY - bounds.minY), region.maxY - marginY - bounds.maxY)
        let destination = CGPoint(x: anchor.x + dx, y: anchor.y + dy)
        let shortEdge = min(size.width, size.height)
        let targetDisplacement = hypot((destination.x - desired.x) * size.width / shortEdge,
                                       (destination.y - desired.y) * size.height / shortEdge)
        let canFitThirds = targetDisplacement <= rule.tolerance && bounds.width <= region.width && bounds.height <= region.height
        let error = hypot(dx * size.width / shortEdge, dy * size.height / shortEdge)
        let haptic = alignment.update(error: canFitThirds ? error * 0.045 / rule.tolerance : nil, at: snapshot.generatedAt)
        let advice: String
        if !canFitThirds { advice = "대상 전체를 화면 안에 유지하세요. 현재 크기에서는 \(rule.title) 정렬이 어렵습니다." }
        else if alignment.aligned { advice = "\(rule.title) 정렬 완료 · 촬영해 보세요." }
        else if error <= rule.tolerance { advice = "목표 위치입니다. 잠시 구도를 유지하세요." }
        else {
            let horizontal = abs(dx) * size.width / shortEdge > 0.025 ? (dx > 0 ? "오른쪽" : "왼쪽") : ""
            let vertical = abs(dy) * size.height / shortEdge > 0.025 ? (dy > 0 ? "아래쪽" : "위쪽") : ""
            advice = "화면 속 \(label)을 \([horizontal, vertical].filter { !$0.isEmpty }.joined(separator: "·")) 목표점에 맞추세요."
        }
        var guide = LiveCompositionGuide(generatedAt: snapshot.generatedAt, imageSize: size, subjects: subjects, selectedID: id,
                    targetBounds: box?.offsetBy(dx: dx, dy: dy), targetPoint: destination, aligned: alignment.aligned, advice: advice)
        guide.rule = rule; guide.candidates = candidates; guide.measuredPoint = measured; guide.measuredBounds = box
        guide.evidence = evidence; guide.subjectLabel = label
        guide.framingRegion = region
        return (guide, haptic)
    }
}
