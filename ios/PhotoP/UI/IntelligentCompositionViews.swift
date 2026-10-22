import SwiftUI

// Original diagrams only. These schematic paths do not represent detections.
enum CompositionRuleDrawing {
    static func path(_ rule: CompositionRule, in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        var path = Path()
        func line(_ x: CGFloat, _ y: CGFloat, _ xx: CGFloat, _ yy: CGFloat) { path.move(to: point(x, y)); path.addLine(to: point(xx, yy)) }
        switch rule {
        case .center, .symmetryHorizontal, .symmetryVertical, .astro, .architectureFront, .productFood:
            line(0.5, 0, 0.5, 1); line(0, 0.5, 1, 0.5)
        case .circle:
            path.addEllipse(in: CGRect(x: rect.minX + rect.width * 0.17, y: rect.minY + rect.height * 0.17, width: rect.width * 0.66, height: rect.height * 0.66))
        case .diagonal, .architectureAngle: line(0, 0, 1, 1); line(1, 0, 0, 1)
        case .triangle: line(0.5, 0.2, 0.2, 0.8); line(0.2, 0.8, 0.8, 0.8); line(0.8, 0.8, 0.5, 0.2)
        case .spiral:
            for i in 0...180 {
                let angle = Double(i) / 180 * 3.5 * Double.pi
                let radius = 0.008 * pow(1.618034, angle / (.pi / 2))
                let p = point(0.618 + radius * cos(angle), 0.382 + radius * sin(angle))
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
        case .leadingLines, .vanishingPoint:
            for x: CGFloat in [0, 0.3, 0.7, 1] { line(x, 1, 0.5, 0.4) }
        case .frameWithinFrame:
            path.addRect(CGRect(x: rect.minX + rect.width * 0.2, y: rect.minY + rect.height * 0.18, width: rect.width * 0.6, height: rect.height * 0.64))
        case .repetition: for x: CGFloat in [0.2, 0.4, 0.6, 0.8] { line(x, 0.1, x, 0.9) }
        case .negativeSpace, .portraitEnvironment: line(1 / 3, 0, 1 / 3, 1)
        case .landscape, .nightLong, .depthLayers:
            line(0, 1 / 3, 1, 1 / 3); line(0, 2 / 3, 1, 2 / 3)
        case .portraitClose:
            path.addEllipse(in: CGRect(x: rect.minX + rect.width * 0.25, y: rect.minY + rect.height * 0.1, width: rect.width * 0.5, height: rect.height * 0.55))
        case .portraitHalf, .portraitFull:
            let height: CGFloat = rule == .portraitFull ? 0.85 : 0.65
            path.addRect(CGRect(x: rect.minX + rect.width * 0.3, y: rect.minY + rect.height * 0.07, width: rect.width * 0.4, height: rect.height * height))
        case .group:
            for x: CGFloat in [0.15, 0.4, 0.65] { path.addRect(CGRect(x: rect.minX + rect.width * x, y: rect.minY + rect.height * 0.25, width: rect.width * 0.2, height: rect.height * 0.5)) }
        case .video:
            line(0, 0.12, 1, 0.12); line(0, 0.88, 1, 0.88); line(1 / 3, 0.12, 1 / 3, 0.88); line(2 / 3, 0.12, 2 / 3, 0.88)
        default:
            let divisions: [CGFloat] = rule == .golden ? [0.381966, 0.618034] : [1 / 3, 2 / 3]
            for d in divisions { line(d, 0, d, 1); line(0, d, 1, d) }
        }
        return path
    }
}

struct IntelligentRuleOverlay: View {
    let rule: CompositionRule
    let sourceSize: CGSize
    let fill: Bool
    let guide: LiveCompositionGuide?
    let opacity: Double
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, _ in
                let image = GuideGeometry.imageRect(image: sourceSize, viewport: geometry.size, fill: fill)
                let region = guide?.framingRegion ?? GuideGeometry.visibleRegion(image: sourceSize, viewport: geometry.size, fill: fill)
                let rect = CGRect(x: image.minX + region.minX * image.width, y: image.minY + region.minY * image.height,
                                  width: region.width * image.width, height: region.height * image.height)
                var c = context; c.clip(to: Path(CGRect(origin: .zero, size: geometry.size)))
                c.stroke(CompositionRuleDrawing.path(rule, in: rect), with: .color(.white.opacity(opacity * 0.65)), style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
                if let guide, guide.evidence.isFresh(at: ProcessInfo.processInfo.systemUptime) {
                    for line in guide.evidence.lines {
                        var p = Path(); p.move(to: GuideGeometry.point(line.start, in: image, vision: false)); p.addLine(to: GuideGeometry.point(line.end, in: image, vision: false))
                        c.stroke(p, with: .color(.cyan.opacity(opacity * 0.55)), lineWidth: 1)
                    }
                    if let angle = guide.evidence.horizonDegrees {
                        // Measured DIRECTION through screen centre, not a claimed
                        // detected horizon height or a sky segmentation boundary.
                        let dy = CGFloat(tan(angle * .pi / 180)) * rect.width / 2
                        var p = Path(); p.move(to: CGPoint(x: rect.minX, y: rect.midY - dy)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY + dy))
                        c.stroke(p, with: .color(.cyan.opacity(opacity)), lineWidth: 1.5)
                    }
                }
            }
        }.allowsHitTesting(false).accessibilityLabel("\(rule.title) 기준 도식. 청록은 측정 직선과 수평 방향이며 수평선 높이가 아닙니다.")
    }
}

