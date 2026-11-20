import SwiftUI

@MainActor
struct DepthResultLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [DepthResultSummary] = []
    @State private var selected: DepthEditSession?
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                Text("저장된 사진을 열어 초점·f값·렌즈를 바꿉니다. 촬영 당시 깊이와 룩을 검증하여 사용하며 새 결과로 저장합니다.").font(.caption)
                if loading { ProgressView() }
                if let error { Text(error).foregroundStyle(.orange) }
                if entries.isEmpty && !loading { Text("저장된 심도 사진이 없습니다.") }
                ForEach(entries) { entry in
                    Button {
                        loading = true; error = nil
                        Task {
                            defer { loading = false }
                            do { selected = try await CaptureResultProcessor.shared.loadSession(result: entry.result, original: entry.original) }
                            catch { self.error = error.localizedDescription }
                        }
                    } label: {
                        VStack(alignment: .leading) {
                            Text(entry.original.lastPathComponent).lineLimit(1)
                            Text(entry.date, format: .dateTime.year().month().day().hour().minute())
                            Text(String(format: "f/%.1f", entry.aperture))
                        }
                    }.disabled(loading)
                }
            }
            .navigationTitle("심도 보관함")
            .toolbar { Button("닫기") { dismiss() }.disabled(loading) }
            .task { await refresh() }
            .sheet(item: $selected, onDismiss: { Task { await refresh() } }) { DepthResultEditorView(session: $0) }
        }.preferredColorScheme(.dark)
    }
    private func refresh() async {
        do { entries = try await CaptureResultProcessor.shared.list() }
        catch { self.error = error.localizedDescription }
    }
}

private struct DepthPreviewRequest: Hashable {
    let aperture: Double
    let x: Double
    let y: Double
    let profile: DepthLensProfile
    let original: Bool
    let corrections: DepthCorrections
    let diagnostic: DepthDiagnostic
}

