@preconcurrency import AVFoundation
import AVKit
import SwiftUI

@MainActor
struct VideoDepthEditorView: View {
    let item: StoredVideo
    private let framePreview = VideoDepthFramePreview()
    @State private var thumbnail: UIImage?
    @State private var playhead = 0.0
    @State private var timeline = false
    @State private var events: [VideoDepthKeyframe] = []
    @State private var interpolation: VideoDepthInterpolation = .smooth
    @State private var previewing = false
    @State private var previewRevision = UUID()
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
                Text("원본은 보존합니다. 아래 화면을 터치해 초점/추적 대상을 선택하세요. AI 깊이는 상대값이며 미터 단위 거리가 아닙니다.").font(.caption)
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
                DepthLensPicker(selection: $profile)
                Toggle("선택 피사체 추적", isOn: $tracking).onChange(of: tracking) { _, _ in selection = tracking ? .init(point: focus, mode: mode) : nil }
                if tracking {
                    Picker("추적 대상", selection: $mode) { ForEach(SubjectTrackingMode.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented).accessibilityIdentifier("video.depth.mode")
                        .onChange(of: mode) { _, _ in selection = .init(point: focus, mode: mode) }
                }
                Picker("출력 품질", selection: $quality) { ForEach(VideoDepthQuality.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented).accessibilityIdentifier("video.depth.quality")
                DisclosureGroup("시간별 초점·f값 전환") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("키프레임 사용", isOn: $timeline).onChange(of: timeline) { _, enabled in
                            if enabled, events.isEmpty { events = [.init(time: 0,focus: focus,aperture: aperture,profile: profile,selection: tracking ? selection : nil,requiresTracking: tracking)] }
                        }
                        if timeline {
                            Text(String(format: "현재 %.2f초 / %.2f초",playhead,item.manifest.actual.durationSeconds)).font(.caption)
                            Slider(value: $playhead,in: 0...max(0.01,item.manifest.actual.durationSeconds-0.05))
                                .accessibilityIdentifier("video.depth.time")
                            Picker("전환",selection: $interpolation) { ForEach(VideoDepthInterpolation.allCases,id: \.self) { Text($0.title).tag($0) } }.pickerStyle(.menu)
                            Button("현재 초점·f값을 이 시점에 저장") { setKeyframe() }.disabled(events.count >= 64)
                            ForEach(events, id: \.time) { event in
                                HStack {
                                    Button(String(format: "%.2f초 · f/%.1f",event.time,event.aperture)) { playhead = event.time; focus = event.focus; aperture = event.aperture; profile = event.profile }
                                    Spacer()
                                    if event.time > 0 { Button("삭제") { events.removeAll { $0.time == event.time } } }
                                }.font(.caption)
                            }
                            Button(previewing ? "미리보기 처리 중…" : "현재 시점 전환 미리보기") { previewRevision = UUID() }
                                .disabled(previewing || tracking)
                            Text("슬라이더는 원본의 해당 프레임을 표시합니다. 전환 미리보기는 현재 시점의 심도이며 추적 결과는 전체 처리 후 확인합니다. 대상/렌즈 변경은 해당 시점에서 적용합니다.").font(.caption2)
                        }
                    }.disabled(progress != nil || thumbnail == nil)
                }
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
                Text("키프레임을 끄면 현재 설정이 전체 영상에 적용됩니다. SDR·원본 해상도/프레임 시각/오디오 유지 · 공유 결과 위치 제거 · AI 처리 메타데이터 기록. 추적 불확실/깊이 추정 실패 프레임은 원본을 유지하며 결과에 개수를 알립니다. 최대4K/60fps·10분, 처리는 실시간보다 느릴 수 있습니다.").font(.caption2).foregroundStyle(.secondary)
                ForEach(results) { result in
                    Button { Task { do { try await VideoDepthStore.verify(result); selected = result } catch { message = error.localizedDescription } } } label: {
                        Label("심도 영상 재생 · 원본 유지 \(result.recipe.fallbackFrames)/\(result.recipe.frames)프레임", systemImage: "play.rectangle")
                    }.buttonStyle(.bordered)
                }
            }.padding()
        }.navigationTitle("영상 심도").navigationBarTitleDisplayMode(.inline)
            .task { await load() }
            .onDisappear { task?.cancel() }
            .task(id: playhead) {
                guard timeline else { return }
                do {
                    try await Task.sleep(for: .milliseconds(150))
                    let pixels = try await framePreview.image(url: item.url,time: playhead)
                    try Task.checkCancellation(); thumbnail = UIImage(cgImage: try pixels.cgImage())
                } catch { if !Task.isCancelled { message = error.localizedDescription } }
            }
            .task(id: previewRevision) {
                let time = playhead, revision = previewRevision, intent = editingIntent
                guard timeline, let parameters = intent.parameters(at: time) else { return }
                previewing = true; defer { previewing = false }
                do {
                    let pixels = try await framePreview.image(url: item.url,time: time,parameters: parameters)
                    try Task.checkCancellation()
                    guard playhead == time, previewRevision == revision, editingIntent == intent else { return }
                    focus = parameters.focus; aperture = parameters.aperture; profile = parameters.profile
                    thumbnail = UIImage(cgImage: try pixels.cgImage())
                } catch { if !Task.isCancelled { message = error.localizedDescription } }
            }
            .sheet(item: $selected) { VideoDepthPlaybackView(result: $0, original: item.url) }
    }
    private var editingIntent: VideoDepthIntent {
        VideoDepthIntent(quality: quality,keyframes: events,interpolation: interpolation)
    }
    private func setKeyframe() {
        let time = (playhead * 100).rounded() / 100
        let value = VideoDepthKeyframe(time: time,focus: focus,aperture: aperture,profile: profile,
            selection: tracking ? selection : nil,requiresTracking: tracking)
        events.removeAll { abs($0.time-time) < 0.005 }; events.append(value); events.sort { $0.time < $1.time }
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
        let intent = recorded ?? (timeline ? editingIntent : VideoDepthIntent(quality: quality, keyframes: [.init(time: 0, focus: focus, aperture: aperture, profile: profile, selection: tracking ? selection : nil, requiresTracking: tracking)]))
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
