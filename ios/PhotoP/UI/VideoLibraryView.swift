import AVKit
import SwiftUI

@MainActor
struct VideoLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var library = VideoLibrarySnapshot()
    @State private var busy = false
    @State private var message: String?
    @State private var selected: StoredVideo?

    var body: some View {
        NavigationStack {
            List {
                Section("영상 원본") {
                    if library.videos.isEmpty { Text("보관한 영상이 없습니다.").foregroundStyle(.secondary) }
                    ForEach(library.videos) { item in
                        Button { Task { await open(item) } } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "video.fill").foregroundStyle(.purple).frame(width: 32)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(item.manifest.configuration.resolution.title) · \(item.manifest.actual.codec.title)")
                                    Text(String(format: "%.1f초 · %.0f fps · %@", item.manifest.actual.durationSeconds, item.manifest.actual.nominalFrameRate, VideoCapturePolicy.audioLabel(item.manifest.configuration)))
                                        .font(.caption).foregroundStyle(.secondary)
                                    Text(item.createdAt, style: .date).font(.caption2).foregroundStyle(.secondary)
                                    if item.manifest.recoveredFromPending == true { Text("파일 정보에서 복구").font(.caption2).foregroundStyle(.secondary) }
                                }
                                Spacer(); Image(systemName: "play.circle").font(.title2)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
                if !library.pending.isEmpty {
                    Section {
                        ForEach(library.pending) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(item.url.lastPathComponent).font(.caption).lineLimit(1)
                                Text(ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file)).font(.caption2).foregroundStyle(.secondary)
                                HStack {
                                    Button("검사 후 복구") { Task { await recover(item) } }.buttonStyle(.bordered)
                                    ShareLink("미완료 원본 공유", item: item.url).buttonStyle(.bordered)
                                }
                            }.padding(.vertical, 4)
                        }
                    } header: { Text("완료되지 않은 파일") } footer: {
                        Text("기록이 완료된 SDR MOV(오디오 트랙 0~1개)만 복구할 수 있습니다. 손상 파일은 그대로 보관합니다. 복구 구성은 원래 촬영 요청이 아닌 파일 정보에서 추정합니다.")
                    }
                }
                if library.rejectedCount > 0 {
                    Text("검사할 수 없는 항목 \(library.rejectedCount)개를 열지 않았습니다. 파일은 유지합니다.").font(.caption).foregroundStyle(.secondary)
                }
                if let message { Text(message).font(.callout).accessibilityAddTraits(.updatesFrequently) }
            }.disabled(busy)
                .overlay { if busy { ProgressView("파일 확인 중…").padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
                .navigationTitle("영상 보관함")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() }.disabled(busy) } }
                .task { await reload() }
                .refreshable { await reload() }
                .sheet(item: $selected) { VerifiedVideoView(item: $0) }
        }.preferredColorScheme(.dark)
    }

    private func reload() async {
        do {
            library = try await Task.detached(priority: .utility) { try VideoStore.library(in: VideoStore.root()) }.value
        } catch { message = error.localizedDescription }
    }
    private func open(_ item: StoredVideo) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do { _ = try await VideoStore.verify(item); selected = item }
        catch { message = error.localizedDescription }
    }
    private func recover(_ item: PendingVideo) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            _ = try await VideoStore.recover(item.url, in: VideoStore.root())
            message = "영상 원본을 복구했습니다. Photos 저장은 영상을 열어 선택해 주세요."
            await reload()
        } catch { message = error.localizedDescription }
    }
}

@MainActor
private struct VerifiedVideoView: View {
    let item: StoredVideo
    @State private var player: AVPlayer
    @State private var saving = false
    @State private var message: String?
    init(item: StoredVideo) {
        self.item = item
        _player = State(initialValue: AVPlayer(url: item.url))
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VideoPlayer(player: player)
                HStack {
                    ShareLink("원본 공유", item: item.url).buttonStyle(.bordered)
                    Button("Photos에 저장") {
                        saving = true
                        Task {
                            defer { saving = false }
                            do { try await VideoStore.addToPhotos(item.url); message = "사진 보관함에 저장했습니다." }
                            catch { message = error.localizedDescription }
                        }
                    }.buttonStyle(.borderedProminent).disabled(saving)
                }
                if let message { Text(message).font(.caption) }
                Text("해시를 확인한 SDR 무음 원본 · LUT 비굽기").font(.caption).foregroundStyle(.secondary)
            }.padding().navigationTitle("영상 원본").navigationBarTitleDisplayMode(.inline)
                .onAppear { player.play() }.onDisappear { player.pause() }
        }.preferredColorScheme(.dark)
    }
}
