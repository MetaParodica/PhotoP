import SwiftUI

enum CameraDrawer: String {
    case composition, looks
}

enum CameraScreen: String, Identifiable {
    case review, editor, history, videos
    var id: String { rawValue }
}

@MainActor
struct CameraView: View {
    @StateObject private var model = CameraModel()
    @State private var tool: CameraTool?
    @State private var screen: CameraScreen?
    @State private var drawer: CameraDrawer?
    @State private var showLiveControls = false
    @State private var showStyles = false
    @State private var showLongExposure = false
    @State private var showCompositionLibrary = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    private let accent = Color(red: 0.78, green: 0.69, blue: 1)
    private var reviewing: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return ProcessInfo.processInfo.arguments.contains("--ui-review")
        #else
        return false
        #endif
    }
    private var locked: Bool { model.busy || model.switchingMode }
    private var isVideo: Bool { model.snapshot.video.isVideoMode }
    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            let dockHeight = min(landscape ? (tool != nil ? 154.0 : drawer != nil ? 110.0 : 96.0) : (tool != nil ? 290.0 : drawer != nil ? 200.0 : 240.0), geometry.size.height * 0.48)
            let insets = geometry.safeAreaInsets
            ZStack(alignment: .topLeading) {
                viewfinder(width: geometry.size.width + insets.leading + insets.trailing,
                           height: geometry.size.height + insets.top + insets.bottom,
                           topInset: geometry.safeAreaInsets.top + 52,
                           bottomInset: dockHeight + geometry.safeAreaInsets.bottom + 8)
                    .offset(x: -insets.leading, y: -insets.top)
                    .accessibilityElement(children: .contain).accessibilityIdentifier("camera.viewfinder")
                VStack(spacing: 0) {
                    topBar.padding(.horizontal, 10).frame(height: 44)
                    Spacer(minLength: 0)
                    cameraDock(landscape: landscape, height: dockHeight)
                        .frame(height: dockHeight).clipped()
                        .accessibilityElement(children: .contain).accessibilityIdentifier("camera.dock")
                        .background(alignment: .bottom) {
                            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                                .allowsHitTesting(false)
                        }
                }.frame(width: geometry.size.width, height: geometry.size.height)
            }.frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .background(Color(red: 0.025, green: 0.025, blue: 0.035).ignoresSafeArea())
        .foregroundStyle(.white).tint(accent)
        .sheet(isPresented: $showLiveControls) { LiveLUTControls(model: model) }
        .sheet(isPresented: $showStyles) { FilmStylesView { imported in try await model.useLiveLUT(imported) } }
        .sheet(isPresented: $showLongExposure) { LongExposureView(model: model) }
        .sheet(isPresented: $showCompositionLibrary) { CompositionLibraryView(model: model) }
        .fullScreenCover(item: $screen, onDismiss: resume) { current in
            switch current {
            case .review: CaptureReviewView(model: model) { next in open(next) }
            case .editor:
                if let original = model.latestOriginal { LUTEditorView(original: original) }
                else { CaptureReviewView(model: model) { next in open(next) } }
            case .history: SavedEditsView()
            case .videos: VideoLibraryView()
            }
        }
        .onAppear {
            if model.showGrid { model.guideGrid = .thirds; model.showGrid = false }
            if reviewing {
                let arguments = ProcessInfo.processInfo.arguments
                if arguments.contains("--review-guide") { drawer = .composition; model.selectCompositionPreset("portrait-two-thirds") }
                if arguments.contains("--review-looks") { drawer = .looks }
                if arguments.contains("--review-video") { tool = .video }
                if arguments.contains("--review-person") { model.personGuide = PersonGuide(framing: .full, position: .left); model.framing = .square }
            } else { resume() }
        }
        .onChange(of: scenePhase) { _, value in
            if value != .active { model.pausePhotoReview() }
            if !reviewing { resume() }
        }
        .onChange(of: model.settings.exposure.manual) { _, manual in if manual { model.proMode = true } }
        .onChange(of: model.monitoring) { _, _ in model.monitoringChanged() }
        .onChange(of: model.focusAssistEnabled) { _, _ in model.monitoringChanged() }
        .onChange(of: model.guideAIEnabled) { _, _ in model.updateComposition(); model.monitoringChanged() }
        .onChange(of: model.guideScene) { _, _ in model.updateComposition() }
        .onChange(of: model.compositionTarget) { _, _ in model.compositionTargetChanged() }
        .onChange(of: model.shootingIntent) { _, _ in model.intelligentOptionsChanged() }
        .onChange(of: model.intelligentRule) { _, rule in model.selectIntelligentRule(rule) }
        .onChange(of: model.cameraCoachEnabled) { _, _ in model.intelligentOptionsChanged() }
        .onChange(of: model.coachLearningEnabled) { _, _ in model.learningChanged() }
        .onChange(of: model.photoReviewEnabled) { _, _ in model.photoReviewSettingChanged() }
        .onChange(of: model.framing) { _, _ in model.intelligentOptionsChanged() }
        .sensoryFeedback(.success, trigger: model.compositionHapticID)
        .onChange(of: model.liveIntensity) { _, _ in model.updateLiveIntensity() }
        .onChange(of: model.liveCompareOriginal) { _, _ in model.updateLiveIntensity() }
        .onChange(of: model.liveGrain) { _, _ in model.updateLiveIntensity() }
        .onChange(of: model.liveFinish) { _, _ in model.updateLiveIntensity() }
        .onChange(of: model.videoPreviewFill) { _, _ in
            model.livePreview?.setViewfinderFill(model.viewfinderFill); model.intelligentOptionsChanged()
        }
        .onChange(of: model.proMode) { _, _ in model.validateDepthMode() }
        .onChange(of: model.longMode) { _, _ in model.validateDepthMode() }
        .onChange(of: model.rawMode) { _, _ in model.validateDepthMode() }
        .onChange(of: model.bracketEnabled) { _, _ in model.validateDepthMode() }
        .onChange(of: model.snapshot.isApplyingSettings) { _, pending in if !pending { model.monitoringChanged() } }
        .task { await model.prepareInstalledLooks() }
        .alert("카메라 알림", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("확인") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .onDisappear { if !reviewing { model.setActive(false) } }
        .preferredColorScheme(.dark)
    }
    private func resume() { if !reviewing { model.setActive(scenePhase == .active && screen == nil) } }
    private func open(_ next: CameraScreen) {
        if !reviewing { model.setActive(false) }
        screen = next
    }
    private func toggle(_ selected: CameraTool) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
            tool = tool == selected ? nil : selected
            if tool != nil { drawer = nil }
        }
    }
    private func toggleDrawer(_ selected: CameraDrawer) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { drawer = drawer == selected ? nil : selected; tool = nil }
    }

    // MARK: Viewfinder

    private func viewfinder(width: CGFloat, height: CGFloat, topInset: CGFloat, bottomInset: CGFloat) -> some View {
        ZStack {
            if reviewing { reviewBackdrop }
            else {
                CameraPreview(session: model.previewSession, mirrored: selectedFront, lensID: model.snapshot.selectedLens,
                              zoom: model.snapshot.readout?.zoom ?? 1, onZoom: { model.setZoom($0) }, fill: model.viewfinderFill,
                              onOrientation: { value in Task { @MainActor in model.setOrientation(value) } },
                              onIndicator: { point, locked in model.showMeteringTarget(point, locked: locked) },
                              onSubjectTap: { model.selectCompositionSubject(at: $0) }) { point, lensID, locked in
                    Task { await model.focusAndMeter(point, lensID: lensID, locked: locked) }
                }
                if model.snapshot.state != .running { unavailableCamera }
            }
            if let preview = model.livePreview {
                LivePreviewSurface(preview: preview)
                    .opacity(model.liveHasFrame && model.snapshot.state == .running ? 1 : 0).allowsHitTesting(false)
            }
            if let target = model.meteringTarget {
                VStack(spacing: 4) {
                    if target.locked { Text(model.snapshot.readout?.focusLocked == true || model.snapshot.readout?.exposureLocked == true ? "AE/AF 잠금" : "AE/AF 고정 중").font(.caption2.weight(.semibold)) }
                    Rectangle().stroke(.yellow, lineWidth: 1.5).frame(width: 64, height: 64)
                }.foregroundStyle(.yellow).position(x: target.point.x * width, y: target.point.y * height)
                    .allowsHitTesting(false).accessibilityIdentifier("camera.focus.target")
            }
            CompositionOverlay(grid: model.guideAIEnabled ? .off : model.guideGrid, pose: model.poseTemplate, opacity: model.guideOpacity,
                               snapshot: model.composition, live: liveGuide, sourceSize: overlayImageSize,
                               fill: model.viewfinderFill, showsAdvice: !model.guideAIEnabled)
            if model.guideAIEnabled {
                AICompositionOverlay(guide: model.aiComposition, live: liveGuide && !model.busy, opacity: model.guideOpacity,
                                     fill: model.viewfinderFill, bottomInset: bottomInset,
                                     manualRule: model.intelligentRule, sourceSize: overlayImageSize, status: model.coachAvailability)
            }
            PersonGuideOverlay(guide: model.personGuide, opacity: model.guideOpacity, snapshot: model.composition,
                               live: liveGuide, sourceSize: overlayImageSize, fill: model.viewfinderFill)
            if let preset = model.compositionPreset { CompositionPresetOverlay(preset: preset, opacity: max(0.5, model.guideOpacity), imageSize: overlayImageSize, fill: model.viewfinderFill) }
            if !isVideo && model.framing != .native { FramingMaskOverlay(aspect: model.framing, imageSize: overlayImageSize, fill: model.viewfinderFill) }
            if model.showGrid { ThirdsGrid() }
            if let countdown = model.countdown {
                Text("\(countdown)").font(.system(size: 96, weight: .thin, design: .rounded)).monospacedDigit()
                    .shadow(radius: 8).allowsHitTesting(false).accessibilityLabel("셀프타이머 \(countdown)초")
            }
        }
        .frame(width: width, height: height).clipped()
        .onAppear { model.updateGuideViewport(CGSize(width: width, height: height)) }
        .onChange(of: CGSize(width: width, height: height)) { _, size in model.updateGuideViewport(size) }
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                HStack(alignment: .top) {
                    previewBadge
                    Spacer()
                    if let histogram = model.histogram, model.liveHasFrame { PreviewHistogramView(histogram: histogram) }
                }
                if model.guideAIEnabled && model.cameraCoachEnabled && liveGuide && !model.busy {
                    CameraCoachBar(model: model) { toggle(model.settings.exposure.manual ? .shutter : .ev) }
                }
                if model.personGuide.framing != .off || model.compositionPresetID != nil, let feedback = personFeedback { feedbackChip(feedback) }
            }.padding(.horizontal, 10).padding(.top, topInset)
                .background(alignment: .top) { scrim(top: true).allowsHitTesting(false) }
        }
    }
    private var liveGuide: Bool { model.liveHasFrame && model.snapshot.state == .running }
    private var overlayImageSize: CGSize {
        if let actual = model.previewImageSize { return actual }
        if isVideo { return model.orientation == .portrait ? CGSize(width: 9, height: 16) : CGSize(width: 16, height: 9) }
        return model.orientation.imageSize
    }
    private var personFeedback: String? {
        guard liveGuide, model.guideAIEnabled, let snapshot = model.composition,
              snapshot.isFresh(at: ProcessInfo.processInfo.systemUptime), let body = snapshot.bodies.first else { return nil }
        let size = model.previewImageSize ?? model.orientation.imageSize
        return model.compositionPreset?.feedback(body: body) ?? model.personGuide.feedback(body: body, aspect: size.width / size.height)
    }
    private func feedbackChip(_ text: String) -> some View {
        Label(text, systemImage: "figure.stand").font(.caption.weight(.semibold))
            .padding(.horizontal, 12).padding(.vertical, 7).background(.black.opacity(0.6), in: Capsule())
            .accessibilityIdentifier("camera.person.feedback")
    }
    private func scrim(top: Bool) -> some View {
        LinearGradient(colors: [.black.opacity(0.45), .clear], startPoint: top ? .top : .bottom, endPoint: top ? .bottom : .top)
            .frame(height: 120)
    }
    private var previewBadge: some View {
        Text(model.snapshot.video.phase.isActive ? String(format: "REC · %02d:%02d · %@", Int(model.snapshot.video.elapsedSeconds) / 60, Int(model.snapshot.video.elapsedSeconds) % 60, VideoCapturePolicy.audioLabel(model.snapshot.video.configuration)) : reviewing ? "SIMULATOR · UI 검토" : isVideo ? "SDR · \(model.videoPreviewFill ? "화면 채움" : "전체 프레임") · \(VideoCapturePolicy.audioLabel(model.snapshot.video.configuration))" : model.snapshot.state == .running ? "화면 채움 · 원본 전체 프레임 저장" : "CAMERA OFFLINE")
            .font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1)
            .padding(.horizontal, 10).padding(.vertical, 7).background(.black.opacity(0.5), in: Capsule())
    }
    private var unavailableCamera: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.aperture").font(.system(size: 40, weight: .ultraLight)).foregroundStyle(accent)
            Text("촬영을 준비하세요").font(.headline)
            Button("카메라 연결") { model.setActive(true) }.buttonStyle(.bordered).disabled(locked)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(white: 0.06))
    }
    private var reviewBackdrop: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.13, green: 0.16, blue: 0.23), Color(red: 0.3, green: 0.25, blue: 0.4), Color(red: 0.11, green: 0.09, blue: 0.16)], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 12) {
                Image(systemName: "camera.aperture").font(.system(size: 56, weight: .ultraLight))
                Text("FRAME YOUR PERSPECTIVE").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(2)
                Text("카메라 입력 없는 UI 검토 화면").font(.caption2).foregroundStyle(.secondary)
            }.foregroundStyle(.white.opacity(0.55))
        }.accessibilityLabel("시뮬레이터 UI 검토 배경. 촬영 영상이 아닙니다.")
    }

    // MARK: Header

    private var topBar: some View {
        HStack(spacing: 6) {
            if !isVideo {
                CameraIconButton(symbol: model.effectiveFlash.symbol, label: model.flash.title, selected: model.effectiveFlash != .off, size: 40) {
                    model.cycleFlash()
                }.disabled(locked || (model.snapshot.capabilities?.flashModes.count ?? 1) < 2)
                    .accessibilityIdentifier("camera.flash")
                CameraIconButton(symbol: "timer", label: model.selfTimer.title, selected: model.selfTimer != .off, size: 40,
                                 badge: model.selfTimer == .off ? nil : "\(model.selfTimer.rawValue)") {
                    model.selfTimer = model.selfTimer.next
                }.disabled(model.countdown != nil).accessibilityIdentifier("camera.timer")
                Button { model.framing = model.framing.next } label: {
                    Text(model.framing.title).font(.system(size: 11, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(model.framing == .native ? .white : accent)
                        .frame(width: 40, height: 40).contentShape(Circle())
                }.buttonStyle(.plain).cameraGlass(radius: 20)
                    .accessibilityLabel("프레이밍 비율").accessibilityValue(model.framing.title)
                    .accessibilityIdentifier("camera.framing")
            }
            Spacer(minLength: 0)
            if isVideo {
                CameraIconButton(symbol: model.videoPreviewFill ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                                 label: model.videoPreviewFill ? "영상 전체 프레임 보기" : "영상 미리보기 화면 채움", size: 40) { model.videoPreviewFill.toggle() }
                    .accessibilityIdentifier("camera.video.previewFit")
            }
            formatChip
            CameraIconButton(symbol: "waveform.path", label: "노출 보조", selected: tool == .monitor, size: 40) { toggle(.monitor) }
                .accessibilityIdentifier("camera.monitor")
            CameraIconButton(symbol: "person.crop.rectangle", label: "구도·인물 가이드",
                             selected: drawer == .composition || tool == .guide || model.personGuide.framing != .off || model.compositionPresetID != nil, size: 40) {
                if isVideo { toggle(.guide) } else { toggleDrawer(.composition) }
            }
                .accessibilityIdentifier("camera.guide")
        }
    }
    private var formatTitle: String {
        model.snapshot.video.configuration.map { "\($0.resolution.title) · \($0.framesPerSecond)" } ?? (model.rawMode == .processed ? model.photoFormat.title : model.rawMode.title)
    }
    private var chipLabel: some View {
        HStack(spacing: 5) {
            Text(formatTitle)
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
        }.font(.system(.caption, design: .rounded, weight: .semibold)).padding(.horizontal, 12).frame(minHeight: 40)
    }
    private var formatChip: some View {
        Button { toggle(isVideo ? .video : .format) } label: { chipLabel }
            .buttonStyle(.plain).cameraGlass(radius: 20).disabled(locked)
            .accessibilityLabel("촬영 포맷").accessibilityIdentifier("camera.format")
    }

    // MARK: Zoom and controls rail

    private var sideLenses: [CameraLens] {
        model.snapshot.lenses.filter { $0.isFront == selectedFront && (!$0.depthCamera || $0.id == model.snapshot.selectedLens) }
            .sorted { ($0.zoomEquivalent ?? 1) < ($1.zoomEquivalent ?? 1) }
    }
    private var zoomControl: some View {
        return HStack(spacing: 2) {
            ForEach(sideLenses) { lens in
                let selected = lens.id == model.snapshot.selectedLens
                Button { model.selectLens(lens.id) } label: {
                    Text(lens.zoomEquivalent.map(ZoomPolicy.label) ?? lens.name)
                        .font(.system(size: 12, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(selected ? accent : .white)
                        .frame(minWidth: 40, minHeight: 40).padding(.horizontal, 2)
                        .background(selected ? Color.black.opacity(0.35) : .clear, in: Circle())
                }.buttonStyle(.plain).accessibilityLabel("\(lens.name) 렌즈").accessibilityAddTraits(selected ? .isSelected : [])
                    .disabled(locked || isVideo)
            }
        }.padding(.horizontal, 4).cameraGlass(radius: 22)
            .opacity(model.snapshot.lenses.isEmpty ? 0 : 1)
    }
    private var railTools: [CameraTool] {
        CaptureWorkflowPolicy.controls(pro: model.proMode, long: model.longMode, video: isVideo)
    }
    private var controlsRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                if !model.longMode || isVideo { aiButton }
                if !model.proMode && !isVideo && !model.longMode {
                    Text("AUTO").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1).foregroundStyle(accent)
                        .padding(.horizontal, 8)
                }
                ForEach(railTools) { item in
                    Button { toggle(item) } label: {
                        VStack(spacing: 5) {
                            Image(systemName: item.symbol).font(.system(size: 17, weight: .regular))
                            Text(value(item)).font(.system(size: 10, weight: .medium, design: .monospaced)).lineLimit(1)
                        }.frame(minWidth: 51, minHeight: verticalSizeClass == .compact ? 34 : 50).padding(.horizontal, 2)
                            .foregroundStyle(tool == item ? accent : .white.opacity(0.85))
                            .background(tool == item ? accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(alignment: .topTrailing) {
                                if let mark = controlMark(item) {
                                    Text(mark).font(.system(size: 8, weight: .heavy, design: .rounded)).foregroundStyle(.black)
                                        .padding(.horizontal, 3).background(accent, in: Capsule()).offset(x: -2, y: 2)
                                }
                            }
                    }.buttonStyle(.plain).accessibilityLabel(item.title).accessibilityValue(value(item))
                        .accessibilityIdentifier("camera.tool.\(item.rawValue)")
                }
                if model.longMode && !isVideo { aiButton }
                if !model.proMode && !isVideo && !model.longMode { autoReadout }
            }.padding(4)
        }.cameraGlass(radius: 22)
            .accessibilityIdentifier("camera.controls.rail")
    }
    private var aiButton: some View {
        Button { model.guideAIEnabled.toggle() } label: {
            Text("AI").font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(model.guideAIEnabled ? accent : .white)
                .frame(width: 44, height: verticalSizeClass == .compact ? 40 : 44)
                .background(model.guideAIEnabled ? accent.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain)
            .accessibilityLabel("실시간 AI 구도 가이드")
            .accessibilityValue(model.guideAIEnabled ? "켜짐" : "꺼짐")
            .accessibilityIdentifier("camera.ai")
            .contextMenu {
                Button("구도 라이브러리") { showCompositionLibrary = true }
                Button("촬영 의도·코치 설정") { toggle(.guide) }
                ForEach(CompositionTarget.allCases) { target in
                    Button(target.title) { model.compositionTarget = target; model.guideAIEnabled = true }
                }
            }
    }
    // Read-only live values in AUTO; PRO turns them into controls.
    private var autoReadoutText: String {
        guard let r = model.snapshot.readout else { return "장치 자동 노출" }
        var text = "ISO \(Int(r.iso)) · \(CameraControlScale.shutter(r.shutterSeconds))"
        if let kelvin = r.kelvin { text += " · \(Int(kelvin))K" }
        return text
    }
    private var autoReadout: some View {
        Text(autoReadoutText)
            .font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.6))
            .lineLimit(1).padding(.horizontal, 8).accessibilityLabel("현재 자동 노출 값")
    }
    private func controlMark(_ item: CameraTool) -> String? {
        let s = model.settings
        switch item {
        case .iso, .shutter: return s.exposure.manual ? "M" : (s.exposure.locked ? "L" : nil)
        case .whiteBalance: return s.whiteBalance.manual ? "M" : (s.whiteBalance.locked ? "L" : nil)
        case .focus: return s.focus.manual ? "M" : (s.focus.locked ? "L" : nil)
        default: return nil
        }
    }
    private var looksButton: some View {
        Button { toggleDrawer(.looks) } label: {
            VStack(spacing: 4) {
                Image(systemName: CameraTool.looks.symbol).font(.system(size: 17))
                Text(model.liveUsesLUT ? "ON" : "룩").font(.system(size: 9, weight: .bold, design: .rounded))
            }.foregroundStyle(drawer == .looks || tool == .looks || model.liveUsesLUT ? accent : .white)
                .frame(width: verticalSizeClass == .compact ? 44 : 58, height: verticalSizeClass == .compact ? 44 : 58).contentShape(Circle())
        }.buttonStyle(.plain).cameraGlass(radius: 29)
            .accessibilityLabel("룩").accessibilityValue(model.liveLUTTitle ?? "원본 색상")
            .accessibilityIdentifier("camera.tool.looks")
    }
    private func value(_ item: CameraTool) -> String {
        let r = model.snapshot.readout
        switch item {
        case .iso: return r.map { "ISO \(Int($0.iso))" } ?? "ISO"
        case .shutter: return r.map { CameraControlScale.shutter($0.shutterSeconds) } ?? "SHUTTER"
        case .ev: return r.map { String(format: "%+.1f EV", $0.exposureBias) } ?? "EV"
        case .whiteBalance: return r?.kelvin.map { "\(Int($0)) K" } ?? "WB"
        case .focus: return model.settings.focus.manual ? "MF" : "AF"
        case .aperture: return model.depthEnabled ? String(format: "f/%.1f", model.depthAperture) : "f/—"
        case .longExposure: return CaptureWorkflowPolicy.durationLabel(model.longConfiguration.duration)
        default: return ""
        }
    }
    private func panel(_ selected: CameraTool, availableHeight: CGFloat) -> some View {
        VStack(spacing: 8) {
            HStack {
                Label(selected.title, systemImage: selected.symbol).font(.system(.subheadline, design: .rounded, weight: .semibold))
                Spacer()
                if locked { ProgressView().controlSize(.small) }
                Button { toggle(selected) } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).frame(width: 44, height: 44) }
                    .buttonStyle(.plain).accessibilityLabel("조절 패널 닫기").accessibilityIdentifier("camera.panel.close")
            }
            ScrollView {
                CameraQuickControls(model: model, tool: selected, openStyles: { showStyles = true },
                                    openImports: { showLiveControls = true }, openLongExposure: { showLongExposure = true })
                    .padding(.bottom, 8)
            }.frame(maxHeight: max(32, availableHeight - 60))
        }.padding(.horizontal, 16).padding(.bottom, 8).cameraGlass(radius: 24)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("camera.panel.\(selected.rawValue)")
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: Bottom bar

    private func cameraDock(landscape: Bool, height: CGFloat) -> some View {
        Group {
            if landscape {
                HStack(spacing: 12) {
                    VStack(spacing: 2) {
                        Group {
                            if let tool { panel(tool, availableHeight: height - 48) }
                            else if let drawer, !isVideo { carousel(drawer) }
                            else { HStack { controlsRail; if !isVideo { looksButton } } }
                        }.frame(height: drawer == nil ? height - 48 : height).clipped()
                        if drawer == nil { modeRow.frame(height: 44) }
                    }
                    shutterRow.frame(width: 240)
                }
            } else {
                VStack(spacing: 4) {
                    Group {
                        if let tool { panel(tool, availableHeight: height - 130) }
                        else if let drawer, !isVideo { carousel(drawer) }
                        else {
                            VStack(spacing: 4) {
                                HStack(spacing: 8) { controlsRail; if !isVideo { looksButton } }.padding(.horizontal, 10)
                                if !sideLenses.isEmpty && !isVideo { zoomControl }
                            }
                        }
                    }.frame(height: max(60, height - (drawer == nil ? 130 : 86))).clipped()
                    if drawer == nil { modeRow.frame(height: 44) }
                    shutterRow.frame(height: 78)
                }
            }
        }.padding(.horizontal, 4).background(.black.opacity(0.12))
    }
    private var shutterRow: some View {
        HStack {
                if drawer != nil && !isVideo {
                    CameraIconButton(symbol: "chevron.down", label: "카드 선택 닫기", size: 52) { toggleDrawer(drawer ?? .composition) }
                        .accessibilityIdentifier("camera.drawer.close")
                } else { thumbnailButton }
                Spacer()
                if isVideo { recordButton } else { shutterButton }
                Spacer()
                CameraIconButton(symbol: "arrow.triangle.2.circlepath.camera", label: "전후면 카메라 전환") {
                    if let lens = model.snapshot.lenses.first(where: { $0.isFront != selectedFront }) { model.selectLens(lens.id) }
                }.disabled(locked || isVideo || !model.snapshot.lenses.contains(where: { $0.isFront != selectedFront }))
            }.padding(.horizontal, 12)
    }
    private var modeRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                modeButton("AUTO", selected: !isVideo && !model.proMode && !model.longMode) {
                    if isVideo { Task { await model.setVideoMode(false) } }
                    else if model.snapshot.capabilities != nil {
                        model.settings = CameraSettings(); Task { await model.applySettings() }
                    }
                    model.proMode = false
                    model.longMode = false
                    tool = nil
                }
                modeButton("PRO", selected: !isVideo && model.proMode && !model.longMode) {
                    if isVideo { Task { await model.setVideoMode(false) } }
                    model.proMode = true
                    model.longMode = false; tool = nil; drawer = nil
                }
                modeButton("LONG", selected: model.longMode && !isVideo) {
                    if isVideo { Task { await model.setVideoMode(false); model.longMode = true } }
                    else { model.longMode = true }
                    model.rawMode = .processed; model.bracketEnabled = false; tool = nil; drawer = nil
                }
                modeButton("VIDEO", selected: isVideo) {
                    if !reviewing && !isVideo { Task { await model.setVideoMode(true) } }
                    tool = nil; drawer = nil
                }.accessibilityIdentifier("camera.mode.video")
            }.disabled(locked || model.countdown != nil || model.recordingRequested)
            .frame(minHeight: 36).frame(maxWidth: .infinity)
        }
    }

    // MARK: Card drawers

    @ViewBuilder private func carousel(_ drawer: CameraDrawer) -> some View {
        switch drawer {
        case .composition: CameraCarousel(title: "구도 가이드 선택", items: compositionItems, identifier: "camera.drawer.composition")
        case .looks: CameraCarousel(title: "룩 선택", items: lookItems, identifier: "camera.drawer.looks")
        }
    }
    private var compositionItems: [CameraCarouselItem] {
        let none = model.compositionPresetID == nil && model.personGuide.framing == .off
        var items = [CameraCarouselItem(id: "off", title: "가이드 끔", selected: none, thumbnail: AnyView(GuideThumbnail(preset: nil))) {
            model.selectCompositionPreset(nil); model.personGuide.framing = .off
        }]
        items.append(CameraCarouselItem(id: "person", title: "인물 실루엣", selected: model.personGuide.framing != .off,
                                        thumbnail: AnyView(SymbolThumbnail(symbol: "figure.stand"))) {
            model.selectCompositionPreset(nil)
            if model.personGuide.framing == .off { model.personGuide.framing = .full; model.guideScene = .portrait }
            toggle(.guide)
        })
        items.append(CameraCarouselItem(id: "settings", title: "세부 설정", thumbnail: AnyView(SymbolThumbnail(symbol: "slider.horizontal.3"))) { toggle(.guide) })
        items += CompositionPreset.all.map { preset in
            CameraCarouselItem(id: preset.id, title: preset.title, selected: model.compositionPresetID == preset.id,
                               thumbnail: AnyView(GuideThumbnail(preset: preset))) {
                model.selectCompositionPreset(model.compositionPresetID == preset.id ? nil : preset.id)
            }
        }
        return items
    }
    // Same carousel as guides: original, PhotoP colour styles, spatial looks, then adjust/browse.
    private var lookItems: [CameraCarouselItem] {
        var items = [CameraCarouselItem(id: "original", title: "원본", selected: !model.liveUsesLUT, thumbnail: AnyView(SymbolThumbnail(symbol: "camera"))) {
            Task { await model.selectOriginalLook() }
        }]
        items.append(CameraCarouselItem(id: "adjust", title: "강도·마감", thumbnail: AnyView(SymbolThumbnail(symbol: "slider.horizontal.3"))) { toggle(CameraTool.looks) })
        items.append(CameraCarouselItem(id: "browse", title: "전체·가져오기", thumbnail: AnyView(SymbolThumbnail(symbol: "square.grid.2x2"))) { showStyles = true })
        items += FilmStyle.all.map { style in
            CameraCarouselItem(id: style.id, title: style.name, selected: model.liveLookID == style.id,
                               thumbnail: AnyView(SymbolThumbnail(symbol: "camera.filters"))) {
                Task { await model.selectLook(id: style.id) { try style.imported() } }
            }
        }
        items += ProceduralLook.all.map { look in
            CameraCarouselItem(id: look.id, title: look.name, selected: model.liveLookID == look.id,
                               thumbnail: AnyView(SymbolThumbnail(symbol: "sparkles"))) {
                Task { await model.selectLook(id: look.id) { try look.imported() } }
            }
        }
        items += model.installedLooks.filter(\.canApply).map { look in
            CameraCarouselItem(id: look.id, title: look.name, selected: model.liveLookID == look.id,
                               thumbnail: AnyView(SymbolThumbnail(symbol: "camera.filters"))) {
                Task { await model.selectLook(id: look.id) { try await look.load() } }
            }
        }
        if model.installedLooks.isEmpty {
            items.append(CameraCarouselItem(id: "installing", title: model.lookInstallationError == nil ? "외부 룩 준비 중" : "외부 룩 재시도",
                                            thumbnail: AnyView(SymbolThumbnail(symbol: "arrow.down.circle"))) {
                Task { await model.prepareInstalledLooks() }
            })
        }
        return items
    }
    private var thumbnailButton: some View {
        Button { open(.review) } label: {
            Group {
                if let thumbnail = model.latestThumbnail {
                    Image(decorative: thumbnail.image, scale: 1).resizable().scaledToFill()
                } else {
                    Image(systemName: "photo.on.rectangle.angled").font(.system(size: 20))
                }
            }.frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 14))
                .cameraGlass(radius: 14)
        }.buttonStyle(.plain).accessibilityLabel("사진과 편집 기록")
            .accessibilityValue(model.latestOriginal == nil ? "최근 촬영 없음" : "최근 촬영 보기")
            .disabled(locked || model.countdown != nil)
    }
    private var shutterButton: some View {
        Button { if model.longExposureRunning { model.cancelLongExposure() } else { model.shutterPressed() } } label: {
            ZStack {
                Circle().stroke(.white.opacity(0.85), lineWidth: 2.5)
                if model.countdown != nil || model.longExposureRunning {
                    RoundedRectangle(cornerRadius: 6).fill(.white).frame(width: 28, height: 28)
                } else {
                    Circle().fill(.white).padding(6).opacity(model.canCapture ? 1 : 0.4)
                }
            }.frame(width: 78, height: 78)
        }.buttonStyle(.plain).disabled(!model.canCapture && model.countdown == nil && !model.longExposureRunning)
            .overlay(alignment: .top) {
                if model.longExposureRunning, let progress = model.longProgress { ProgressView(value: progress.fraction).tint(.purple).offset(y: -6) }
            }
            .accessibilityLabel(model.longExposureRunning ? "장노출 취소" : model.countdown != nil ? "셀프타이머 취소" : model.longMode ? "장노출 합성 촬영" : model.bracketEnabled ? "노출 브래킷 3장 촬영"
                                : model.selfTimer != .off ? "\(model.selfTimer.rawValue)초 후 사진 촬영" : "사진 촬영")
            .accessibilityIdentifier("camera.shutter")
    }
    private var recordButton: some View {
        Button {
            if model.snapshot.video.phase.isActive { model.stopVideo() }
            else { Task { await model.recordVideo() } }
        } label: {
            ZStack {
                Circle().stroke(.white.opacity(0.85), lineWidth: 2.5)
                if model.snapshot.video.phase.isActive { RoundedRectangle(cornerRadius: 5).fill(.red).frame(width: 30, height: 30) }
                else { Circle().fill(.red).padding(7) }
            }.frame(width: 78, height: 78)
        }.buttonStyle(.plain)
            .disabled(model.snapshot.video.phase == .stopping || (!model.snapshot.video.phase.isActive && !model.canRecordVideo))
            .accessibilityLabel(model.snapshot.video.phase.isActive ? "영상 녹화 종료" : "\(VideoCapturePolicy.audioLabel(model.snapshot.video.configuration)) 영상 녹화")
            .accessibilityIdentifier("camera.record")
    }
    private func modeButton(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 11, weight: .semibold, design: .rounded)).tracking(1.5)
                .foregroundStyle(selected ? accent : .white.opacity(0.5)).frame(minWidth: 54, minHeight: 44)
                .overlay(alignment: .bottom) { if selected { Circle().fill(accent).frame(width: 4, height: 4) } }
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
    private var selectedFront: Bool { model.snapshot.lenses.first(where: { $0.id == model.snapshot.selectedLens })?.isFront ?? false }
}
