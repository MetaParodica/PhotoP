import SwiftUI

// Independent guide layer. Never intercepts the native tap/hold/pinch recognizers,
// never renders into a photo or movie, and never mutates camera settings.
struct AICompositionOverlay: View {
    let guide: LiveCompositionGuide?
    let live: Bool
    var opacity = 0.8
    var fill = false
    var bottomInset: CGFloat = 0
    var manualRule: CompositionRule = .automatic
    var sourceSize = CGSize(width: 3, height: 4)
    var status = "AI 분석 대기"

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { _ in
            let fresh = guide.flatMap { live && $0.isFresh(at: ProcessInfo.processInfo.systemUptime) ? $0 : nil }
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    if live || manualRule != .automatic {
                        IntelligentRuleOverlay(rule: fresh?.rule ?? manualRule, sourceSize: fresh?.imageSize ?? sourceSize,
                                               fill: fill, guide: fresh, opacity: opacity)
                    }
                    if let fresh {
                        Canvas { context, _ in
                            let rect = GuideGeometry.imageRect(image: fresh.imageSize, viewport: geometry.size, fill: fill)
                            func map(_ p: CGPoint) -> CGPoint { GuideGeometry.point(p, in: rect, vision: false) }
                            func box(_ b: CGRect) -> CGRect {
                                let a = map(b.origin)
                                return CGRect(x: a.x, y: a.y, width: b.width * rect.width, height: b.height * rect.height)
                            }
                            var c = context
                            c.clip(to: Path(CGRect(origin: .zero, size: geometry.size)))
                            c.addFilter(.shadow(color: .black.opacity(0.9), radius: 1.5))
                            for subject in fresh.subjects {
                                let selected = subject.id == fresh.selectedID
                                let color: Color = selected ? .yellow : .cyan
                                let bounds = box(subject.bounds)
                                c.stroke(Path(roundedRect: bounds, cornerRadius: 6), with: .color(color.opacity(opacity)), lineWidth: selected ? 2 : 1)
                                c.draw(Text("\(subject.detection.kind == .face ? "얼굴" : "인물") \(subject.id)")
                                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(color),
                                       at: CGPoint(x: bounds.midX, y: max(12, bounds.minY - 9)))
                                if selected {
                                    let p = map(subject.anchor)
                                    c.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)), with: .color(.yellow))
                                }
                            }
                            if let point = fresh.targetPoint {
                                let color: Color = fresh.aligned ? .green : .white
                                if let target = fresh.targetBounds {
                                    c.stroke(Path(roundedRect: box(target), cornerRadius: 6), with: .color(color.opacity(opacity)),
                                             style: StrokeStyle(lineWidth: 2, dash: fresh.aligned ? [] : [6, 5]))
                                }
                                let p = map(point)
                                c.stroke(Path(ellipseIn: CGRect(x: p.x - 9, y: p.y - 9, width: 18, height: 18)), with: .color(color), lineWidth: 2)
                                if let measured = fresh.measuredPoint, !fresh.aligned {
                                    let start = map(measured), dx = p.x - start.x, dy = p.y - start.y
                                    let distance = hypot(dx, dy)
                                    if distance > 16 {
                                        let ux = dx / distance, uy = dy / distance
                                        let end = CGPoint(x: p.x - ux * 12, y: p.y - uy * 12)
                                        var arrow = Path(); arrow.move(to: start); arrow.addLine(to: end)
                                        arrow.move(to: CGPoint(x: end.x - ux * 7 - uy * 4, y: end.y - uy * 7 + ux * 4))
                                        arrow.addLine(to: end)
                                        arrow.addLine(to: CGPoint(x: end.x - ux * 7 + uy * 4, y: end.y - uy * 7 - ux * 4))
                                        c.stroke(arrow, with: .color(.white), lineWidth: 2)
                                    }
                                }
                            }
                        }.accessibilityHidden(true)
                    }
                    VStack(spacing: 3) {
                        if let fresh {
                            Text(fresh.rule.title + " · " + (manualRule == .automatic ? (fresh.candidates.first(where: { $0.rule == fresh.rule })?.reason ?? "새 후보 확인 중") : "수동 선택"))
                                .font(.system(size: 10)).lineLimit(2)
                        }
                        if let fresh, !fresh.subjects.isEmpty {
                            Text("검출 \(fresh.subjects.count)명 · 인물을 탭해 선택")
                                .font(.system(size: 10, weight: .medium))
                        }
                        Label(fresh?.advice ?? status,
                              systemImage: fresh?.aligned == true ? "checkmark.circle.fill" : "viewfinder")
                            .font(.caption.weight(.semibold)).multilineTextAlignment(.center)
                    }
                    .foregroundStyle(fresh?.aligned == true ? .green : .white)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
                    .padding(8).padding(.bottom, bottomInset).accessibilityElement(children: .combine)
                    .accessibilityIdentifier("camera.ai.status")
                }
            }
        }.allowsHitTesting(false)
    }
}

