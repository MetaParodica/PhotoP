@preconcurrency import AVFoundation
import AVKit
import SwiftUI

@MainActor
struct VideoDepthEditorView: View {
    let item: StoredVideo
    @State private var thumbnail: UIImage?
    @State private var focus = CGPoint(x: 0.5, y: 0.5)
    @State private var aperture = 2.8
    @State private var profile: DepthLensProfile = .natural
    @State private var quality: VideoDepthQuality = .high
    @State private var tracking = false
    @State private var mode: SubjectTrackingMode = .object
    @State private var selection: SubjectTrackingSelection?
    @State private var progress: Double?
    @State private var message: String?
    @State private var jobID: UUID?
    @State private var task: Task<Void, Never>?
    @State private var recordedIntent: VideoDepthIntent?
    @State private var results: [VideoDepthResult] = []
    @State private var selected: VideoDepthResult?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("영상 AI 심도 편집").font(.title2.bold())
                Text("원본은 보존합니다. 아래 원본 첫 화면을 터치해 초점/추적 대상을 선택하세요. AI 깊이는 상대값이며 미터 단위 거리가 아닙니다.").font(.caption)
                if let thumbnail {
                    GeometryReader { geometry in
                        let rect = GuideGeometry.imageRect(image: thumbnail.size, viewport: geometry.size)
                        Image(uiImage: thumbnail).resizable().scaledToFit().frame(width: geometry.size.width, height: geometry.size.height)
                            .overlay {
                                Circle().stroke(.green, lineWidth: 2).frame(width: 28, height: 28)
                                    .position(x: rect.minX + rect.width * focus.x, y: rect.minY + rect.height * focus.y)
                            }
                            .contentShape(Rectangle()).gesture(SpatialTapGesture().onEnded { event in
                                guard progress == nil, let point = GuideGeometry.normalizedPoint(event.location, in: rect) else { return }
                                focus = point; selection = tracking ? .init(point: point, mode: mode) : nil
                            })
                    }.frame(height: 260).accessibilityElement(children: .contain).accessibilityIdentifier("video.depth.target")
                } else { ProgressView("원본 화면 읽는 중…").frame(height: 160) }
                CameraValueSlider(title: "심도 f값", value: $aperture, range: 1.4...16, display: { String(format: "f/%.1f", $0) }, onCommit: {})
                Picker("보케 렌즈", selection: $profile) { ForEach(DepthLensProfile.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                Toggle("선택 피사체 추적", isOn: $tracking).onChange(of: tracking) { _, _ in selection = tracking ? .init(point: focus, mode: mode) : nil }
                if tracking {
                    Picker("추적 대상", selection: $mode) { ForEach(SubjectTrackingMode.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented).accessibilityIdentifier("video.depth.mode")
                        .onChange(of: mode) { _, _ in selection = .init(point: focus, mode: mode) }
                }
                Picker("출력 품질", selection: $quality) { ForEach(VideoDepthQuality.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented).accessibilityIdentifier("video.depth.quality")
                if let progress {
                    ProgressView(value: progress).accessibilityIdentifier("video.depth.progress")
                    Button("처리 취소") { task?.cancel() }.buttonStyle(.bordered)
                } else {
                    Button("별도 심도 영상 만들기") { render(nil) }.buttonStyle(.borderedProminent).disabled(thumbnail == nil)
                        .accessibilityIdentifier("video.depth.render")
                    if let recordedIntent {
                        Button("촬영 당시 시간별 설정으로 만들기") { render(recordedIntent) }.buttonStyle(.bordered).disabled(thumbnail == nil)
                    }
                }
                if let message { Text(message).font(.caption).accessibilityIdentifier("video.depth.message") }
                Text("현재 설정은 전체 영상에 적용됩니다. SDR·원본 해상도/프레임 시각/오디오 유지 · 공유 결과 위치 제거 · AI 처리 메타데이터 기록. 추적 불확실/깊이 추정 실패 프레임은 원본을 유지하며 결과에 개수를 알립니다. 최대4K/60fps·10분, 처리는 실시간보다 느릴 수 있습니다.").font(.caption2).foregroundStyle(.secondary)
                ForEach(results) { result in
                    Button { Task { do { try await VideoDepthStore.verify(result); selected = result } catch { message = error.localizedDescription } } } label: {
                        Label("심도 영상 재생 · 원본 유지 \(result.recipe.fallbackFrames)/\(result.recipe.frames)프레임", systemImage: "play.rectangle")
                    }.buttonStyle(.bordered)
                }
            }.padding()
        }.navigationTitle("영상 심도").navigationBarTitleDisplayMode(.inline)
            .task { await load() }
            .onDisappear { task?.cancel() }
            .sheet(item: $selected) { VideoDepthPlaybackView(result: $0, original: item.url) }
    }
    private func load() async {
        do {
            _ = try await VideoStore.verify(item)
            let url = item.url
            let image = try await Task.detached(priority: .userInitiated) {
                let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url)); generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 1280, height: 1280)
                return try generator.copyCGImage(at: .zero, actualTime: nil)
            }.value
            thumbnail = UIImage(cgImage: image)
            let sidecar = item.url.deletingLastPathComponent().appendingPathComponent("depth-intent.json")
            if let size = try? sidecar.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 2_000_000,
               let data = try? Data(contentsOf: sidecar), let saved = try? JSONDecoder().decode(VideoDepthIntent.self, from: data), saved.valid,
               let first = saved.keyframes.first {
                recordedIntent = saved
                focus = first.focus; aperture = first.aperture; profile = first.profile; quality = saved.quality
                selection = first.selection; tracking = first.requiresTracking || first.selection != nil; mode = first.selection?.mode ?? .object
            }
            reloadResults()
        } catch { message = error.localizedDescription }
    }
    private func reloadResults() {
        results = (try? VideoDepthStore.library().filter { $0.recipe.originalSHA256 == item.manifest.sha256 }) ?? []
    }
    private func render(_ recorded: VideoDepthIntent?) {
        guard task == nil else { return }
        let intent = recorded ?? VideoDepthIntent(quality: quality, keyframes: [.init(time: 0, focus: focus, aperture: aperture, profile: profile, selection: tracking ? selection : nil, requiresTracking: tracking)])
        let token = UUID(); jobID = token
        progress = 0; message = "AI 심도 처리 중 · 녹화 원본 보존"
        task = Task {
            defer { progress = nil; task = nil; jobID = nil }
            do {
                let original = try await VideoStore.verify(item)
                let result = try await VideoDepthProcessor.shared.render(original, intent: intent, progress: { value in
                    Task { @MainActor in if jobID == token { progress = value } }
                })
                message = "심도 영상 보관 완료 · 적용 \(result.recipe.processedFrames)/\(result.recipe.frames)프레임"
                reloadResults(); selected = result
            } catch is CancellationError { message = "취소했습니다. 원본은 보존했습니다." }
            catch { message = error.localizedDescription }
        }
    }
}

