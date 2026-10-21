import SwiftUI

@MainActor
struct FilmStylesView: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (ImportedLUT) async throws -> Void
    @State private var query = ""
    @State private var category = "전체"
    @State private var presets: [FilterPreset] = []
    @State private var busy = false
    @State private var message: String?
    private var categories: [String] { ["전체"] + Set(FilmStyle.all.map(\.category)).sorted() }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("PhotoP 자체 제작 12종 · sRGB SDR\n브랜드 필름의 공식 재현이 아닙니다. 색상표 미리보기는 사진 품질 평가를 대신하지 않습니다.").font(.caption)
                    Picker("카테고리", selection: $category) { ForEach(categories, id: \.self) { Text($0) } }
                }
                Section("자체 스타일") {
                    ForEach(FilmStyle.search(query, category: category)) { style in
                        Button {
                            select { try await Task.detached { try style.imported() }.value }
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(style.name).font(.headline)
                                Text(style.detail).font(.caption).foregroundStyle(.secondary)
                                HStack(spacing: 1) {
                                    ForEach(FilmStyle.chart.indices, id: \.self) { i in
                                        let c = style.color(FilmStyle.chart[i])
                                        Rectangle().fill(Color(.sRGB, red: c.x, green: c.y, blue: c.z, opacity: 1)).frame(height: 24)
                                    }
                                }.accessibilityLabel("생성 색상표 미리보기")
                            }
                        }
                    }
                }
                Section("사용자 프리셋 · 전체 룩") {
                    ForEach(presets.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { preset in
                        VStack(alignment: .leading) {
                            Button(preset.name) { select { try await FilterPresetLibrary.shared.load(preset.id) } }
                            if let p = preset.provenance {
                                Text("\(p.creator) · \(p.license)\n\(p.source)").font(.caption2).textSelection(.enabled)
                            } else { Text("사용자 LUT · 권리는 원본 제공 조건을 확인하세요.").font(.caption2) }
                            Text("강도 \(Int(preset.settings.intensity * 100))% · LUT SHA256 \(preset.lutSHA256)").font(.caption2).textSelection(.enabled)
                        }
                    }.onDelete { offsets in
                        let visible = presets.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
                        Task {
                            do { for i in offsets { try await FilterPresetLibrary.shared.remove(visible[i].id) }; try await reload() }
                            catch { message = error.localizedDescription }
                        }
                    }
                    if presets.isEmpty { Text("편집 화면에서 전체 룩을 저장하면 여기에 표시됩니다.").font(.caption) }
                }
                Section {
                    Text("자체 프로파일: PhotoP Project / PhotoP-Style-Permission-1. 상업 이용·재배포 시 PhotoP Project 크레딧. 외부 LUT에는 이 허가가 적용되지 않습니다. Hald 가져오기는 level 2~8, 8비트 RGB sRGB PNG만 지원합니다.").font(.caption)
                    if busy { ProgressView() }
                    if let message { Text(message).font(.caption) }
                }
            }.disabled(busy)
            .searchable(text: $query, prompt: "이름·장면 검색")
            .navigationTitle("스타일·프리셋")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() }.disabled(busy) } }
            .interactiveDismissDisabled(busy)
            .task { do { try await reload() } catch { message = error.localizedDescription } }
        }.preferredColorScheme(.dark)
    }
    private func reload() async throws { presets = try await FilterPresetLibrary.shared.entries() }
    private func select(_ load: @escaping () async throws -> ImportedLUT) {
        busy = true
        Task {
            defer { busy = false }
            do { let imported = try await load(); try await onSelect(imported); dismiss() }
            catch { message = error.localizedDescription }
        }
    }
}
