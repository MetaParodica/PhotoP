import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

enum ShootingIntent: String, Codable, CaseIterable, Identifiable, Sendable {
    case person, background, balanced, symmetry, dynamic, minimal, cinematic
    var id: String { rawValue }
    var title: String {
        switch self {
        case .person: return "인물 강조"; case .background: return "배경 강조"; case .balanced: return "인물·배경 균형"
        case .symmetry: return "대칭"; case .dynamic: return "역동적"; case .minimal: return "미니멀"; case .cinematic: return "영화 같은 프레이밍"
        }
    }
    var subjectHeight: CGFloat {
        switch self { case .person: return 0.72; case .background, .minimal: return 0.35; case .cinematic: return 0.5; default: return 0.58 }
    }
}

enum CoachCaptureMode: String, Codable, Sendable { case photo, pro, raw, longExposure, video }

enum CompositionRule: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic, center, thirds, golden, spiral, symmetryHorizontal, symmetryVertical, diagonal, triangle, circle
    case leadingLines, frameWithinFrame, negativeSpace, repetition, vanishingPoint, depthLayers
    case portraitClose, portraitHalf, portraitFull, portraitEnvironment, group, street
    case architectureFront, architectureAngle, landscape, productFood, nightLong, astro, video
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: return "자동 추천"; case .center: return "중앙"; case .thirds: return "삼분할"; case .golden: return "황금비"
        case .spiral: return "황금 나선"; case .symmetryHorizontal: return "좌우 대칭"; case .symmetryVertical: return "상하 대칭"
        case .diagonal: return "대각선"; case .triangle: return "삼각형"; case .circle: return "원형"
        case .leadingLines: return "리딩라인"; case .frameWithinFrame: return "프레임 속 프레임"; case .negativeSpace: return "여백"
        case .repetition: return "반복 패턴"; case .vanishingPoint: return "소실점"; case .depthLayers: return "전경·중경·원경"
        case .portraitClose: return "인물 클로즈업"; case .portraitHalf: return "상반신"; case .portraitFull: return "전신"
        case .portraitEnvironment: return "인물과 배경"; case .group: return "커플·단체"; case .street: return "거리 스냅"
        case .architectureFront: return "건축 정면"; case .architectureAngle: return "건축 대각선"; case .landscape: return "풍경·수평"
        case .productFood: return "제품·음식"; case .nightLong: return "장노출·야경"; case .astro: return "천체"; case .video: return "영상 프레이밍"
        }
    }
    var category: String {
        switch self {
        case .automatic: return "자동"
        case .portraitClose, .portraitHalf, .portraitFull, .portraitEnvironment, .group: return "인물"
        case .street, .architectureFront, .architectureAngle, .landscape, .productFood, .nightLong, .astro, .video: return "상황"
        default: return "기하학"
        }
    }
    var detail: String {
        switch self {
        case .automatic: return "측정된 인물 수·크기·관심 영역·직선·수평과 촬영 의도로 후보를 평가합니다."
        case .center: return "대상을 중앙에 두고 주변 여백을 비교합니다."
        case .thirds: return "얼굴/대상 중심을 삼분할 교차점에 배치합니다."
        case .golden: return "대상 중심을 0.382/0.618 비율에 배치합니다."
        case .spiral: return "자체 도식의 나선 중심으로 시선을 모읍니다. 자동 나선 인식은 아닙니다."
        case .symmetryHorizontal: return "좌우 밝기 패턴 유사도를 참고합니다. 사물의 대칭을 보증하지 않습니다."
        case .symmetryVertical: return "상하 대응을 수동으로 비교합니다. 반사면 인식은 아닙니다."
        case .diagonal: return "검출 직선 또는 수동 기준 대각선을 따라 배치합니다."
        case .triangle: return "세 대상의 위치를 삼각형 도식과 비교합니다."
        case .circle: return "중앙의 원형 도식 안에 대상을 배치합니다. 원형 사물 검출은 아닙니다."
        case .leadingLines: return "측정된 직선의 교차점 쪽으로 시선을 모읍니다."
        case .frameWithinFrame: return "실제 검출 사각형과 내부 대상 위치를 비교합니다. 창문/건물 판별은 아닙니다."
        case .negativeSpace: return "작은 대상과 큰 빈 공간의 비율을 조절합니다."
        case .repetition: return "검출된 평행 직선 또는 수동 반복선의 간격을 비교합니다."
        case .vanishingPoint: return "직선 교차점 추정을 참고합니다. 실제 3D 소실점 복원은 아닙니다."
        case .depthLayers: return "세 영역 도식으로 전경·중경·원경을 직접 구성합니다. 깊이 인식은 아닙니다."
        case .portraitClose: return "얼굴 영역과 상단 여백을 중심으로 인물을 강조합니다."
        case .portraitHalf: return "상반신 크기와 얼굴 위치를 참고합니다. 신체 절단 부위는 직접 확인하세요."
        case .portraitFull: return "전신 박스의 상하 여백을 확보합니다. 관절 검출이 있어도 발끝은 직접 확인하세요."
        case .portraitEnvironment: return "인물을 작게 배치해 배경을 함께 보여 줍니다."
        case .group: return "선택 대상이 없으면 검출 인물 전체 영역을 기준으로 중앙과 여백을 맞춥니다."
        case .street: return "거리 장면의 대상과 여백을 수동으로 선택합니다. 거리 자동 분류는 아닙니다."
        case .architectureFront: return "검출 사각형의 수직 방향과 기기 수평을 별도로 비교합니다."
        case .architectureAngle: return "사각형의 좌우 수직선 각도 차이를 참고합니다. 원근과 기기 기울기는 다릅니다."
        case .landscape: return "Vision 추정 수평 방향을 맞춥니다. 수평선 높이·하늘 영역은 판별하지 않습니다."
        case .productFood: return "중앙/여백을 수동으로 구성합니다. 관심 영역을 음식·제품으로 분류하지 않습니다."
        case .nightLong: return "장노출에서는 수평·안정적인 지지와 밝은 영역을 확인합니다."
        case .astro: return "중앙과 여백을 수동으로 정합니다. 별·천체 추적이나 식별은 제공하지 않습니다."
        case .video: return "영상 화면 비율과 대상의 가장자리 여백을 확인합니다. 저장 프레임을 자르지 않습니다."
        }
    }
    var tolerance: CGFloat { self == .group || self == .negativeSpace ? 0.06 : 0.045 }
    var manualOnly: Bool { [.spiral, .circle, .symmetryVertical, .depthLayers, .street, .productFood, .astro].contains(self) }
    var grid: GuideGrid {
        switch self {
        case .golden: return .golden; case .spiral: return .spiral; case .diagonal, .architectureAngle: return .diagonal
        case .triangle: return .triangle; case .landscape, .nightLong: return .horizon
        case .negativeSpace, .portraitEnvironment: return .negativeSpace; case .depthLayers: return .depth
        case .center, .symmetryHorizontal, .symmetryVertical, .circle, .group, .architectureFront, .productFood: return .center
        default: return .thirds
        }
    }
}

