import CoreGraphics
import Foundation

// Silhouette placement guides for people. Shapes are original schematic drawings, not detected people.
enum PersonFraming: String, CaseIterable, Identifiable, Sendable {
    case off, full, knee, waist, chest, face
    var id: String { rawValue }
    var title: String {
        switch self { case .off: return "없음"; case .full: return "전신"; case .knee: return "무릎 위"; case .waist: return "허리 위"
        case .chest: return "가슴 위"; case .face: return "얼굴" }
    }
    // Figure units: head top 0, feet 1. `cut` is the lowest figure height shown at the frame bottom.
    var cut: CGFloat { switch self { case .off, .full: return 1; case .knee: return 0.8; case .waist: return 0.52; case .chest: return 0.34; case .face: return 0.2 } }
    var headroom: CGFloat { switch self { case .off, .full: return 0.06; case .knee: return 0.07; case .waist: return 0.08; case .chest: return 0.1; case .face: return 0.1 } }
    var tip: String {
        switch self {
        case .off: return ""
        case .full: return "발끝을 화면 아래 끝에 맞추고 카메라를 허리 높이로 낮추면 다리가 길어 보입니다."
        case .knee: return "무릎 바로 위가 아닌 허벅지 중간 또는 무릎 아래에서 자르면 자연스럽습니다."
        case .waist: return "팔꿈치·손목 관절에 화면 끝이 걸리지 않게 여백을 두세요."
        case .chest: return "눈을 위쪽 1/3 선에 두고 머리 위 여백은 좁게 유지하세요."
        case .face: return "눈높이에서 촬영하고 시선 방향에 여백을 남기세요."
        }
    }
}

enum PersonPosition: String, CaseIterable, Identifiable, Sendable {
    case left, center, right
    var id: String { rawValue }
    var title: String { switch self { case .left: return "왼쪽 1/3"; case .center: return "중앙"; case .right: return "오른쪽 1/3" } }
    var x: CGFloat { switch self { case .left: return 1.0 / 3; case .center: return 0.5; case .right: return 2.0 / 3 } }
}

struct PersonGuide: Equatable, Sendable {
    var framing: PersonFraming = .off
    var position: PersonPosition = .center
    var people = 1

    // Figure landmarks in figure units (x: 0 is the body centre, positive to the figure's left of frame right).
    static let noseY: CGFloat = 0.075
    static let eyeY: CGFloat = 0.06
    static let shoulderY: CGFloat = 0.18
    static let shoulderHalfWidth: CGFloat = 0.115
    static let ankleY: CGFloat = 0.96

    // Right half of the outline from head base to feet; mirrored for the left half.
    static let outline: [CGPoint] = [
        .init(x: 0.028, y: 0.128), .init(x: 0.03, y: 0.15), .init(x: 0.1, y: 0.165), .init(x: 0.125, y: 0.19),
        .init(x: 0.135, y: 0.3), .init(x: 0.15, y: 0.47), .init(x: 0.13, y: 0.5), .init(x: 0.11, y: 0.35),
        .init(x: 0.095, y: 0.42), .init(x: 0.11, y: 0.52), .init(x: 0.09, y: 0.75), .init(x: 0.085, y: 0.97),
        .init(x: 0.105, y: 1), .init(x: 0.03, y: 1), .init(x: 0.03, y: 0.75), .init(x: 0.012, y: 0.55), .init(x: 0, y: 0.54)]

    struct Placement: Equatable, Sendable {
        let centerX: CGFloat
        let top: CGFloat        // frame y of head top
        let scale: CGFloat      // frame height per figure unit
        let widthScale: CGFloat // frame width per figure unit
        func point(_ figure: CGPoint) -> CGPoint { .init(x: centerX + figure.x * widthScale, y: top + figure.y * scale) }
        var noseY: CGFloat { top + PersonGuide.noseY * scale }
        var eyeY: CGFloat { top + PersonGuide.eyeY * scale }
        var shoulderWidth: CGFloat { 2 * PersonGuide.shoulderHalfWidth * widthScale }
    }

    // Placement in normalized frame coordinates (top-left origin) for a frame of width/height `aspect`.
    func placements(aspect: CGFloat = 3.0 / 4.0) -> [Placement] {
        guard framing != .off, aspect > 0 else { return [] }
        let scale = framing == .full ? (0.95 - framing.headroom) / PersonGuide.ankleY : (1 - framing.headroom) / framing.cut
        let count = max(1, min(people, 3))
        let shrink: CGFloat = count == 1 ? 1 : (count == 2 ? 0.92 : 0.82)
        let s = scale * shrink
        let widthScale = s / aspect
        let spacing = min(0.3, 2.2 * PersonGuide.shoulderHalfWidth * widthScale)
        let first = position.x - spacing * CGFloat(count - 1) / 2
        return (0..<count).map { index in
            Placement(centerX: min(max(first + spacing * CGFloat(index), 0.1), 0.9), top: framing.headroom, scale: s, widthScale: widthScale)
        }
    }

    // Compare a Vision body (normalized, bottom-left origin) with the first target. Directions are frame-relative.
    func feedback(body: [String: CGPoint], aspect: CGFloat = 3.0 / 4.0) -> String? {
        guard let target = placements(aspect: aspect).first,
              let ls = body["ls"], let rs = body["rs"] else { return nil }
        let width = abs(ls.x - rs.x)
        guard width > 0.01 else { return nil }
        // Close-ups put the shoulders outside the frame, so only position is compared there.
        if target.shoulderWidth < 0.9 {
            let ratio = width / target.shoulderWidth
            if ratio < 0.8 { return "인물을 더 크게: 가까이 가거나 줌을 올리세요." }
            if ratio > 1.25 { return "인물을 더 작게: 한 걸음 뒤로 가거나 줌을 낮추세요." }
        }
        let centerX = body["nose"].map { $0.x } ?? (ls.x + rs.x) / 2
        let dx = centerX - target.centerX
        if dx < -0.06 { return "인물을 화면 오른쪽으로 옮기세요." }
        if dx > 0.06 { return "인물을 화면 왼쪽으로 옮기세요." }
        if let nose = body["nose"] {
            let dy = (1 - nose.y) - target.noseY
            if dy < -0.05 { return "인물을 화면 아래쪽으로 옮기세요." }
            if dy > 0.05 { return "인물을 화면 위쪽으로 옮기세요." }
        }
        return "가이드와 맞습니다. 촬영하세요."
    }
}