@MainActor
struct CompositionLibraryView: View {
    @ObservedObject var model: CameraModel
    @Environment(\.dismiss) private var dismiss
    @State private var category = "전체"
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    CameraChoice(title: "촬영 의도", selection: $model.shootingIntent, values: ShootingIntent.allCases,
                                 identifier: "camera.ai.intent", key: { $0.id }, label: { $0.title })
                    Picker("분류", selection: $category) { ForEach(["전체", "자동", "기하학", "인물", "상황"], id: \.self) { Text($0) } }.pickerStyle(.segmented)
                    Text("자체 제작 도식입니다. 자동 추천은 측정 근거가 있는 후보만 사용하며, 수동 선택을 사물 인식으로 가장하지 않습니다.").font(.caption)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 145))], spacing: 12) {
                        ForEach(CompositionRule.allCases.filter { category == "전체" || $0.category == category }) { rule in
                            Button { model.selectIntelligentRule(rule); dismiss() } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Canvas { context, size in
                                        context.stroke(CompositionRuleDrawing.path(rule, in: CGRect(origin: .zero, size: size).insetBy(dx: 5, dy: 5)), with: .color(.white), lineWidth: 1)
                                    }.frame(height: 76).background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
                                    Text(rule.title).font(.headline)
                                    Text(rule.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(4)
                                    if rule.manualOnly { Text("수동 도식").font(.caption2) }
                                }.padding(10).frame(maxWidth: .infinity, alignment: .leading).cameraGlass(radius: 14)
                            }.buttonStyle(.plain).accessibilityIdentifier("camera.ai.rule.\(rule.id)")
                                .accessibilityAddTraits(model.intelligentRule == rule ? .isSelected : [])
                        }
                    }
                }.padding()
            }.navigationTitle("AI 구도 라이브러리")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() } } }
        }.preferredColorScheme(.dark)
    }
}

@MainActor
struct CameraCoachBar: View {
    @ObservedObject var model: CameraModel
    let onExposure: () -> Void
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let now = ProcessInfo.processInfo.systemUptime
            let result = model.cameraCoach.flatMap { $0.isFresh(at: now) ? $0 : nil }
            VStack(alignment: .leading, spacing: 4) {
                if let message = result?.advice.first { Text(message.message).font(.caption2).lineLimit(3) }
                HStack(spacing: 8) {
                    if let zoom = result?.advice.compactMap(\.zoom).first {
                        Button { model.applyCoachZoom() } label: { Label(zoom.lensID == nil ? String(format: "%.1f× 제안", zoom.factor) : "렌즈 제안", systemImage: "plus.magnifyingglass") }
                            .accessibilityIdentifier("camera.coach.zoom")
                    }
                    if result?.advice.contains(where: { [.clipping, .backlight, .dark].contains($0.kind) }) == true {
                        Button("노출 설정", action: onExposure).accessibilityIdentifier("camera.coach.exposure")
                    }
                    if let tilt = model.cameraTilt, tilt.isFresh(at: now), let roll = tilt.rollDegrees {
                        Text(String(format: "수평 %+.1f°", roll)).monospacedDigit().foregroundStyle(abs(roll) <= 2 ? .green : .white)
                    }
                }.font(.caption2).buttonStyle(.bordered)
            }.padding(6).background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityElement(children: .contain).accessibilityIdentifier("camera.coach")
        }
    }
}

@MainActor
struct PhotoReviewPanel: View {
    @ObservedObject var model: CameraModel
    let url: URL
    @Environment(\.scenePhase) private var phase
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let report = model.photoReviews[url] {
                Text(report.sourceDescription).font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(report.findings) { item in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title + (item.basis == .measured ? " · 측정" : item.basis == .suggestion ? " · 조언" : " · 제한")).font(.caption.weight(.semibold))
                                Text(item.message).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }.frame(maxHeight: 200)
            } else if model.reviewingURL == url { ProgressView("온디바이스 촬영 리뷰 중") }
            else {
                if let error = model.photoReviewErrors[url] { Text(error).font(.caption).foregroundStyle(.orange) }
                Button("이 사진 분석") { model.requestPhotoReview(url) }.accessibilityIdentifier("camera.review.analyze")
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("camera.review.report")
            .task(id: url) { if model.photoReviewEnabled { model.requestPhotoReview(url) } }
            .onChange(of: phase) { _, value in if value == .active && model.photoReviewEnabled { model.requestPhotoReview(url) } }
    }
}
