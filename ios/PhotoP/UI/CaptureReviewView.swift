import SwiftUI

// Shows the most recent original right after capture, with its actual file facts and next actions.
@MainActor
struct CaptureReviewView: View {
    @ObservedObject var model: CameraModel
    let open: (CameraScreen) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var preview: PhotoThumbnailImage?
    @State private var index = 0

    private var originals: [URL] { model.latestOriginals.isEmpty ? (model.latestOriginal.map { [$0] } ?? []) : model.latestOriginals }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if originals.isEmpty {
                    ContentUnavailableView("아직 촬영한 사진이 없습니다.", systemImage: "camera",
                                           description: Text("촬영하면 원본을 바로 여기서 확인합니다."))
                } else {
                    photo.frame(maxHeight: .infinity)
                    if originals.count > 1 {
                        Picker("브래킷 원본", selection: $index) {
                            ForEach(originals.indices, id: \.self) { Text("원본 \($0 + 1)").tag($0) }
                        }.pickerStyle(.segmented).padding(.horizontal)
                    }
                    facts
                    actions
                }
                library
            }.padding(.vertical)
            .navigationTitle("최근 촬영").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() } } }
            .task(id: originals.indices.contains(index) ? originals[index] : nil) { await load() }
            .onChange(of: originals) { _, _ in index = min(index, max(0, originals.count - 1)) }
        }.preferredColorScheme(.dark)
    }

    private var current: URL? { originals.indices.contains(index) ? originals[index] : nil }

    @ViewBuilder private var photo: some View {
        if let preview {
            Image(decorative: preview.image, scale: 1).resizable().scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 12)).padding(.horizontal)
                .accessibilityLabel("최근 촬영 원본 미리보기")
        } else {
            ProgressView("원본 미리보기 불러오는 중").frame(maxWidth: .infinity)
        }
    }

    private var facts: some View {
        VStack(spacing: 4) {
            if let current {
                Text(current.pathExtension.uppercased() + (model.latestPhotoResolution.map { " · \($0.title)" } ?? ""))
                    .font(.system(.subheadline, design: .monospaced))
                Text(model.savedToPhotos ? "앱 원본 보관 · 사진 앱 저장됨" : "앱 원본 보관 · 사진 앱 미저장")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.accessibilityElement(children: .combine)
    }

    private var actions: some View {
        HStack(spacing: 12) {
            if let current {
                ShareLink(item: current) { Label("공유", systemImage: "square.and.arrow.up") }.buttonStyle(.bordered)
                if !model.savedToPhotos {
                    Button { Task { await model.saveLatestToPhotos() } } label: { Label("사진 앱에 저장", systemImage: "photo.badge.plus") }
                        .buttonStyle(.bordered).disabled(model.busy)
                }
                if current.pathExtension.lowercased() != "dng" {
                    Button { open(.editor) } label: { Label("사진 편집", systemImage: "slider.horizontal.3") }
                        .buttonStyle(.borderedProminent)
                }
            }
        }.font(.subheadline)
    }

    private var library: some View {
        HStack(spacing: 12) {
            Button { open(.history) } label: { Label("편집 기록", systemImage: "photo.stack") }
            Button { open(.videos) } label: { Label("영상 보관함", systemImage: "video") }
            if let video = model.latestVideo {
                ShareLink(item: video.url) { Label("최근 영상", systemImage: "video.badge.ellipsis") }
            }
        }.buttonStyle(.bordered).font(.subheadline)
    }

    private func load() async {
        preview = nil
        guard let current else { return }
        preview = await Task.detached(priority: .userInitiated) { PhotoThumbnail.make(current, maxPixel: 2048) }.value
    }
}