struct CompositionCandidate: Identifiable, Sendable {
    let rule: CompositionRule
    let weight: Int // ranking priority, NEVER displayed as photo quality/confidence
    let reason: String
    var id: String { rule.id }
}

struct CompositionLearning: Codable, Equatable, Sendable {
    var version = 1
    private(set) var selections: [String: Int] = [:]
    mutating func record(intent: ShootingIntent, rule: CompositionRule) {
        guard rule != .automatic else { return }
        let key = intent.rawValue + ":" + rule.rawValue
        selections[key] = min(1000, (selections[key] ?? 0) + 1)
    }
    func bonus(intent: ShootingIntent, rule: CompositionRule) -> Int {
        min(5, selections[intent.rawValue + ":" + rule.rawValue] ?? 0)
    }
    var valid: Bool {
        version == 1 && selections.count <= ShootingIntent.allCases.count * CompositionRule.allCases.count && selections.allSatisfy { key, count in
            let parts = key.split(separator: ":")
            return parts.count == 2 && ShootingIntent(rawValue: String(parts[0])) != nil &&
                CompositionRule(rawValue: String(parts[1])) != nil && (0...1000).contains(count)
        }
    }
}

enum SceneCompositionEngine {
    static func recommend(snapshot: CompositionSnapshot, intent: ShootingIntent, mode: CoachCaptureMode,
                          selected: TrackedPerson?, learning: CompositionLearning = CompositionLearning()) -> [CompositionCandidate] {
        let people = snapshot.people.filter(\.valid)
        let evidence = snapshot.evidence.isFresh(at: snapshot.generatedAt) ? snapshot.evidence : SceneEvidence()
        let subject = selected?.bounds ?? people.first?.bounds
        var output: [CompositionCandidate] = []
        func add(_ rule: CompositionRule, _ weight: Int, _ reason: String) {
            guard !rule.manualOnly else { return }
            output.append(CompositionCandidate(rule: rule, weight: weight + learning.bonus(intent: intent, rule: rule), reason: reason))
        }
        if people.count > 1 { add(.group, 80, "검출 인물 \(people.count)명의 전체 영역과 여백") }
        if let subject {
            add(.thirds, 45, "실제 인물 영역과 얼굴/영역 중심")
            if snapshot.width > snapshot.height, intent == .cinematic {
                add(.golden, 83, "가로 프레임 비율과 영화 같은 프레이밍 의도 · 검출 인물 기준")
            }
            if subject.height > 0.7 { add(.portraitFull, 68, "큰 인물 영역의 상하 여백 확인 · 전신 여부는 직접 확인") }
            else if subject.height > 0.4 { add(.portraitHalf, 65, "인물 영역이 화면 높이의 중간 비율") }
            if selected?.detection.kind == .face || people.contains(where: { $0.kind == .face }) { add(.portraitClose, 78, "실제 얼굴 영역 검출") }
            if intent == .person { add(.portraitClose, 84, "사용자가 인물 강조를 선택함 · 검출 인물 기준") }
            if intent == .background { add(.portraitEnvironment, 90, "배경 강조 의도와 실제 인물 영역") }
            if intent == .minimal || subject.width * subject.height < 0.12 { add(.negativeSpace, 75, "작은 인물 영역 또는 미니멀 의도") }
            if people.count >= 3 { add(.triangle, 50, "세 명 이상 검출 · 배치 도식은 제안") }
        } else if !evidence.saliency.isEmpty {
            add(.thirds, 45, "Vision 관심 영역 · 사물 종류 미분류")
            add(intent == .minimal ? .negativeSpace : .center, 60, "관심 영역 중심과 주변 여백")
        }
        if let angle = evidence.horizonDegrees, angle.isFinite { add(.landscape, 70, "Vision 수평 방향 측정 · 높이는 미검출") }
        if !evidence.rectangles.isEmpty {
            add(.architectureFront, 62, "사각형 가장자리 검출 · 건물 분류 아님")
            if (evidence.verticalConvergence ?? 0) > 8 { add(.architectureAngle, 72, "좌우 수직 가장자리의 각도 차이") }
            if let subject, evidence.rectangleBounds.contains(where: { $0.contains(subject) }) { add(.frameWithinFrame, 74, "검출 사각형 내부의 실제 인물 영역") }
        }
        if evidence.intersection != nil {
            add(.leadingLines, 60, "실제 영상 직선 교차점 추정")
            add(.vanishingPoint, 52, "두 개 이상 비평행 직선의 화면 내 교차점 · 3D 복원 아님")
        }
        if evidence.lines.contains(where: { (25...65).contains(abs($0.angle)) || (115...155).contains(abs($0.angle)) }) {
            add(.diagonal, intent == .dynamic ? 88 : 52, "실제 대각 방향 직선과 촬영 의도")
        }
        if evidence.lines.count >= 3 {
            let angles = evidence.lines.map { ($0.angle + 180).truncatingRemainder(dividingBy: 180) }
            if angles.contains(where: { a in angles.filter { min(abs($0 - a), 180 - abs($0 - a)) < 8 }.count >= 3 }) {
                add(.repetition, 56, "세 개 이상 유사 방향 직선 · 사물 반복/등간격 보증 아님")
            }
        }
        if let photo = evidence.photometry, photo.mirrorDifference < 0.08, photo.edgeContrast > 0.015 {
            add(.symmetryHorizontal, intent == .symmetry ? 91 : 54, "좌우 밝기 패턴 차이가 작음 · 사물 대칭 보증 아님")
        }
        if intent == .symmetry, subject != nil { add(.center, 85, "대칭 의도에 맞춘 중앙 배치 제안") }
        if mode == .longExposure { add(.nightLong, 95, "현재 LONG 모드 · 센서 장노출 시간과 구분") }
        if mode == .video { add(.video, intent == .cinematic ? 96 : 76, "현재 영상 모드와 실제 프레임 비율") }
        if output.isEmpty { add(.center, 10, "인식 근거 부족 · 중앙 기준 수동 안내, 대상 분류/확신 없음") }
        return output.sorted { $0.weight == $1.weight ? $0.rule.rawValue < $1.rule.rawValue : $0.weight > $1.weight }
    }

    static func anchor(rule: CompositionRule, point: CGPoint, side: CompositionTarget, region: CGRect) -> CGPoint {
        let x: CGFloat
        switch side { case .left: x = 1.0 / 3; case .right: x = 2.0 / 3; case .automatic: x = point.x < region.midX ? 1.0 / 3 : 2.0 / 3 }
        var local = CGPoint(x: x, y: 1.0 / 3)
        switch rule {
        case .center, .symmetryHorizontal, .symmetryVertical, .circle, .group, .productFood, .architectureFront, .astro:
            local = CGPoint(x: 0.5, y: 0.5)
        case .golden, .spiral: local = CGPoint(x: x < 0.5 ? 0.381966 : 0.618034, y: 0.381966)
        case .portraitFull: local.y = 0.22
        case .triangle, .diagonal, .video: local.y = 0.4
        default: break
        }
        return CGPoint(x: region.minX + local.x * region.width, y: region.minY + local.y * region.height)
    }
}
