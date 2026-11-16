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
}

@MainActor
struct DepthResultEditorView: View {
    let session: DepthEditSession
    private let editor: DepthPhotoEditor
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
    @State private var saveTask: Task<Void, Never>?

    init(session: DepthEditSession) {
        self.session = session; editor = DepthPhotoEditor(session: session)
        _aperture = State(initialValue: session.recipe.aperture ?? 2.8)
        _focus = State(initialValue: CGPoint(x: session.recipe.focusX, y: session.recipe.focusY))
        _profile = State(initialValue: session.recipe.lensProfile ?? .natural)
    }
    private var request: DepthPreviewRequest {
        .init(aperture: aperture, x: Double(focus.x), y: Double(focus.y), profile: profile, original: compare)
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
                                guard !saving, !compare else { return }
                                focus = CGPoint(x: min(1, max(0, value.location.x / size.width)), y: min(1, max(0, value.location.y / size.height)))
                            }).position(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
                    } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("사진을 터치하여 재초점 · " + String(format: "f/%.1f", aperture))
                    Slider(value: $aperture, in: 1.4...16)
                    Picker("렌즈", selection: $profile) { ForEach(DepthLensProfile.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                    Toggle("원본 비교", isOn: $compare)
                    if rendering { ProgressView("미리보기 갱신 중") }
                    if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
                    if saving { Button("저장 취소") { saveTask?.cancel() } }
                    else { Button("원래 해상도로 새 결과 저장") { save() }.buttonStyle(.borderedProminent) }
                    Text("미리보기는 최대768px입니다. 재초점은 저장된 깊이의 정확도 범위에서 작동합니다. 원본과 이전 결과는 보존합니다.").font(.caption2).foregroundStyle(.secondary)
                }.disabled(saving && saveTask == nil).padding(.horizontal)
            }.padding(.bottom)
                .navigationTitle("사진 재초점")
                .toolbar { Button("닫기") { dismiss() }.disabled(saving) }
                .interactiveDismissDisabled(saving)
                .task(id: request) { await refresh(request) }
                .onChange(of: scenePhase) { _, phase in if phase != .active { saveTask?.cancel() } }
                .onDisappear { saveTask?.cancel() }
        }.preferredColorScheme(.dark)
    }
    private func refresh(_ value: DepthPreviewRequest) async {
        do {
            try await Task.sleep(for: .milliseconds(150)); rendering = true
            let pixels = try await editor.preview(aperture: value.aperture, focus: CGPoint(x: value.x, y: value.y), profile: value.profile, original: value.original)
            try Task.checkCancellation(); image = try pixels.cgImage(); rendering = false
        } catch is CancellationError { }
        catch { if !Task.isCancelled { message = error.localizedDescription; rendering = false } }
    }
    private func save() {
        let f = aperture, point = focus, lens = profile
        saving = true; message = nil
        saveTask = Task {
            defer { saving = false; saveTask = nil }
            do {
                _ = try await editor.save(aperture: f, focus: point, profile: lens)
                message = "새 심도 사진을 앱 보관함에 저장했습니다."
            } catch is CancellationError { message = "저장을 취소했습니다. 원본과 이전 결과는 보존됩니다." }
            catch { message = error.localizedDescription }
        }
    }
}
