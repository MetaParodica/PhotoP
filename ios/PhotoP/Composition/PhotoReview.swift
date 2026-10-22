import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

struct CaptureGuideReference: Codable, Sendable {
    let intent: ShootingIntent
    let rule: CompositionRule
    let mode: CoachCaptureMode
    let subjectBounds: CGRect?
    let subjectAnchor: CGPoint?
    let target: CGPoint?
    let isFaceAnchor: Bool
    let personCount: Int
    let imageAspect: Double
    let brightness: Double?
    let roll: Double?
    let capturedAt: Date
    var valid: Bool {
        func point(_ p: CGPoint?) -> Bool { p.map { $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) } ?? true }
        let boxValid = subjectBounds.map { b in
            [b.minX, b.minY, b.width, b.height].allSatisfy(\.isFinite) && b.width > 0 && b.height > 0 &&
            b.minX >= 0 && b.minY >= 0 && b.maxX <= 1.001 && b.maxY <= 1.001
        } ?? true
        return boxValid && point(subjectAnchor) && point(target) && (0...24).contains(personCount) &&
            imageAspect.isFinite && (0.1...10).contains(imageAspect) &&
            (brightness.map { $0.isFinite && (0...1).contains($0) } ?? true) &&
            (roll.map { $0.isFinite && abs($0) <= 90 } ?? true) && capturedAt.timeIntervalSince1970.isFinite
    }

    static func make(guide: LiveCompositionGuide, intent: ShootingIntent, mode: CoachCaptureMode,
                     mirrored: Bool, tilt: CameraTilt?, now: Double) -> CaptureGuideReference? {
        guard guide.isFresh(at: now), guide.imageSize.height > 0 else { return nil }
        func point(_ p: CGPoint?) -> CGPoint? { p.map { CGPoint(x: mirrored ? 1 - $0.x : $0.x, y: $0.y) } }
        let box = guide.measuredBounds.map { b in CGRect(x: mirrored ? 1 - b.maxX : b.minX, y: b.minY, width: b.width, height: b.height) }
        return CaptureGuideReference(intent: intent, rule: guide.rule, mode: mode, subjectBounds: box,
            subjectAnchor: point(guide.measuredPoint), target: point(guide.targetPoint), isFaceAnchor: guide.subject?.detection.faceCenter != nil,
            personCount: guide.subjects.count, imageAspect: Double(guide.imageSize.width / guide.imageSize.height),
            brightness: guide.evidence.photometry?.mean,
            roll: tilt.flatMap { $0.isFresh(at: now) ? $0.rollDegrees : nil }, capturedAt: Date())
    }
}

struct PhotoReviewFinding: Codable, Identifiable, Equatable, Sendable {
    enum Basis: String, Codable, Sendable { case measured, suggestion, limitation }
    let id: String
    let title: String
    let message: String
    let basis: Basis
}

struct PhotoReviewReport: Codable, Sendable {
    var version = 1
    let originalFilename: String
    let originalSHA256: String
    let analyzedAt: Date
    let sourceDescription: String
    let findings: [PhotoReviewFinding]
    let reference: CaptureGuideReference?
    var valid: Bool {
        version == 1 && !originalFilename.isEmpty && originalFilename.count <= 255 &&
        originalFilename == URL(fileURLWithPath: originalFilename).lastPathComponent &&
        originalSHA256.count == 64 && originalSHA256.allSatisfy { "0123456789abcdef".contains($0) } &&
        analyzedAt.timeIntervalSince1970.isFinite && sourceDescription.count <= 1000 && (reference?.valid ?? true) &&
        findings.count <= 32 && Set(findings.map(\.id)).count == findings.count &&
        findings.allSatisfy { $0.message.count <= 2000 && $0.title.count <= 150 && !$0.id.isEmpty && $0.id.count <= 100 }
    }
}

