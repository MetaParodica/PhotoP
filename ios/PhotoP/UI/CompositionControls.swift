import SwiftUI

@MainActor
struct CompositionControls: View {
    @ObservedObject var model: CameraModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Picker("구도선", selection: $model.guideGrid) { ForEach(GuideGrid.allCases) { Text($0.title).tag($0) } }
                Slider(value: $model.guideOpacity, in: 0.1...1) { Text("가이드 투명도") }
                Picker("장면", selection: $model.guideScene) { ForEach(GuideScene.allCases) { Text($0.title).tag($0) } }
                Picker("목표 포즈 · 직접 그린 도식", selection: $model.poseTemplate) { ForEach(PoseTemplate.allCases) { Text($0.title).tag($0) } }
                AICompositionControls(model: model)
                Button("AI 프리뷰 시작 · 적용") { Task { await model.enableMonitoring() } }
                    .disabled(!model.guideAIEnabled || model.busy || model.snapshot.state != .running)
                Button("AI·노출 보조 끄기 · 선택 룩 유지") { model.disableLiveLUT() }.disabled(model.busy || model.livePreview == nil)
                Text("흰 선은 목표 구도, 노란 도식은 목표 포즈, 청록 표시는 실제 Vision 검출 결과입니다. AI는 제안이며 정답이나 점수가 아닙니다. 이미지 서버 전송은 하지 않습니다.").font(.caption)
                Text("인물 분석은 최대 5Hz·640px·1작업으로 처리하며 오래된 결과를 숨깁니다. 발열·저전력 시 빈도를 낮추거나 중지합니다. 추적은 위치 기반으로, 겹침·가림 후 동일 인물을 보장하지 않습니다.").font(.caption)
                if let snapshot = model.composition { Text(snapshot.advice).font(.caption) }
                if let message = model.message { Text(message).font(.caption) }
            }
            .navigationTitle("구도 가이드")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() } } }
            .onChange(of: model.guideGrid) { _, _ in model.showGrid = false }
            .onChange(of: model.guideAIEnabled) { _, _ in model.updateComposition() }
            .onChange(of: model.guideScene) { _, _ in model.updateComposition() }
        }.preferredColorScheme(.dark)
    }
}

struct CompositionOverlay: View {
    let grid: GuideGrid
    let pose: PoseTemplate
    let opacity: Double
    let snapshot: CompositionSnapshot?
    let live: Bool
    let sourceSize: CGSize?
    var fill = false
    var showsAdvice = true
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            GeometryReader { geometry in
                let fresh = snapshot.flatMap { $0.isFresh(at: ProcessInfo.processInfo.systemUptime) ? $0 : nil }
                let imageSize = sourceSize ?? CGSize(width: 3, height: 4)
                let rect = GuideGeometry.imageRect(image: imageSize, viewport: geometry.size, fill: fill)
                Canvas { context, _ in
                    func map(_ point: CGPoint, vision: Bool = false) -> CGPoint { GuideGeometry.point(point, in: rect, vision: vision) }
                    func line(_ a: CGPoint, _ b: CGPoint, color: Color = .white) {
                        var p = Path(); p.move(to: map(a)); p.addLine(to: map(b)); context.stroke(p, with: .color(color.opacity(opacity)), lineWidth: 1)
                    }
                    switch grid {
                    case .off: break
                    case .thirds, .golden:
                        let divisions: [CGFloat] = grid == .thirds ? [1 / 3, 2 / 3] : [0.381966, 0.618034]
                        for x in divisions { line(.init(x: x, y: 0), .init(x: x, y: 1)); line(.init(x: 0, y: x), .init(x: 1, y: x)) }
                    case .center: line(.init(x: 0.5, y: 0), .init(x: 0.5, y: 1)); line(.init(x: 0, y: 0.5), .init(x: 1, y: 0.5))
                    case .diagonal: line(.zero, .init(x: 1, y: 1)); line(.init(x: 1, y: 0), .init(x: 0, y: 1))
                    case .triangle:
                        line(.zero, .init(x: 1, y: 1))
                        let d = rect.width * rect.width + rect.height * rect.height
                        if d > 0 {
                            let a = rect.width * rect.width / d, b = rect.height * rect.height / d
                            line(.init(x: 1, y: 0), .init(x: a, y: a)); line(.init(x: 0, y: 1), .init(x: b, y: b))
                        }
                    case .horizon, .depth:
                        for y: CGFloat in [1 / 3, 2 / 3] { line(.init(x: 0, y: y), .init(x: 1, y: y)) }
                    case .negativeSpace: line(.init(x: 1 / 3, y: 0), .init(x: 1 / 3, y: 1))
                    case .spiral:
                        var p = Path()
                        for i in 0...240 {
                            let angle = Double(i) / 240 * 4 * Double.pi, r = 0.008 * pow(1.618034, angle / (.pi / 2))
                            let point = map(.init(x: 0.618 + r * cos(angle), y: 0.618 + r * sin(angle)))
                            if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
                        }
                        context.stroke(p, with: .color(.white.opacity(opacity)), lineWidth: 1)
                    }
                    func skeleton(_ body: [String: CGPoint], vision: Bool, color: Color) {
                        for (a, b) in PoseTemplate.bones {
                            guard let first = body[a], let last = body[b] else { continue }
                            var p = Path(); p.move(to: map(first, vision: vision)); p.addLine(to: map(last, vision: vision))
                            context.stroke(p, with: .color(color.opacity(opacity)), lineWidth: 2)
                        }
                    }
                    for target in pose.targets { skeleton(target, vision: false, color: .yellow) }
                    if live, let fresh {
                        for body in fresh.bodies { skeleton(body, vision: true, color: .cyan) }
                        for polygon in fresh.polygons where polygon.count >= 3 {
                            var p = Path(); p.move(to: map(polygon[0], vision: true))
                            for point in polygon.dropFirst() { p.addLine(to: map(point, vision: true)) }; p.closeSubpath()
                            context.stroke(p, with: .color(.cyan.opacity(opacity)), lineWidth: 2)
                        }
                    }
                }
                if showsAdvice, live, let fresh { Text(fresh.advice).font(.caption2).padding(5).background(.black.opacity(0.65)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom) }
            }
        }.allowsHitTesting(false).accessibilityLabel("흰 목표 구도선, 노란 목표 포즈와 청록 AI 검출 가이드")
    }
}