@MainActor
struct DepthResultEditorView: View {
    let session: DepthEditSession
    private let editor: DepthPhotoEditor
    private let beforeSave: (@Sendable () async throws -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var aperture: Double
    @State private var focus: CGPoint
    @State private var profile: DepthLensProfile
    @State private var compare = false
    @State private var image: CGImage?
    @State private var message: String?
    @State private var saving = false
    @State private var rendering = false
    @State private var history: DepthCorrectionHistory
    @State private var brushEnabled = false
    @State private var brushMode: DepthBrushMode = .foreground
    @State private var brushRadius = 0.035
    @State private var softness = 0.6
    @State private var protectFocus = false
    @State private var strokePoints: [DepthBrushPoint] = []
    @State private var diagnostic: DepthDiagnostic = .result
    @State private var saveTask: Task<Void, Never>?

    init(session: DepthEditSession, beforeSave: (@Sendable () async throws -> Void)? = nil) {
        self.session = session; editor = DepthPhotoEditor(session: session)
        self.beforeSave = beforeSave
        _aperture = State(initialValue: session.recipe.aperture ?? 2.8)
        _focus = State(initialValue: CGPoint(x: session.recipe.focusX, y: session.recipe.focusY))
        _profile = State(initialValue: session.recipe.lensProfile ?? .natural)
        _history = State(initialValue: DepthCorrectionHistory(session.corrections))
    }
    private var request: DepthPreviewRequest {
        .init(aperture: aperture, x: Double(focus.x), y: Double(focus.y), profile: profile, original: compare, corrections: history.current, diagnostic: diagnostic)
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                GeometryReader { geometry in
                    if let image {
                        let scale = min(geometry.size.width / CGFloat(image.width), geometry.size.height / CGFloat(image.height))
                        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
                        let origin = CGPoint(x: (geometry.size.width - size.width) / 2, y: (geometry.size.height - size.height) / 2)
                        Image(decorative: image, scale: 1).resizable().frame(width: size.width, height: size.height)
                            .overlay(alignment: .topLeading) {
                                Rectangle().stroke(.yellow, lineWidth: 2).frame(width: 36, height: 36)
                                    .position(x: focus.x * size.width, y: focus.y * size.height).allowsHitTesting(false)
                            }
                            .contentShape(Rectangle())
                            .gesture(SpatialTapGesture().onEnded { value in
                                guard !saving, !compare, !brushEnabled else { return }
                                focus = CGPoint(x: min(1, max(0, value.location.x / size.width)), y: min(1, max(0, value.location.y / size.height)))
                            })
                            .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { value in
                                guard brushEnabled, !saving, !compare else { return }
                                let point = DepthBrushPoint(x: min(1,max(0,Double(value.location.x / size.width))), y: min(1,max(0,Double(value.location.y / size.height))))
                                if strokePoints.count < 128, strokePoints.last.map({ hypot($0.x-point.x,$0.y-point.y)>0.004 }) ?? true { strokePoints.append(point) }
                            }.onEnded { _ in finishStroke() })
                            .position(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
                    } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("사진을 터치하여 재초점 · " + String(format: "f/%.1f", aperture))
                        .accessibilityIdentifier("editor.depth.apertureValue")
                    Group {
                        Slider(value: $aperture, in: 1.4...16)
                            .accessibilityIdentifier("editor.depth.aperture")
                        DepthLensPicker(selection: $profile, identifier: "editor.depth.profile")
                        Toggle("원본 비교", isOn: $compare).accessibilityIdentifier("editor.depth.compare")
                    }.disabled(saving)
                    DisclosureGroup("심도 교정·진단") {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("보기", selection: $diagnostic) { ForEach(DepthDiagnostic.allCases, id: \.self) { Text($0.title).tag($0) } }.pickerStyle(.menu)
                            if diagnostic == .matte, session.matte == nil { Text("저장된 선택 매트가 없습니다.").font(.caption) }
                            Toggle("깊이 교정 브러시", isOn: $brushEnabled).accessibilityIdentifier("editor.depth.brush")
                            if brushEnabled {
                                Picker("교정", selection: $brushMode) { Text("전경").tag(DepthBrushMode.foreground); Text("배경").tag(DepthBrushMode.background) }.pickerStyle(.segmented)
                                Text("브러시 크기").font(.caption); Slider(value: $brushRadius, in: 0.01...0.15)
                                Text("경계 부드러움").font(.caption); Slider(value: $softness, in: 0...1)
                                Toggle("현재 초점 깊이 범위 보호", isOn: $protectFocus)
                            }
                            HStack {
                                Button("실행 취소") { history.undo() }.disabled(!history.canUndo)
                                Button("다시 실행") { history.redo() }.disabled(!history.canRedo)
                            }
                            Text("원본 깊이 지도 보존 · 전경/배경 값은 기존 지도 범위에서 결정합니다. 노란 진단은 결측/혼합 경계이며 모델 확률이 아닙니다.").font(.caption2)
                        }.disabled(saving)
                    }.disabled(saving)
                    if rendering { ProgressView("미리보기 갱신 중") }
                    if let message { Text(message).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("editor.depth.message") }
                    if saving { Button("저장 취소") { saveTask?.cancel() }.accessibilityIdentifier("editor.depth.cancel") }
                    else { Button("원래 해상도로 새 결과 저장") { save() }.buttonStyle(.borderedProminent).accessibilityIdentifier("editor.depth.save") }
                    Text("미리보기는 최대768px입니다. 재초점은 저장된 깊이의 정확도 범위에서 작동하며 최초 매트 밖의 피사체는 깊이만 사용합니다. 원본과 이전 결과는 보존합니다.").font(.caption2).foregroundStyle(.secondary)
                }.padding(.horizontal)
            }.padding(.bottom)
                .navigationTitle("사진 재초점")
                .toolbar { Button("닫기") { dismiss() }.disabled(saving) }
                .interactiveDismissDisabled(saving)
                .task(id: request) { await refresh(request) }
                .onChange(of: scenePhase) { _, phase in if phase != .active { saveTask?.cancel() } }
                .onDisappear { saveTask?.cancel() }
        }.preferredColorScheme(.dark)
    }
    private func finishStroke() {
        defer { strokePoints.removeAll() }
        guard brushEnabled, !saving, !compare, !strokePoints.isEmpty else { return }
        var range: ClosedRange<Float>?
        if protectFocus, let value = session.field.focusValue(x: Double(focus.x), y: Double(focus.y)), let bounds = session.field.bounds {
            let margin = max(0.0001,(bounds.upper-bounds.lower)*0.05)
            range = max(0.000001,value-margin)...(value+margin)
        }
        if !history.append(.init(points: strokePoints, mode: brushMode, radius: brushRadius, softness: softness, protectedRange: range)) {
            message = "교정 횟수/점 한도에 도달했습니다. 실행 취소 후 다시 시도하세요."
        }
    }
    private func refresh(_ value: DepthPreviewRequest) async {
        do {
            try await Task.sleep(for: .milliseconds(150)); rendering = true
            let pixels = try await editor.preview(aperture: value.aperture, focus: CGPoint(x: value.x, y: value.y), profile: value.profile, original: value.original, corrections: value.corrections, diagnostic: value.diagnostic)
            try Task.checkCancellation(); image = try pixels.cgImage(); rendering = false
        } catch is CancellationError { }
        catch { if !Task.isCancelled { message = error.localizedDescription; rendering = false } }
    }
    private func save() {
        let f = aperture, point = focus, lens = profile, edits = history.current
        saving = true; message = nil
        saveTask = Task {
            defer { saving = false; saveTask = nil }
            do {
                try await beforeSave?()
                try Task.checkCancellation()
                _ = try await editor.save(aperture: f, focus: point, profile: lens, corrections: edits)
                message = "새 심도 사진을 앱 보관함에 저장했습니다."
            } catch is CancellationError { message = "저장을 취소했습니다. 원본과 이전 결과는 보존됩니다." }
            catch { message = error.localizedDescription }
        }
    }
}