enum PhotoReviewEngine {
    static func findings(snapshot: CompositionSnapshot, reference: CaptureGuideReference?) -> [PhotoReviewFinding] {
        var output: [PhotoReviewFinding] = []
        func add(_ id: String, _ title: String, _ message: String, _ basis: PhotoReviewFinding.Basis = .measured) {
            output.append(PhotoReviewFinding(id: id, title: title, message: message, basis: basis))
        }
        let people = snapshot.people.filter(\.valid)
        if snapshot.detectionAvailable {
            add("people", "인물 배치", "검출 인물/얼굴 영역 \(people.count)개. 동일 인물 식별이나 실제 인원 수 보장은 아닙니다.")
            if let box = people.map(\.bounds).reduce(nil as CGRect?, { combined, box in combined.map { $0.union(box) } ?? box }) {
                let margin = min(box.minX, box.minY, 1 - box.maxX, 1 - box.maxY)
                add("margin", "인물 주변 여백", String(format: "검출 영역에서 가장 가까운 이미지 경계까지 %.1f%%. 머리·발끝 잘림은 원본에서도 확인하세요.", max(0, margin) * 100))
                if margin < 0.025 { add("marginTip", "가장자리 확인", "인물 영역이 가장자리에 가깝습니다. 다음 촬영에서 상하·좌우 여백을 늘리는 방안을 검토하세요.", .suggestion) }
            }
        } else { add("visionFailure", "인식 제한", "Vision 인식에 실패했습니다. 검출되지 않은 것을 대상이 없다고 해석하지 않습니다.", .limitation) }
        if let photo = snapshot.evidence.photometry {
            add("exposure", "밝기·하이라이트", String(format: "SDR 평균 휘도 %.3f, 밝은 채널 상한 근접 %.1f%%, 저휘도 %.1f%%. RAW 센서 클리핑 측정이 아닙니다.", photo.mean, photo.highlights * 100, photo.shadows * 100))
            if photo.highlights > 0.03 { add("highlightTip", "밝은 영역 조언", "SDR 밝은 영역이 상한에 가깝습니다. 다음 촬영에서 노출을 낮추되 피사체가 너무 어두워지지 않는지 확인하세요.", .suggestion) }
            add("sharpness", "선명도 참고 측정", String(format: "96px 표준 샘플의 평균 인접 경계 대비 %.4f. 피사체 질감·조명·축소의 영향을 받으며 원본 초점/흔들림을 확정하지 않습니다.", photo.edgeContrast))
            if photo.edgeContrast < 0.012 { add("sharpnessTip", "원본 확대 확인", "표준 샘플의 경계 대비가 낮습니다. 단색 장면일 수도 있으므로 원본을 확대해 초점과 흔들림을 직접 확인하세요.", .suggestion) }
            add("balance", "시각적 밝기 균형", String(format: "좌우 평균 휘도 차이 %.3f, 상하 차이 %.3f. 균형이 0에 가까워야 좋은 사진이라는 뜻은 아닙니다.", photo.leftRightDifference, photo.topBottomDifference))
            if photo.meanRGB.count == 3 {
                add("color", "색감 측정", String(format: "SDR 평균 R/G/B %.3f / %.3f / %.3f. 조명색·화이트밸런스·피사체 색을 구분하는 측정은 아닙니다.", photo.meanRGB[0], photo.meanRGB[1], photo.meanRGB[2]))
            }
        }
        if let angle = snapshot.evidence.horizonDegrees {
            add("horizon", "추정 수평 방향", String(format: "Vision 추정 방향 %.1f°. 수평선의 화면 내 높이나 실제 지평선 판별은 아닙니다.", angle))
        }
        if let convergence = snapshot.evidence.verticalConvergence {
            add("vertical", "수직·원근 참고", String(format: "검출 사각형 좌우 수직선 각도 차이 %.1f°. 건물 인식/원근 복원이 아니며 기기 롤과 다를 수 있습니다.", convergence))
        }
        if let region = snapshot.evidence.saliency.first {
            add("attention", "구도·여백", String(format: "주요 관심 영역은 화면 면적의 %.1f%%. 사물 종류·주관적 미학 점수로 해석하지 않습니다.", region.width * region.height * 100))
        }
        if let reference {
            add("intent", "촬영 전 의도", "\(reference.intent.title) · \(reference.rule.title). 촬영 시작 전 프레임과 저장 이미지의 대응을 확인합니다.")
            if let before = reference.subjectBounds, let anchor = reference.subjectAnchor, let target = reference.target,
               abs(Double(snapshot.width) / Double(max(1, snapshot.height)) / reference.imageAspect - 1) < 0.03,
               reference.personCount == people.count,
               let match = people.max(by: { overlap($0.bounds, before) < overlap($1.bounds, before) }), overlap(match.bounds, before) > 0.2,
               !reference.isFaceAnchor || match.faceCenter != nil {
                let after = match.faceCenter ?? CGPoint(x: match.bounds.midX, y: match.bounds.midY)
                let oldDistance = hypot(anchor.x - target.x, anchor.y - target.y)
                let newDistance = hypot(after.x - target.x, after.y - target.y)
                add("comparison", "촬영 전후 위치 비교", String(format: "화면 정규화 목표점 거리: 전 %.3f → 후 %.3f. 공간 대응 추정이며 동일 인물 확인/사진 품질 점수가 아닙니다.", oldDistance, newDistance))
            } else {
                add("comparisonUnavailable", "촬영 전후 비교 제한", "피사체 대응·화면 비율·랜드마크가 충분히 일치하지 않아 위치 비교를 생략했습니다.", .limitation)
            }
        }
        add("aesthetic", "평가 범위", "임의의 미학 점수는 제공하지 않습니다. 위 측정값과 촬영 의도를 함께 참고하세요. 원본은 변경하지 않습니다.", .limitation)
        return output
    }
    private static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let area = a.intersection(b)
        guard !area.isNull else { return 0 }
        let intersection = area.width * area.height
        return intersection / max(0.0001, a.width * a.height + b.width * b.height - intersection)
    }
}
