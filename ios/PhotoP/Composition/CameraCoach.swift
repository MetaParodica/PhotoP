import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

struct CameraTilt: Sendable {
    let generatedAt: Double
    let rollDegrees: Double?
    let pitchDegrees: Double
    func isFresh(at time: Double) -> Bool { time >= generatedAt && time - generatedAt <= 1 }
    static func measure(x: Double, y: Double, z: Double, orientation: String, time: Double) -> CameraTilt? {
        guard [x, y, z, time].allSatisfy(\.isFinite), abs(x) <= 1.1, abs(y) <= 1.1, abs(z) <= 1.1 else { return nil }
        var gx = x, gy = y
        if orientation == "landscapeLeft" { gx = -y; gy = x }
        if orientation == "landscapeRight" { gx = y; gy = -x }
        var roll = atan2(gx, -gy) * 180 / .pi
        while roll > 90 { roll -= 180 }; while roll < -90 { roll += 180 }
        return CameraTilt(generatedAt: time, rollDegrees: abs(z) > 0.85 ? nil : roll,
                          pitchDegrees: asin(min(1, max(-1, -z))) * 180 / .pi)
    }
}

struct CoachLens: Sendable {
    let id: String
    let equivalent: Double
}

struct CoachCameraContext: Sendable {
    var mode: CoachCaptureMode = .photo
    var lensID = ""
    var zoom = 1.0
    var maximumZoom = 1.0
    var lensEquivalent = 1.0
    var opticalLenses: [CoachLens] = []
    var exposureManual = false
    var exposureLocked = false
    var ev = 0.0
    var minimumEV = -3.0
    var maximumEV = 3.0
    var zoomSuppressed = false
}

struct CoachZoomProposal: Equatable, Sendable {
    let factor: Double
    let lensID: String? // nil means current camera DIGITAL zoom
    let label: String
}

struct CameraCoachAdvice: Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case clipping, backlight, dark, level, perspective, angle, zoom, framing }
    let kind: Kind
    let message: String
    let priority: Int
    var zoom: CoachZoomProposal?
    var exposureDirection: Double? // advice only; never a device mutation
    var id: String { kind.rawValue }
}

struct CameraCoachResult: Sendable {
    let generatedAt: Double
    let lensID: String
    let baseZoom: Double
    let advice: [CameraCoachAdvice]
    func isFresh(at time: Double) -> Bool { time >= generatedAt && time - generatedAt <= 0.65 }
}

enum CameraCoachEngine {
    static func evaluate(guide: LiveCompositionGuide, intent: ShootingIntent, camera: CoachCameraContext,
                         tilt: CameraTilt?, now: Double) -> [CameraCoachAdvice] {
        guard guide.isFresh(at: now) else { return [] }
        var output: [CameraCoachAdvice] = []
        if let photo = guide.evidence.photometry, guide.evidence.isFresh(at: now) {
            let face = guide.subject?.detection.faceCenter.map { p in
                CGRect(x: max(0, p.x - 0.04), y: max(0, p.y - 0.04), width: 0.08, height: 0.08)
            }
            let subjectMean = (face ?? guide.measuredBounds).flatMap { photo.brightness(in: $0) }
            let locked = camera.exposureManual || camera.exposureLocked
            let limit = locked ? " · 수동/잠금 유지, 자동 변경 안 함" : " · 노출 패널에서 직접 조절"
            if photo.highlights >= 0.03 {
                output.append(CameraCoachAdvice(kind: .clipping,
                    message: String(format: "SDR 밝은 채널 상한 근접 %.1f%% · 하이라이트를 확인하고 노출 감소 검토", photo.highlights * 100) + limit,
                    priority: 100, exposureDirection: !locked && camera.ev > camera.minimumEV ? -0.3 : nil))
            } else if let subjectMean, subjectMean < 0.28, photo.mean - subjectMean > 0.22 {
                output.append(CameraCoachAdvice(kind: .backlight, message: "대상 영역이 주변보다 어둡습니다. 역광 가능성 · 밝은 배경 손실도 확인하세요." + limit,
                    priority: 90, exposureDirection: !locked && camera.ev < camera.maximumEV ? 0.3 : nil))
            } else if photo.mean < 0.18 && photo.shadows > 0.25 {
                output.append(CameraCoachAdvice(kind: .dark, message: "SDR 샘플이 어둡습니다. 촬영 의도가 아니라면 노출 증가와 흔들림을 확인하세요." + limit,
                    priority: 80, exposureDirection: !locked && camera.ev < camera.maximumEV ? 0.3 : nil))
            }
        }
        if let tilt, tilt.isFresh(at: now) {
            if let roll = tilt.rollDegrees, abs(roll) > 2 {
                output.append(CameraCoachAdvice(kind: .level, message: String(format: "기기 수평 기울기 %.1f° · 수평 표시를 맞추세요. 원근 왜곡과는 별개입니다.", roll), priority: 75))
            } else if abs(tilt.pitchDegrees) > 22 {
                output.append(CameraCoachAdvice(kind: .angle, message: String(format: "기기가 앞뒤로 %.0f° 기울어져 있습니다. 촬영 의도와 원근을 확인하세요. 촬영 높이는 판별하지 않습니다.", tilt.pitchDegrees), priority: 50))
            }
        }
        if guide.evidence.isFresh(at: now), let convergence = guide.evidence.verticalConvergence, convergence > 8 {
            output.append(CameraCoachAdvice(kind: .perspective, message: String(format: "사각형 좌우 수직선 차이 %.1f° · 원근 가능성. 기기 수평만 맞춰도 해소된다고 보장하지 않습니다.", convergence), priority: 65))
        }
        if !camera.zoomSuppressed, let box = guide.measuredBounds,
           let proposal = zoom(subjectHeight: Double(box.height / max(0.01, guide.framingRegion.height)), intent: intent, camera: camera) {
            output.append(CameraCoachAdvice(kind: .zoom, message: proposal.label, priority: 40, zoom: proposal))
        }
        return output.sorted { $0.priority > $1.priority }
    }

