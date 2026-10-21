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
    @State private var grainAmount = 0.0
    @State private var grainSeed: UInt32 = 1
    @State private var revision = 0
    @State private var profileConfirmed = false
    @State private var showOriginal = false
    @State private var importing = false
    @State private var showFavorites = false
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
                    HStack {
                        Button("즐겨찾기 불러오기") { showFavorites = true }.disabled(busy || originalImage == nil)
                        Button("즐겨찾기에 저장") {
                            busy = true
                            Task {
                                defer { busy = false }
                                do { try await editor.favoriteCurrent(); message = "LUT 즐겨찾기에 저장했습니다." }
                                catch { message = error.localizedDescription }
                            }
                        }.disabled(busy || title == nil)
                    }
                    Text("Log/HDR LUT는 아직 지원하지 않습니다.").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Text("강도")
                        Slider(value: $intensity, in: 0...1)
                            .accessibilityLabel("LUT 강도")
                        Text(intensity, format: .percent.precision(.fractionLength(0))).monospacedDigit()
                    }.disabled(title == nil || busy)
                    HStack {
                        Text("그레인")
                        Slider(value: $grainAmount, in: 0...1)
                        Text("\(Int(grainAmount * 100))%")
                    }.disabled(title == nil || busy)
                    Text("기본 단색 입자 · LUT 강도와 별도 조절").font(.caption)
                    Toggle("원본과 비교", isOn: $showOriginal).disabled(originalImage == nil)
                    if busy || rendering { ProgressView() }
                    if let message { Text(message).font(.caption).multilineTextAlignment(.center) }
                    Button("편집본 저장") {
                        busy = true
                        exported = nil
                        Task {
                            defer { busy = false }
                            do {
                                exported = try await editor.export(intensity: intensity, grain: GrainSettings(amount: grainAmount, seed: grainSeed))
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
            .sheet(isPresented: $showFavorites) {
                LUTFavoritesView { imported in
                    busy = true
                    defer { busy = false }
                    title = try await editor.useLUT(imported)
                    profileConfirmed = true
                    exported = nil
                    renderedImage = nil
                    revision += 1
                    message = nil
                }
            }
            .task {
                do {
                    let image = try await editor.loadOriginal()
                    originalImage = UIImage(cgImage: try image.cgImage())
                } catch { message = error.localizedDescription }
            }
            .task(id: "\(revision):\(intensity):\(grainAmount):\(grainSeed)") {
                guard title != nil else { return }
                rendering = true
                do {
                    try await Task.sleep(for: .milliseconds(150))
                    try Task.checkCancellation()
                    let image = try await editor.renderPreview(intensity: intensity, grain: GrainSettings(amount: grainAmount, seed: grainSeed))
                    try Task.checkCancellation()
                    renderedImage = UIImage(cgImage: try image.cgImage())
                    rendering = false
                } catch is CancellationError {
                    // The replacement preview task owns the loading state.
                } catch {
                    if !Task.isCancelled { message = error.localizedDescription; rendering = false }
                }
            }
            .onChange(of: grainAmount) { _, _ in exported = nil }
            .onChange(of: intensity) { _, _ in exported = nil }
        }.preferredColorScheme(.dark)
    }
}
