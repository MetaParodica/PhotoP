import SwiftUI

@MainActor
struct CameraView: View {
    @StateObject private var model = CameraModel()
    @State private var tool: CameraTool?
    @State private var showEditor = false
    @State private var showHistory = false
    @State private var showVideos = false
    @State private var showLiveControls = false
    @State private var showStyles = false
    @State private var showLongExposure = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let accent = Color(red: 0.78, green: 0.69, blue: 1)
    private var reviewing: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return ProcessInfo.processInfo.arguments.contains("--ui-review")
        #else
        return false
        #endif
    }
    private var locked: Bool { model.busy || model.snapshot.isApplyingSettings }
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 12) {
                topBar
                viewfinder
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
                controlsRail
                bottomBar
            }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 8)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(Color(red: 0.025, green: 0.025, blue: 0.035).ignoresSafeArea())
        .foregroundStyle(.white).tint(accent)
        .sheet(isPresented: $showLiveControls) { LiveLUTControls(model: model) }
        .sheet(isPresented: $showStyles) { FilmStylesView { imported in try await model.useLiveLUT(imported) } }
        .sheet(isPresented: $showLongExposure) { LongExposureView(model: model) }
        .fullScreenCover(isPresented: $showEditor, onDismiss: resume) {
            if let original = model.latestOriginal { LUTEditorView(original: original) }
        }
        .fullScreenCover(isPresented: $showHistory, onDismiss: resume) { SavedEditsView() }
        .fullScreenCover(isPresented: $showVideos, onDismiss: resume) { VideoLibraryView() }
        .onAppear {
            if model.showGrid { model.guideGrid = .thirds; model.showGrid = false }
            if reviewing {
                if ProcessInfo.processInfo.arguments.contains("--review-guide") { tool = .guide; model.guideGrid = .thirds; model.showGrid = false }
                if ProcessInfo.processInfo.arguments.contains("--review-video") { tool = .video }
            } else { resume() }
        }
        .onChange(of: scenePhase) { _, _ in if !reviewing { resume() } }
        .onDisappear { if !reviewing { model.setActive(false) } }
        .preferredColorScheme(.dark)
    }
    private func resume() { if !reviewing { model.setActive(scenePhase == .active && !showEditor && !showHistory && !showVideos) } }
    private func toggle(_ selected: CameraTool) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { tool = tool == selected ? nil : selected }
    }
    private var topBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(accent).frame(width: 6, height: 6)
                Text("PhotoP").font(.system(.title3, design: .rounded, weight: .semibold))
            }.accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            Button { toggle(model.snapshot.video.isVideoMode ? .video : .format) } label: {
                HStack(spacing: 5) {
                    Text(model.snapshot.video.configuration.map { "\($0.resolution.title) · \($0.framesPerSecond)" } ?? (model.rawMode == .processed ? model.photoFormat.title : model.rawMode.title))
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                }.font(.system(.caption, design: .rounded, weight: .semibold)).padding(.horizontal, 14).frame(minHeight: 44)
            }.buttonStyle(.plain).cameraGlass(radius: 22).accessibilityLabel("촬영 포맷")
                .accessibilityIdentifier("camera.format")
            CameraIconButton(symbol: "waveform.path", label: "노출 보조", selected: tool == .monitor) { toggle(.monitor) }
                .accessibilityIdentifier("camera.monitor")
            CameraIconButton(symbol: "square.split.2x2", label: "구도 가이드", selected: tool == .guide) { toggle(.guide) }
                .accessibilityIdentifier("camera.guide")
        }
    }
    private var viewfinder: some View {
        GeometryReader { g in
            // Preserve sensor aspect ratio. Controls overlay the viewfinder, never crop the saved image.
            let ratio: CGFloat = model.snapshot.video.isVideoMode ? 9 / 16 : 3 / 4
            let w = min(g.size.width, g.size.height * ratio)
            ZStack(alignment: .bottom) {
                ZStack {
                    if reviewing { reviewBackdrop }
                    else {
                        CameraPreview(session: model.previewSession, mirrored: selectedFront, lensID: model.snapshot.selectedLens) { point, lensID in
                            Task { await model.focusAndMeter(point, lensID: lensID) }
                        }
                        if model.snapshot.state != .running { unavailableCamera }
                    }
                    if let preview = model.livePreview {
                        LivePreviewSurface(preview: preview)
                            .opacity(model.liveHasFrame && model.snapshot.state == .running ? 1 : 0).allowsHitTesting(false)
                    }
                    CompositionOverlay(grid: model.guideGrid, pose: model.poseTemplate, opacity: model.guideOpacity,
                                       snapshot: model.composition, live: model.liveHasFrame && model.snapshot.state == .running, sourceSize: model.previewImageSize)
                    if model.showGrid { ThirdsGrid() }
                }.frame(width: w, height: w / ratio).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .overlay(alignment: .topLeading) { previewBadge.padding(12) }
                    .overlay(alignment: .topTrailing) {
                        if let histogram = model.histogram, model.liveHasFrame { PreviewHistogramView(histogram: histogram).padding(10) }
                    }
                if tool == nil { lensRail.padding(.bottom, 14) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) { if let tool { panel(tool, availableHeight: g.size.height - 16).padding(8) } }
        }
    }
    private var previewBadge: some View {
        Text(model.snapshot.video.phase.isActive ? String(format: "REC · %02d:%02d · 무음", Int(model.snapshot.video.elapsedSeconds) / 60, Int(model.snapshot.video.elapsedSeconds) % 60) : reviewing ? "SIMULATOR · UI 검토" : model.snapshot.video.isVideoMode ? "SDR · ORIGINAL · 무음" : model.liveUsesLUT ? "LOOK PREVIEW · 원본 저장" : model.snapshot.state == .running ? "ORIGINAL" : "CAMERA OFFLINE")
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
            }.foregroundStyle(.white.opacity(0.55)).offset(y: -60)
        }.accessibilityLabel("시뮬레이터 UI 검토 배경. 촬영 영상이 아닙니다.")
    }
    private var lensRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(model.snapshot.lenses.filter { $0.isFront == selectedFront }) { lens in
                    Button { model.selectLens(lens.id) } label: {
                        Text(lens.name).font(.caption.weight(.semibold)).padding(.horizontal, 12).frame(minHeight: 44)
                            .foregroundStyle(lens.id == model.snapshot.selectedLens ? accent : .white)
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 6)
        }.fixedSize(horizontal: false, vertical: true).cameraGlass(radius: 24)
            .padding(.horizontal, 36).disabled(locked || model.livePreview != nil || model.snapshot.video.isVideoMode)
            .opacity(model.snapshot.lenses.isEmpty ? 0 : 1)
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
            }.frame(maxHeight: max(48, min(215, availableHeight - 68)))
        }.padding(.horizontal, 16).padding(.bottom, 8).cameraGlass(radius: 24)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("camera.panel.\(selected.rawValue)")
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    private var controlsRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach([CameraTool.iso, .shutter, .ev, .whiteBalance, .focus, .looks]) { item in
                    Button { toggle(item) } label: {
                        VStack(spacing: 5) {
                            Image(systemName: item.symbol).font(.system(size: 17, weight: .regular))
                            Text(value(item)).font(.system(size: 10, weight: .medium, design: .monospaced)).lineLimit(1)
                        }.frame(minWidth: 51, minHeight: 54).padding(.horizontal, 2)
                            .foregroundStyle(tool == item ? accent : .white.opacity(0.8))
                            .background(tool == item ? accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain).accessibilityLabel(item.title).accessibilityValue(value(item))
                        .accessibilityIdentifier("camera.tool.\(item.rawValue)")
                }
            }.padding(6)
        }.cameraGlass(radius: 22)
    }
    private func value(_ item: CameraTool) -> String {
        let r = model.snapshot.readout
        switch item {
        case .iso: return r.map { "ISO \(Int($0.iso))" } ?? "ISO"
        case .shutter: return r.map { CameraControlScale.shutter($0.shutterSeconds) } ?? "SHUTTER"
        case .ev: return r.map { String(format: "%+.1f EV", $0.exposureBias) } ?? "EV"
        case .whiteBalance: return r?.kelvin.map { "\(Int($0)) K" } ?? "WB"
        case .focus: return model.settings.focus.manual ? "MF" : "AF"
        default: return "LOOKS"
        }
    }
    private var bottomBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 24) {
                modeButton("AUTO", selected: !model.snapshot.video.isVideoMode && !model.settings.exposure.manual && tool != .longExposure) {
                    if model.snapshot.video.isVideoMode { Task { await model.setVideoMode(false) } }
                    else if model.snapshot.capabilities != nil {
                        model.settings.exposure.manual = false; model.settings.exposure.locked = false
                        Task { await model.applySettings() }
                    }
                    tool = nil
                }
                modeButton("PRO", selected: !model.snapshot.video.isVideoMode && model.settings.exposure.manual && tool != .longExposure) {
                    if model.snapshot.video.isVideoMode { Task { await model.setVideoMode(false) } }; toggle(.iso)
                }
                modeButton("LONG", selected: tool == .longExposure) {
                    if model.snapshot.video.isVideoMode { Task { await model.setVideoMode(false) } }; toggle(.longExposure)
                }
                modeButton("VIDEO", selected: model.snapshot.video.isVideoMode || tool == .video) {
                    if !reviewing && !model.snapshot.video.isVideoMode { Task { await model.setVideoMode(true) } }
                    toggle(.video)
                }.accessibilityIdentifier("camera.mode.video")
            }.disabled(locked)
            HStack {
                Menu {
                    Button("영상 보관함", systemImage: "video") { if !reviewing { model.setActive(false) }; showVideos = true }
                    if let video = model.latestVideo {
                        ShareLink(item: video.url) { Label("영상 원본 공유", systemImage: "video") }
                        if !model.videoSavedToPhotos { Button("영상 사진 앱에 저장") { Task { await model.saveVideoToPhotos() } } }
                    }
                    Button("편집 기록", systemImage: "photo.stack") { model.setActive(false); showHistory = true }
                    if let original = model.latestOriginal {
                        ShareLink(item: original) { Label("촬영 원본 공유", systemImage: "square.and.arrow.up") }
                        if original.pathExtension != "dng" {
                            Button("사진 편집", systemImage: "slider.horizontal.3") { model.setActive(false); showEditor = true }
                        }
                        if !model.savedToPhotos { Button("사진 앱에 저장") { Task { await model.saveLatestToPhotos() } } }
                    }
                    ForEach(Array(model.latestOriginals.enumerated()), id: \.element) { i, url in ShareLink("원본 \(i + 1) 공유", item: url) }
                } label: {
                    Image(systemName: "photo.on.rectangle.angled").font(.system(size: 20)).frame(width: 52, height: 52).cameraGlass(radius: 18)
                }.accessibilityLabel("사진과 편집 기록").disabled(locked)
                Spacer()
                if model.snapshot.video.isVideoMode {
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
                        .accessibilityLabel(model.snapshot.video.phase.isActive ? "영상 녹화 종료" : "무음 영상 녹화")
                        .accessibilityIdentifier("camera.record")
                } else {
                    Button { Task { await model.capture() } } label: {
                        Circle().fill(.white).padding(6).overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 2.5))
                            .frame(width: 78, height: 78).opacity(model.canCapture ? 1 : 0.4)
                    }.buttonStyle(.plain).disabled(!model.canCapture)
                        .accessibilityLabel(model.bracketEnabled ? "노출 브래킷 3장 촬영" : "사진 촬영")
                        .accessibilityIdentifier("camera.shutter")
                }
                Spacer()
                CameraIconButton(symbol: "arrow.triangle.2.circlepath.camera", label: "전후면 카메라 전환") {
                    if let lens = model.snapshot.lenses.first(where: { $0.isFront != selectedFront }) { model.selectLens(lens.id) }
                }.disabled(locked || model.snapshot.video.isVideoMode || model.livePreview != nil || !model.snapshot.lenses.contains(where: { $0.isFront != selectedFront }))
            }.padding(.horizontal, 16)
            status
        }
    }
    private func modeButton(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 11, weight: .semibold, design: .rounded)).tracking(1.5)
                .foregroundStyle(selected ? accent : .white.opacity(0.5)).frame(minWidth: 54, minHeight: 44)
                .overlay(alignment: .bottom) { if selected { Circle().fill(accent).frame(width: 4, height: 4) } }
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
    private var status: some View {
        HStack(spacing: 6) {
            if locked { ProgressView().controlSize(.mini) }
            Text(reviewing ? "시뮬레이터 · 실제 촬영 검증 전" : (model.snapshot.video.isVideoMode ? nil : model.rawUnavailableReason ?? model.bracketUnavailableReason) ?? model.message ?? "원본을 보존하는 카메라")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                .accessibilityAddTraits(.updatesFrequently)
        }.frame(maxWidth: .infinity, minHeight: 24)
    }
    private var selectedFront: Bool { model.snapshot.lenses.first(where: { $0.id == model.snapshot.selectedLens })?.isFront ?? false }
}
