import SwiftUI

@MainActor
struct CameraView: View {
    @StateObject private var model = CameraModel()
    @State private var showEditor = false
    @State private var showHistory = false
    @State private var showLiveControls = false
    @State private var showMonitoring = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geometry in
            let previewHeight = min(geometry.size.width * 4 / 3, max(120, geometry.size.height - 420))
            VStack(spacing: 14) {
                HStack {
                    Text("PhotoP").font(.headline)
                    Spacer()
                    Picker("사진 포맷", selection: $model.photoFormat) {
                        ForEach(model.snapshot.capabilities?.photoFormats ?? [.jpeg]) { format in
                            Text(format.title).tag(format)
                        }
                    }
                    .disabled(model.busy || model.snapshot.isApplyingSettings || model.rawMode != .processed)
                    Button { model.showGrid.toggle() } label: { Image(systemName: "grid") }
                        .accessibilityLabel("삼분할 격자 전환")
                }
                .padding(.horizontal)
                CameraPreview(session: model.previewSession, mirrored: selectedFront, lensID: model.snapshot.selectedLens) { point, lensID in
                    Task { await model.focusAndMeter(point, lensID: lensID) }
                }
                    .frame(width: previewHeight * 3 / 4, height: previewHeight)
                    .overlay {
                        if let preview = model.livePreview {
                            LivePreviewSurface(preview: preview)
                                .opacity(model.liveHasFrame && model.snapshot.state == .running ? 1 : 0)
                                .allowsHitTesting(false)
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if model.liveHasFrame, model.snapshot.state == .running, let histogram = model.histogram {
                            PreviewHistogramView(histogram: histogram)
                        }
                    }
                    .overlay { if model.showGrid { ThirdsGrid() } }
                    .overlay(alignment: .bottom) {
                        if model.snapshot.state != .running {
                            Button("카메라 시작 · 다시 시도") { model.setActive(true) }
                                .buttonStyle(.borderedProminent).padding()
                        }
                    }
                Picker("촬영 데이터", selection: $model.rawMode) {
                    ForEach(model.snapshot.capabilities?.rawModes ?? [.processed]) { mode in Text(mode.title).tag(mode) }
                }.pickerStyle(.segmented).padding(.horizontal)
                    .disabled(model.busy || model.snapshot.isApplyingSettings)
                if let reason = model.rawUnavailableReason { Text(reason).font(.caption).padding(.horizontal) }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(model.snapshot.lenses) { lens in
                            Button(lens.name) { model.selectLens(lens.id) }
                                .font(.caption)
                                .buttonStyle(.bordered)
                                .tint(lens.id == model.snapshot.selectedLens ? .yellow : .gray)
                                .disabled(model.busy || model.snapshot.isApplyingSettings || model.livePreview != nil)
                        }
                    }.padding(.horizontal)
                }
                HStack {
                    Button("LUT") { showLiveControls = true }
                        .disabled(model.busy || model.snapshot.isApplyingSettings)
                    Button("보조") { showMonitoring = true }
                        .disabled(model.busy || model.snapshot.isApplyingSettings)
                    Button("PRO") { model.showControls = true }
                        .disabled(model.busy || model.snapshot.isApplyingSettings)
                    Spacer()
                    Button { Task { await model.capture() } } label: {
                        Circle().fill(.white).frame(width: 66, height: 66)
                            .padding(5).overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                    .disabled(!model.canCapture)
                    .opacity(model.canCapture ? 1 : 0.4)
                    .accessibilityLabel("사진 촬영")
                    Spacer()
                    if let original = model.latestOriginal {
                        ShareLink(item: original) { Image(systemName: "square.and.arrow.up") }
                            .accessibilityLabel("마지막 촬영 원본 공유")
                    } else { Color.clear.frame(width: 30, height: 30) }
                }.padding(.horizontal, 28)
                if model.livePreview != nil {
                    Text(model.liveHasFrame ? (model.liveUsesLUT ? "LUT·보조 프리뷰 · 원본 촬영" : "보조 프리뷰 · 원본 촬영") : "프리뷰 프레임 대기 중")
                        .font(.caption).foregroundStyle(.yellow)
                }
                if model.busy || model.snapshot.isApplyingSettings { ProgressView() }
                if let readout = model.snapshot.readout {
                    CameraReadoutView(readout: readout)
                        .padding(.horizontal)
                }
                if let message = model.message {
                    Text(message).font(.caption).multilineTextAlignment(.center).padding(.horizontal)
                        .accessibilityAddTraits(.updatesFrequently)
                }
                Button("편집 기록") {
                    model.setActive(false)
                    showHistory = true
                }.disabled(model.busy || model.snapshot.isApplyingSettings)
                if let original = model.latestOriginal, original.pathExtension != "dng" {
                    Button("LUT 사진 편집") {
                        model.setActive(false)
                        showEditor = true
                    }.disabled(model.busy || model.snapshot.isApplyingSettings)
                }
                if model.latestOriginal != nil && !model.savedToPhotos {
                    Button("사진 앱에 저장") { Task { await model.saveLatestToPhotos() } }.disabled(model.busy || model.snapshot.isApplyingSettings)
                }
                Spacer(minLength: 0)
            }
        }
        .background(.black).foregroundStyle(.white)
        .sheet(isPresented: $model.showControls) { ManualControls(model: model) }
        .sheet(isPresented: $showMonitoring) { MonitoringControls(model: model) }
        .sheet(isPresented: $showLiveControls) { LiveLUTControls(model: model) }
        .fullScreenCover(isPresented: $showEditor, onDismiss: { model.setActive(scenePhase == .active) }) {
            if let original = model.latestOriginal { LUTEditorView(original: original) }
        }
        .fullScreenCover(isPresented: $showHistory, onDismiss: { model.setActive(scenePhase == .active) }) {
            SavedEditsView()
        }
        .onAppear { model.setActive(scenePhase == .active && !showEditor && !showHistory) }
        .onChange(of: scenePhase) { _, phase in model.setActive(phase == .active && !showEditor && !showHistory) }
        .onDisappear { model.setActive(false) }
        .preferredColorScheme(.dark)
    }

    private var selectedFront: Bool {
        model.snapshot.lenses.first(where: { $0.id == model.snapshot.selectedLens })?.isFront ?? false
    }
}