    static func zoom(subjectHeight: Double, intent: ShootingIntent, camera: CoachCameraContext) -> CoachZoomProposal? {
        guard camera.mode != .raw, [subjectHeight, camera.zoom, camera.maximumZoom, camera.lensEquivalent].allSatisfy(\.isFinite),
              subjectHeight > 0.04, subjectHeight <= 1, camera.maximumZoom >= 1, camera.zoom >= 1,
              camera.zoom <= camera.maximumZoom, camera.lensEquivalent > 0 else { return nil }
        let ratio = Double(intent.subjectHeight) / subjectHeight
        guard ratio < 0.78 || ratio > 1.3 else { return nil }
        let wanted = camera.zoom * camera.lensEquivalent * min(2, max(0.5, ratio))
        if camera.mode != .video, let optical = camera.opticalLenses.filter({
            $0.id != camera.lensID && $0.equivalent.isFinite && $0.equivalent > 0 && abs(log($0.equivalent / wanted)) < 0.2
        }).min(by: { abs(log($0.equivalent / wanted)) < abs(log($1.equivalent / wanted)) }) {
            return CoachZoomProposal(factor: optical.equivalent, lensID: optical.id,
                                     label: String(format: "지원 물리 카메라 %.1f× 제안 · 탭해 렌즈 전환, 제어 범위 변경 가능", optical.equivalent))
        }
        let factor = min(max(1, min(5, camera.maximumZoom)), max(1, wanted / camera.lensEquivalent))
        guard abs(factor - camera.zoom) > 0.2 else { return nil }
        return CoachZoomProposal(factor: factor, lensID: nil,
                                 label: String(format: "현재 카메라 %.1f× 디지털 줌 제안 · 확대 시 세부 화질 저하 가능 · 탭으로만 적용", factor))
    }
}

// Suggestions must persist for 0.6s before publication. A disappeared condition
// is removed immediately; values/actions always come from the CURRENT frame.
struct CoachAdviceStabilizer {
    private var entered: [String: Double] = [:]
    private var lastTime = -Double.infinity
    mutating func update(_ advice: [CameraCoachAdvice], at time: Double) -> [CameraCoachAdvice] {
        guard time.isFinite, time > lastTime else { return [] }
        if time - lastTime > 0.65 { entered = [:] }
        lastTime = time
        let keys = Set(advice.map(\.id))
        entered = entered.filter { keys.contains($0.key) }
        for item in advice where entered[item.id] == nil { entered[item.id] = time }
        return Array(advice.filter { time - (entered[$0.id] ?? time) >= 0.6 }.prefix(3))
    }
}
