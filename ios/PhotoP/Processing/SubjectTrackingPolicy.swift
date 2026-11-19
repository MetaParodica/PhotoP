import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

enum SubjectTrackingMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case object, person, face
    var id: String { rawValue }
    var title: String { switch self { case .object: return "물체"; case .person: return "인물"; case .face: return "얼굴" } }
}

struct SubjectTrackingSelection: Codable, Equatable, Sendable {
    let id: UUID
    let point: CGPoint
    let mode: SubjectTrackingMode
    var seedBounds: CGRect?
    init(point: CGPoint, mode: SubjectTrackingMode = .object, seedBounds: CGRect? = nil, id: UUID = UUID()) {
        self.id = id; self.point = point; self.mode = mode; self.seedBounds = seedBounds
    }
    var valid: Bool {
        Self.valid(point) && (seedBounds.map { Self.valid($0) && $0.contains(point) } ?? true)
    }
    static func valid(_ point: CGPoint) -> Bool {
        point.x.isFinite && point.y.isFinite && (0...1).contains(point.x) && (0...1).contains(point.y)
    }
    static func valid(_ box: CGRect) -> Bool {
        [box.minX, box.minY, box.width, box.height].allSatisfy(\.isFinite) && box.width >= 0.01 && box.height >= 0.01 &&
            box.minX >= 0 && box.minY >= 0 && box.maxX <= 1.000001 && box.maxY <= 1.000001
    }
    var region: CGRect {
        seedBounds ?? CGRect(x: min(0.82, max(0, point.x - 0.09)), y: min(0.82, max(0, point.y - 0.09)), width: 0.18, height: 0.18)
    }
}

enum SubjectTrackingPhase: String, Codable, Sendable {
    case off, selecting, acquiring, tracking, uncertain, lost
    var title: String {
        switch self {
        case .off: return "추적 끔"; case .selecting: return "화면에서 피사체 선택"
        case .acquiring: return "피사체 확인 중"; case .tracking: return "피사체 추적 중"
        case .uncertain: return "추적 불확실 · 원본 유지"; case .lost: return "대상 놓침 · 다시 선택"
        }
    }
}

struct SubjectTrackingSnapshot: Equatable, Sendable {
    let selectionID: UUID?
    let generation: UInt64
    let phase: SubjectTrackingPhase
    let bounds: CGRect?
    let confidence: Float
    let time: Double
    var boundsTime: Double? = nil
    func isFresh(at now: Double) -> Bool {
        let observed = bounds == nil ? time : boundsTime ?? time
        return now.isFinite && time.isFinite && observed.isFinite && now >= time && now >= observed &&
            now - time <= 0.45 && now - observed <= 0.45
    }
    func focus(at now: Double) -> CGPoint? {
        guard phase == .tracking, isFresh(at: now), let bounds else { return nil }
        return CGPoint(x: bounds.midX, y: bounds.midY)
    }
}

// Cost fusion ported from FoundationVision/ByteTrack matching.py:fuse_score,
// commit d1bf0191adff59bc8fcfeaa0b33d3d1642552a99.
// Copyright (c) 2021 Yifu Zhang. MIT License (full text also bundled).
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
// of the Software, and to permit persons to whom the Software is furnished to do
// so, subject to the following conditions: The above copyright notice and this
// permission notice shall be included in all copies or substantial portions of
// the Software. THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO
// EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES
// OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
// ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
// DEALINGS IN THE SOFTWARE.
enum SubjectAssociation {
    static func cost(overlap: Double, confidence: Double) -> Double? {
        guard overlap.isFinite, confidence.isFinite, (0...1).contains(overlap), (0...1).contains(confidence) else { return nil }
        return 1 - overlap * confidence
    }
    static func compatible(_ a: CGRect, _ b: CGRect, confidence: Float) -> Bool {
        guard SubjectTrackingSelection.valid(a), SubjectTrackingSelection.valid(b), confidence.isFinite, (0...1).contains(confidence) else { return false }
        let ratio = b.width * b.height / (a.width * a.height)
        let distance = hypot(a.midX - b.midX, a.midY - b.midY)
        let intersection = a.intersection(b)
        let area = intersection.isNull ? 0 : intersection.width * intersection.height
        let iou = min(1, max(0, area / max(0.000001, a.width * a.height + b.width * b.height - area)))
        guard let cost = cost(overlap: Double(iou), confidence: Double(confidence)) else { return false }
        return (0.4...2.5).contains(ratio) && distance < 0.24 && (cost < 0.97 || distance < 0.075)
    }
}

// One selected target, not biometric identity. Low-confidence observations can
// maintain a hypothesis but NEVER drive blur/AF. A lost target needs a new tap.
struct SubjectTrackingState: Sendable {
    private(set) var selection: SubjectTrackingSelection?
    private(set) var generation: UInt64 = 0
    private var enabled = false
    private var box: CGRect?
    private var phase: SubjectTrackingPhase = .off
    private var lastTime = -Double.infinity
    private var lastGoodTime = -Double.infinity
    private var firstTime = -Double.infinity
    private var confidence: Float = 0
    private var good = 0
    mutating func configure(enabled: Bool, selection: SubjectTrackingSelection?, generation: UInt64) {
        guard self.enabled != enabled || self.selection != selection || self.generation != generation else { return }
        self.enabled = enabled; self.selection = selection?.valid == true ? selection : nil; self.generation = generation
        box = nil; confidence = 0; good = 0; lastTime = -.infinity; lastGoodTime = -.infinity; firstTime = -.infinity
        phase = !enabled ? .off : self.selection == nil ? .selecting : .acquiring
    }
    @discardableResult mutating func observe(bounds: CGRect?, confidence: Float, time: Double, generation: UInt64) -> Bool {
        guard enabled, selection != nil, self.generation == generation, time.isFinite, time > lastTime, phase != .lost else { return false }
        if lastTime.isFinite, time - lastTime > 0.8 { phase = .lost; self.confidence = 0; return false }
        if !firstTime.isFinite { firstTime = time }
        lastTime = time
        guard let bounds, SubjectTrackingSelection.valid(bounds), confidence.isFinite, (0...1).contains(confidence),
              box.map({ SubjectAssociation.compatible($0, bounds, confidence: confidence) }) ?? true else {
            weaken(at: time); return false
        }
        guard confidence >= 0.6 else { weaken(at: time); return false }
        // Follow motion; smooth only sub-pixel-like jitter, not large movement.
        if let old = box, hypot(old.midX - bounds.midX, old.midY - bounds.midY) < 0.015 {
            box = CGRect(x: old.minX * 0.25 + bounds.minX * 0.75, y: old.minY * 0.25 + bounds.minY * 0.75,
                         width: old.width * 0.25 + bounds.width * 0.75, height: old.height * 0.25 + bounds.height * 0.75)
        } else { box = bounds }
        self.confidence = confidence; lastGoodTime = time; good += 1
        phase = good >= 2 ? .tracking : .acquiring
        return true
    }
    private mutating func weaken(at time: Double) {
        good = 0; confidence = 0
        phase = lastGoodTime.isFinite && time - lastGoodTime > 0.8 ? .lost : .uncertain
        if !lastGoodTime.isFinite { phase = time - firstTime > 0.8 ? .lost : .uncertain }
    }
    func snapshot(at now: Double) -> SubjectTrackingSnapshot {
        let stale = phase == .tracking && (!now.isFinite || now < lastTime || now - lastTime > 0.45)
        return .init(selectionID: selection?.id, generation: generation, phase: stale ? .uncertain : phase,
                     bounds: box, confidence: confidence, time: lastTime, boundsTime: lastGoodTime)
    }
}
