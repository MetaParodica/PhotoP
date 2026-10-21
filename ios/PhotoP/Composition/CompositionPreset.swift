import CoreGraphics
import Foundation

// Annotated composition presets: thirds grid, dashed subject zones, points of interest, connecting
// lines and handwritten-style notes. Coordinates are normalized to the 3:4 frame, top-left origin.
// All shapes and copy are PhotoP's own; no third-party guide artwork is bundled.
enum GuideMark: Equatable, Sendable {
    case zone(CGRect)                                   // dashed rectangle where the subject sits
    case point(CGPoint, radius: CGFloat)                // dashed circle; radius in frame-width units
    case line([CGPoint], closed: Bool)                  // dashed connecting path
    case note(String, at: CGPoint, arrowTo: CGPoint?)   // handwritten note with an optional curved arrow
}

struct CompositionPreset: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let category: String
    let detail: String
    var thirds = true
    let marks: [GuideMark]

    // The zone a person should fill, used for live Vision feedback.
    var subject: CGRect? {
        guard category == "인물" else { return nil }
        for mark in marks { if case .zone(let rect) = mark { return rect } }
        return nil
    }

    // Compare a Vision body (bottom-left origin) with the subject zone. Directions are frame-relative.
    func feedback(body: [String: CGPoint]) -> String? {
        guard let zone = subject else { return nil }
        let points = body.values.map { CGPoint(x: $0.x, y: 1 - $0.y) }
        guard points.count >= 3, let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { return nil }
        // Joints run from the nose to the ankles, roughly 85% of a standing person.
        let height = (maxY - minY) / 0.85
        guard height > 0.02 else { return nil }
        if height < zone.height * 0.6 { return "인물을 더 크게: 가까이 가거나 줌을 올리세요." }
        if height > zone.height * 1.2 { return "인물을 더 작게: 한 걸음 뒤로 가거나 줌을 낮추세요." }
        let dx = (minX + maxX) / 2 - zone.midX
        if dx < -0.06 { return "인물을 점선 영역 오른쪽으로 옮기세요." }
        if dx > 0.06 { return "인물을 점선 영역 왼쪽으로 옮기세요." }
        let top = minY - height * 0.08
        if top < zone.minY - 0.06 { return "인물을 화면 아래쪽으로 옮기세요." }
        if top > zone.minY + 0.08 { return "인물을 화면 위쪽으로 옮기세요." }
        return "점선 영역과 맞습니다. 촬영하세요."
    }

    static let all: [CompositionPreset] = [
        .init(id: "portrait-two-thirds", title: "인물 2/3", category: "인물", detail: "앉은 인물을 가운데 칸 아래 2/3에 두고 배경 포인트를 위쪽 교차점에",
              marks: [.zone(.init(x: 0.36, y: 0.36, width: 0.28, height: 0.6)), .point(.init(x: 0.86, y: 0.25), radius: 0.05),
                      .note("시선 포인트\n2/3 구도", at: .init(x: 0.74, y: 0.17), arrowTo: .init(x: 0.58, y: 0.31))]),
        .init(id: "portrait-eye-line", title: "눈높이 1/3", category: "인물", detail: "눈을 위쪽 1/3 선에 맞추는 반신",
              marks: [.zone(.init(x: 0.35, y: 0.18, width: 0.3, height: 0.82)), .point(.init(x: 0.5, y: 1.0 / 3), radius: 0.035),
                      .note("눈을 위쪽 1/3 선에", at: .init(x: 0.5, y: 0.1), arrowTo: .init(x: 0.44, y: 0.31))]),
        .init(id: "portrait-left", title: "왼쪽 전신", category: "인물", detail: "왼쪽 1/3에 전신, 시선 방향으로 여백",
              marks: [.zone(.init(x: 0.2, y: 0.12, width: 0.27, height: 0.84)),
                      .note("시선 방향에 여백", at: .init(x: 0.72, y: 0.42), arrowTo: .init(x: 0.52, y: 0.42))]),
        .init(id: "portrait-right", title: "오른쪽 전신", category: "인물", detail: "오른쪽 1/3에 전신, 반대편을 여백으로",
              marks: [.zone(.init(x: 0.53, y: 0.12, width: 0.27, height: 0.84)),
                      .note("배경을 여백으로", at: .init(x: 0.28, y: 0.42), arrowTo: .init(x: 0.48, y: 0.42))]),
        .init(id: "portrait-landmark", title: "인물+랜드마크", category: "인물", detail: "랜드마크를 크게, 인물은 작게 아래 1/3에",
              marks: [.point(.init(x: 0.5, y: 0.34), radius: 0.2), .zone(.init(x: 0.45, y: 0.64, width: 0.1, height: 0.22)),
                      .note("인물은 작게", at: .init(x: 0.78, y: 0.7), arrowTo: .init(x: 0.57, y: 0.72))]),
        .init(id: "still-triangle", title: "삼각 구도", category: "음식·정물", detail: "세 피사체를 이어 삼각형을 만드는 탑뷰",
              marks: [.point(.init(x: 0.3, y: 0.36), radius: 0.06), .point(.init(x: 0.64, y: 0.29), radius: 0.06), .point(.init(x: 0.62, y: 0.7), radius: 0.06),
                      .line([.init(x: 0.3, y: 0.36), .init(x: 0.64, y: 0.29), .init(x: 0.62, y: 0.7)], closed: true),
                      .note("시선 포인트\n삼각 구도", at: .init(x: 0.5, y: 0.13), arrowTo: .init(x: 0.62, y: 0.24))]),
        .init(id: "still-vertical-triangle", title: "세로 삼각", category: "음식·정물", detail: "벽·선반·컵 세 점을 세로로 연결",
              marks: [.point(.init(x: 0.42, y: 0.13), radius: 0.05), .point(.init(x: 0.62, y: 0.5), radius: 0.05), .point(.init(x: 0.38, y: 0.76), radius: 0.05),
                      .line([.init(x: 0.42, y: 0.13), .init(x: 0.62, y: 0.5), .init(x: 0.38, y: 0.76)], closed: true),
                      .note("세 점을 잇는 시선", at: .init(x: 0.76, y: 0.3), arrowTo: .init(x: 0.6, y: 0.44))]),
        .init(id: "still-diagonal", title: "대각 포인트", category: "음식·정물", detail: "두 주제를 대각선 교차점에",
              marks: [.point(.init(x: 1.0 / 3, y: 1.0 / 3), radius: 0.09), .point(.init(x: 2.0 / 3, y: 2.0 / 3), radius: 0.09),
                      .line([.init(x: 1.0 / 3, y: 1.0 / 3), .init(x: 2.0 / 3, y: 2.0 / 3)], closed: false),
                      .note("시선 포인트", at: .init(x: 0.24, y: 0.58), arrowTo: .init(x: 0.58, y: 0.66))]),
        .init(id: "space-light", title: "조명 삼각", category: "공간", detail: "조명과 두 소품을 잇는 실내 구도",
              marks: [.point(.init(x: 0.5, y: 0.1), radius: 0.04), .point(.init(x: 0.32, y: 0.6), radius: 0.05), .point(.init(x: 0.74, y: 0.74), radius: 0.05),
                      .line([.init(x: 0.5, y: 0.1), .init(x: 0.32, y: 0.6), .init(x: 0.74, y: 0.74)], closed: true)]),
        .init(id: "landscape-reflection", title: "반영", category: "풍경", detail: "수평선을 가운데에 두고 반영을 점선 영역에",
              marks: [.line([.init(x: 0, y: 0.5), .init(x: 1, y: 0.5)], closed: false), .zone(.init(x: 0.4, y: 0.52, width: 0.27, height: 0.32)),
                      .note("반영을 액자처럼", at: .init(x: 0.76, y: 0.3), arrowTo: .init(x: 0.6, y: 0.46))]),
        .init(id: "landscape-horizon", title: "하늘 2/3", category: "풍경", detail: "수평선을 아래 1/3 선에",
              marks: [.line([.init(x: 0, y: 2.0 / 3), .init(x: 1, y: 2.0 / 3)], closed: false),
                      .note("하늘 2/3 · 땅 1/3", at: .init(x: 0.5, y: 0.5), arrowTo: .init(x: 0.5, y: 0.64))]),
        .init(id: "landscape-frame", title: "프레임 속 프레임", category: "풍경", detail: "아치·문·창을 액자로 사용", thirds: false,
              marks: [.point(.init(x: 0.5, y: 0.6), radius: 0.42),
                      .note("아치를 액자로", at: .init(x: 0.5, y: 0.1), arrowTo: .init(x: 0.5, y: 0.26))]),
    ]

    static func preset(_ id: String?) -> CompositionPreset? { id.flatMap { id in all.first { $0.id == id } } }
}
