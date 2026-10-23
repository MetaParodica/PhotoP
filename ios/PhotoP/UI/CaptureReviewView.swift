import SwiftUI

// Shows the most recent original right after capture, with its actual file facts and next actions.
@MainActor
struct CaptureReviewView: View {
    @ObservedObject var model: CameraModel
    let open: (CameraScreen) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var preview: PhotoThumbnailImage?
    @State private var index = 0
    @State private var previewURL: URL?

    private var originals: [URL] {
        let source = model.latestOriginals.isEmpty ? (model.latestOriginal.map { [$0] } ?? []) : model.latestOriginals
        return (model.latestRendered.map { [$0] } ?? []) + model.latestRenderedSeries.filter { $0 != model.latestRendered } + source
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if originals.isEmpty {
                    ContentUnavailableView("아직 촬영한 사진이 없습니다.", systemImage: "camera",
                                           description: Text("촬영하면 원본을 바로 여기서 확인합니다."))
                } else {
                    photo.frame(maxHeight: .infinity)
                    if originals.count > 1 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(originals.indices, id: \.self) { i in
                                    Button((model.latestRenderedSeries.contains(originals[i]) ? "효과 결과 " : "원본 ") + "\(i + 1)") { index = i }
                                        .buttonStyle(.bordered).accessibilityAddTraits(index == i ? .isSelected : [])
                                }
                            }
                        }.padding(.horizontal)
                    }
                    facts
                    if let current {
                        DisclosureGroup("AI 촬영 리뷰") { PhotoReviewPanel(model: model, url: current) }
                            .padding(.horizontal).accessibilityIdentifier("camera.review.coach")
                    }
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
        if let preview, previewURL == current {
            Image(decorative: preview.image, scale: 1).resizable().scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 12)).padding(.horizontal)
                .accessibilityLabel("최근 촬영 \(current.map { model.latestRenderedSeries.contains($0) } == true ? "효과 결과" : "원본") 미리보기")
        } else {
            ProgressView("원본 미리보기 불러오는 중").frame(maxWidth: .infinity)
        }
    }

    private var facts: some View {
        VStack(spacing: 4) {
            if let current {
                Text(model.latestRenderedSeries.contains(current) ? "효과 적용 결과 · \(model.latestCaptureLook?.displayName ?? "심도")" : "무보정 원본 · 룩 미적용")
                    .font(.caption.weight(.semibold)).accessibilityIdentifier("camera.review.effectStatus")
                if let failure = model.latestRenderErrors[current] {
                    Text("효과 결과 생성 실패 · 원본은 보존됨\n" + failure).font(.caption).foregroundStyle(.orange)
                }
                Text(current.pathExtension.uppercased() + (model.latestPhotoResolution.map { " · \($0.title)" } ?? ""))
                    .font(.system(.subheadline, design: .monospaced))
                Text((model.latestRenderedSeries.isEmpty ? "앱 원본 보관" : "앱 원본·결과 별도 보관") + (model.savedToPhotos ? " · 사진 앱 저장됨" : " · 사진 앱 미저장"))
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
                    Button { if model.prepareEditor(for: current) { open(.editor) } } label: { Label("원본에서 룩 편집", systemImage: "slider.horizontal.3") }
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
        preview = nil; previewURL = nil
        guard let current else { return }
        let task = Task.detached(priority: .userInitiated) { PhotoThumbnail.make(current, maxPixel: 2048) }
        let image = await task.value
        guard !Task.isCancelled, self.current == current else { return }
        preview = image; previewURL = current
    }
}
