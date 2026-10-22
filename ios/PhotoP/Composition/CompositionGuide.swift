import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

enum GuideScene: String, CaseIterable, Identifiable, Sendable {
    case general, portrait, architecture, landscape
    var id: String { rawValue }
    var title: String { switch self { case .general: return "일반"; case .portrait: return "인물"; case .architecture: return "건축"; case .landscape: return "풍경" } }
}
enum GuideGrid: String, CaseIterable, Identifiable {
    case off, thirds, golden, diagonal, center, spiral, triangle, horizon, negativeSpace, depth
    var id: String { rawValue }
    var title: String {
        switch self { case .off: return "숨기기"; case .thirds: return "삼분할"; case .golden: return "황금비"; case .diagonal: return "대각선"
        case .center: return "중앙 대칭"; case .spiral: return "황금 나선"; case .triangle: return "황금 삼각형"
        case .horizon: return "수평선 1/3"; case .negativeSpace: return "네거티브 스페이스"; case .depth: return "전경·중경·후경" }
    }
}
enum PoseTemplate: String, CaseIterable, Identifiable {
    case off, full, half, closeup, pair, group, seated, walking, profile, background
    var id: String { rawValue }
    var title: String {
        switch self { case .off: return "없음"; case .full: return "전신"; case .half: return "반신"; case .closeup: return "클로즈업"
        case .pair: return "2인"; case .group: return "단체"; case .seated: return "앉기"; case .walking: return "걷기"
        case .profile: return "측면"; case .background: return "배경 활용" }
    }
    // Independently drawn schematic targets. These are not detected people.
    var targets: [[String: CGPoint]] {
        guard self != .off else { return [] }
        var body: [String: CGPoint] = ["nose": .init(x: 0.5, y: 0.15), "neck": .init(x: 0.5, y: 0.24),
            "ls": .init(x: 0.37, y: 0.26), "rs": .init(x: 0.63, y: 0.26), "le": .init(x: 0.31, y: 0.43), "re": .init(x: 0.69, y: 0.43),
            "lw": .init(x: 0.29, y: 0.57), "rw": .init(x: 0.71, y: 0.57), "lh": .init(x: 0.43, y: 0.54), "rh": .init(x: 0.57, y: 0.54),
            "lk": .init(x: 0.42, y: 0.72), "rk": .init(x: 0.58, y: 0.72), "la": .init(x: 0.4, y: 0.92), "ra": .init(x: 0.6, y: 0.92)]
        if self == .seated { body["lk"] = .init(x: 0.3, y: 0.65); body["rk"] = .init(x: 0.7, y: 0.65) }
        if self == .walking { body["la"] = .init(x: 0.24, y: 0.93); body["ra"] = .init(x: 0.68, y: 0.86); body["rw"] = .init(x: 0.58, y: 0.5) }
        if self == .half || self == .closeup {
            body = body.filter { !["lk", "rk", "la", "ra"].contains($0.key) }
            if self == .closeup { body = body.filter { ["nose", "neck", "ls", "rs"].contains($0.key) }.mapValues { CGPoint(x: 0.5 + ($0.x - 0.5) * 2.5, y: ($0.y - 0.1) * 4) } }
        }
        if self == .profile { body = body.mapValues { CGPoint(x: 0.5 + ($0.x - 0.5) * 0.3, y: $0.y) } }
        let centers: [CGFloat] = self == .pair ? [0.28, 0.72] : (self == .group ? [0.18, 0.5, 0.82] : (self == .background ? [0.33] : [0.5]))
        let scale: CGFloat = self == .group ? 0.45 : (self == .pair ? 0.65 : (self == .background ? 0.6 : 1))
        return centers.map { center in body.mapValues { CGPoint(x: center + ($0.x - 0.5) * scale, y: $0.y) } }
    }
    static let bones = [("nose", "neck"), ("neck", "ls"), ("neck", "rs"), ("ls", "le"), ("le", "lw"),
                        ("rs", "re"), ("re", "rw"), ("ls", "lh"), ("rs", "rh"), ("lh", "rh"),
                        ("lh", "lk"), ("lk", "la"), ("rh", "rk"), ("rk", "ra")]
}

struct CompositionSnapshot: Sendable {
    let id = UUID()
    let generatedAt: Double
    let width: Int
    let height: Int
    let bodies: [[String: CGPoint]] // Vision normalized, bottom-left origin.
    let polygons: [[CGPoint]]
    let advice: String
    var epoch: UInt64 = 0
    var people: [DetectedPerson] = []
    var evidence = SceneEvidence()
    var peopleAnalysisMessage = "인물을 찾지 못했습니다. 인물이 보이도록 프레임을 조절하세요."
    var detectionAvailable = true
    func isFresh(at time: Double) -> Bool { time >= generatedAt && time - generatedAt <= 0.65 }
}

enum GuideGeometry {
    static func visibleRegion(image: CGSize, viewport: CGSize, fill: Bool) -> CGRect {
        let rect = imageRect(image: image, viewport: viewport, fill: fill)
        guard rect.width > 0, rect.height > 0 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        let visible = rect.intersection(CGRect(origin: .zero, size: viewport))
        return CGRect(x: (visible.minX - rect.minX) / rect.width, y: (visible.minY - rect.minY) / rect.height,
                      width: visible.width / rect.width, height: visible.height / rect.height)
    }
    static func normalizedPoint(_ point: CGPoint, in rect: CGRect) -> CGPoint? {
        guard rect.width > 0, rect.height > 0, point.x.isFinite, point.y.isFinite, rect.contains(point) else { return nil }
        return CGPoint(x: (point.x - rect.minX) / rect.width, y: (point.y - rect.minY) / rect.height)
    }
    static func imageRect(image: CGSize, viewport: CGSize, fill: Bool = false) -> CGRect {
        guard image.width > 0, image.height > 0, viewport.width > 0, viewport.height > 0 else { return .zero }
        let x = viewport.width / image.width, y = viewport.height / image.height
        let scale = fill ? max(x, y) : min(x, y)
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        return CGRect(x: (viewport.width - size.width) / 2, y: (viewport.height - size.height) / 2, width: size.width, height: size.height)
    }
    static func point(_ p: CGPoint, in rect: CGRect, vision: Bool, mirror: Bool = false) -> CGPoint {
        CGPoint(x: rect.minX + (mirror ? 1 - p.x : p.x) * rect.width,
                y: rect.minY + (vision ? 1 - p.y : p.y) * rect.height)
    }
    static func portraitAdvice(_ bodies: [[String: CGPoint]]) -> String {
        guard let body = bodies.first else { return "신뢰할 수 있는 인물 관절이 없습니다." }
        if bodies.count > 1 { return "여러 인물의 여백·간격을 확인해 보세요." }
        if let nose = body["nose"], nose.y > 0.92 { return "머리 위 여백을 조금 늘려 보세요." }
        if ["la", "ra"].compactMap({ body[$0] }).contains(where: { $0.y < 0.04 }) { return "발 아래 여백을 조금 늘려 보세요." }
        return "관절 경계와 시선 방향의 여백을 확인해 보세요."
    }
}