@MainActor
struct AICompositionControls: View {
    @ObservedObject var model: CameraModel
    @State private var showLibrary = false
    var body: some View {
        Toggle("온디바이스 AI 제안", isOn: $model.guideAIEnabled)
            .accessibilityIdentifier("camera.ai.toggle")
        if model.guideAIEnabled {
            CameraChoice(title: "촬영 의도", selection: $model.shootingIntent, values: ShootingIntent.allCases,
                         identifier: "camera.ai.intent", key: { $0.id }, label: { $0.title })
            Button("구도 라이브러리") { showLibrary = true }
                .sheet(isPresented: $showLibrary) { CompositionLibraryView(model: model) }
            CameraChoice(title: "구도", selection: $model.intelligentRule, values: CompositionRule.allCases,
                         identifier: "camera.ai.rules", key: { $0.id }, label: { $0.title })
            if let guide = model.aiComposition, guide.isFresh(at: ProcessInfo.processInfo.systemUptime) {
                ForEach(Array(guide.candidates.prefix(3))) { candidate in
                    Button { model.selectIntelligentRule(candidate.rule) } label: {
                        Text(candidate.rule.title + " · " + candidate.reason).font(.caption)
                    }
                }
            }
            Toggle("줌·노출·각도 코치", isOn: $model.cameraCoachEnabled)
            Toggle("촬영 후 자동 리뷰", isOn: $model.photoReviewEnabled)
            Toggle("기기 내 구도 선호 학습 (선택)", isOn: $model.coachLearningEnabled)
            if model.coachLearningEnabled { Button("선호 기록 초기화") { model.resetCoachLearning() } }
            Text(model.motionAvailable ? "수평 센서 사용 가능" : "모션 센서 없음 · 영상 측정만 사용").font(.caption)
            CameraChoice(title: "AI 목표 위치", selection: $model.compositionTarget, values: CompositionTarget.allCases,
                         identifier: "camera.ai.target", key: { $0.id }, label: { $0.title })
            Button("인물 자동 선택") { model.selectCompositionSubject(nil) }
                .accessibilityIdentifier("camera.ai.subject.automatic")
            if let guide = model.aiComposition, guide.isFresh(at: ProcessInfo.processInfo.systemUptime) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(guide.subjects) { subject in
                            Button("인물 \(subject.id) 선택") { model.selectCompositionSubject(subject.id) }
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier("camera.ai.subject.\(subject.id)")
                                .accessibilityAddTraits(guide.selectedID == subject.id ? .isSelected : [])
                        }
                    }
                }
            }
            Text("노란 상자는 선택 인물, 흰 점선은 구도 기준, 초록은 정렬 완료입니다. 청록은 측정 직선/수평 방향입니다. 줌은 제안 버튼으로만, 노출은 기존 패널에서 직접 조절합니다. 리뷰는 원본을 변경하지 않습니다. 선호 학습은 명시적으로 선택하고 촬영한 구도 횟수만 기기 내 저장하며 사진·얼굴은 학습하지 않습니다.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
