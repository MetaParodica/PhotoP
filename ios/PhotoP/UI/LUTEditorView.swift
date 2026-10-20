import SwiftUI
import UniformTypeIdentifiers
import UIKit

@MainActor
struct LUTEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var editor: LUTPhotoEditor
    @State private var originalImage: UIImage?
    @State private var renderedImage: UIImage?
    @State private var title: String?
    @State private var intensity = 1.0
    @State private var revision = 0
    @State private var profileConfirmed = false
    @State private var showOriginal = false
    @State private var importing = false
    @State private var busy = false
    @State private var rendering = false
    @State private var message: String?
    @State private var exported: URL?

    init(original: URL) { _editor = State(initialValue: LUTPhotoEditor(original: original)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if let image = showOriginal ? originalImage : (renderedImage ?? originalImage) {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 440)
                            .accessibilityLabel(showOriginal ? "원본 SDR 미리보기" : "LUT 미리보기")
                    } else { ProgressView().frame(height: 240) }
                    Text(title ?? "사용자 LUT 편집").font(.headline)
                    Text("SDR · sRGB / 1024px 미리보기 · 최대 12.6MP 저장\nHDR gain map과 원본 EXIF는 편집본에 포함하지 않습니다.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Toggle("LUT 입력·출력이 sRGB임을 확인", isOn: $profileConfirmed)
                        .disabled(busy || title != nil)
                    Button(".cube 가져오기") { importing = true }
                        .disabled(!profileConfirmed || busy || originalImage == nil)
                    Text("Log/HDR LUT는 아직 지원하지 않습니다.").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Text("강도")
                        Slider(value: $intensity, in: 0...1)
                            .accessibilityLabel("LUT 강도")
                        Text(intensity, format: .percent.precision(.fractionLength(0))).monospacedDigit()
                    }.disabled(title == nil || busy)
                    Toggle("원본과 비교", isOn: $showOriginal).disabled(originalImage == nil)
                    if busy || rendering { ProgressView() }
                    if let message { Text(message).font(.caption).multilineTextAlignment(.center) }
                    Button("편집본 저장") {
                        busy = true
                        exported = nil
                        Task {
                            defer { busy = false }
                            do {
                                exported = try await editor.export(intensity: intensity)
                                message = "원본을 보존하고 JPEG·LUT·레시피를 별도 저장했습니다."
                            } catch { message = error.localizedDescription }
                        }
                    }.buttonStyle(.borderedProminent).disabled(title == nil || busy || rendering)
                    if let exported {
                        ShareLink(item: exported) { Label("편집 JPEG 공유", systemImage: "square.and.arrow.up") }
                    }
                }.padding()
            }
            .navigationTitle("LUT 사진 편집")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() }.disabled(busy) }
            }
            .interactiveDismissDisabled(busy)
            .fileImporter(isPresented: $importing, allowedContentTypes: [.item]) { result in
                switch result {
                case .success(let url):
                    busy = true
                    Task {
                        defer { busy = false }
                        do {
                            title = try await editor.importCube(url)
                            exported = nil
                            renderedImage = nil
                            revision += 1
                            message = nil
                        } catch { message = error.localizedDescription }
                    }
                case .failure(let error): message = error.localizedDescription
                }
            }
            .task {
                do {
                    let image = try await editor.loadOriginal()
                    originalImage = UIImage(cgImage: try image.cgImage())
                } catch { message = error.localizedDescription }
            }
            .task(id: "\(revision):\(intensity)") {
                guard title != nil else { return }
                rendering = true
                do {
                    try await Task.sleep(for: .milliseconds(150))
                    try Task.checkCancellation()
                    let image = try await editor.renderPreview(intensity: intensity)
                    try Task.checkCancellation()
                    renderedImage = UIImage(cgImage: try image.cgImage())
                    rendering = false
                } catch is CancellationError {
                    // The replacement preview task owns the loading state.
                } catch {
                    if !Task.isCancelled { message = error.localizedDescription; rendering = false }
                }
            }
            .onChange(of: intensity) { _, _ in exported = nil }
        }.preferredColorScheme(.dark)
    }
}