@MainActor
private struct VideoDepthPlaybackView: View {
    let result: VideoDepthResult
    let original: URL
    @State private var player: AVPlayer
    @State private var comparing = false
    @State private var saving = false
    @State private var message: String?
    init(result: VideoDepthResult, original: URL) {
        self.result = result; self.original = original; _player = State(initialValue: AVPlayer(url: result.url))
    }
    var body: some View {
        VStack(spacing: 16) {
            VideoPlayer(player: player)
            Toggle("원본 비교", isOn: $comparing).onChange(of: comparing) { _, value in
                let time = player.currentTime()
                player.replaceCurrentItem(with: AVPlayerItem(url: value ? original : result.url))
                player.seek(to: time); player.play()
            }
            Text("AI 심도 처리 · 위치 정보 제거 · 원본 유지 \(result.recipe.fallbackFrames)/\(result.recipe.frames)프레임").font(.caption)
            HStack {
                ShareLink("심도 영상 공유", item: result.url).buttonStyle(.bordered)
                Button("Photos 저장") {
                    saving = true
                    Task { defer { saving = false }; do { try await VideoStore.addToPhotos(result.url); message = "저장했습니다." } catch { message = error.localizedDescription } }
                }.buttonStyle(.borderedProminent).disabled(saving)
            }
            if let message { Text(message).font(.caption) }
        }.padding().onAppear { player.play() }.onDisappear { player.pause() }.preferredColorScheme(.dark)
    }
}
