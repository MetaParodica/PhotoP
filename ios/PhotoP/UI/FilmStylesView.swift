import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct FilmStylesView: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (ImportedLUT) async throws -> Void
    @State private var query = ""
    @State private var category = "전체"
    @State private var presets: [FilterPreset] = []
    @State private var bundled: [BundledFilmStyle] = []
    @State private var company: [CompanyFilmStyle] = []
    @State private var confirmedSRGB = false
    @State private var importing = false
    @State private var busy = false
    @State private var message: String?
    private var categories: [String] { ["전체"] + Set(FilmStyle.all.map(\.category) + bundled.map(\.category) + company.map(\.category) + ProceduralLook.all.map(\.category)).sorted() }
    private var visiblePresets: [FilterPreset] { presets.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) } }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("PhotoP 컬러 \(FilmStyle.all.count)종 · 공간 효과 \(ProceduralLook.all.count)종 · 외부 룩 \(bundled.count + company.filter { $0.role == "creative" }.count)종 · 기술 LUT \(company.filter { $0.role == "technical" }.count)종\n브랜드 필름·센서의 실측 재현이 아닙니다. 색상표는 생성된 참고 미리보기입니다.").font(.caption)
                    Picker("카테고리", selection: $category) { ForEach(categories, id: \.self) { Text($0) } }
                    Toggle("외부 룩의 SDR 입력·변환 가정 확인", isOn: $confirmedSRGB)
                    Text("표시용 LUT는 sRGB로 가정합니다. V-Log 파생 룩은 SDR→V-Gamut/V-Log→LUT→감마2.4 가정→sRGB로 변환합니다. 센서·HDR 원본을 복원하지 않습니다.").font(.caption)
                    Button("여러 LUT 가져오기 · 최대32개") { importing = true }.disabled(!confirmedSRGB)
                }
                Section("PhotoP 자체 스타일") {
                    ForEach(FilmStyle.search(query, category: category)) { style in ownRow(style) }
                }
                Section("LUT 없는 공간 효과") {
                    ForEach(ProceduralLook.all.filter { (category == "전체" || $0.category == category) && (query.isEmpty || "\($0.name) \($0.detail)".localizedCaseInsensitiveContains(query)) }) { style in
                        Button { select { try style.imported() } } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Label(style.name, systemImage: "sparkles").font(.headline)
                                Text(style.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Text("주변 픽셀을 처리하는 Metal 효과입니다. 색상표로 표현할 수 없습니다. 저장하려면 전체 룩 프리셋을 사용하세요.").font(.caption)
                }
                Section("외부 룩 · slay / CC BY 4.0") {
                    ForEach(bundled.filter { (category == "전체" || $0.category == category) && (query.isEmpty || "\($0.name) \($0.category) \($0.detail)".localizedCaseInsensitiveContains(query)) }) { entry in externalRow(entry) }
                    Link("제작자·원본 저장소", destination: URL(string: "https://github.com/slaycamera/luts")!)
                    Link("CC BY 4.0 라이선스", destination: URL(string: "https://creativecommons.org/licenses/by/4.0/")!)
                    Text("원본 LUT는 변경 없이 포함했습니다. PhotoP와 제작자의 제휴를 의미하지 않습니다. 공유 시 크레딧을 유지하세요.").font(.caption)
                }
                Section("기업 룩 파생·외부 팩 · 원본 전체 포함") {
                    ForEach(company.filter { (category == "전체" || $0.category == category) && (query.isEmpty || "\($0.name) \($0.brand)".localizedCaseInsensitiveContains(query)) }) { entry in companyRow(entry) }
                }
                Section("사용자 프리셋 · 전체 룩") {
                    ForEach(visiblePresets) { preset in
                        VStack(alignment: .leading) {
                            Button(preset.name) { select { try await FilterPresetLibrary.shared.load(preset.id) } }
                            if let p = preset.provenance {
                                Text("\(p.creator) · \(p.license)\n\(p.requiredCredit)").font(.caption2).textSelection(.enabled)
                            } else { Text("사용자 LUT · 권리는 원본 제공 조건을 확인하세요.").font(.caption2) }
                            Text("강도 \(Int(preset.settings.intensity * 100))% · LUT SHA256 \(preset.lutSHA256)").font(.caption2).textSelection(.enabled)
                        }
                    }.onDelete { offsets in
                        let selected = offsets.map { visiblePresets[$0].id }
                        busy = true
                        Task {
                            defer { busy = false }
                            do { for id in selected { try await FilterPresetLibrary.shared.remove(id) }; try await reload() }
                            catch { message = error.localizedDescription }
                        }
                    }
                    if presets.isEmpty { Text("전체 룩 저장·여러 LUT 가져오기를 사용하면 여기에 표시됩니다.").font(.caption) }
                }
                Section {
                    Text("PhotoP 자체 프로파일: PhotoP-Style-Permission-1 / PhotoP Project 크레딧. 외부 LUT에는 해당하지 않습니다. 단독1D(2~65536)·3D(2~65) cube, Hald level2~8의 불투명8bit RGB sRGB PNG를 지원합니다. mixed shaper+3D는 미지원입니다.").font(.caption)
                    if busy { ProgressView() }
                    if let message { Text(message).font(.caption) }
                }
            }.disabled(busy)
            .searchable(text: $query, prompt: "이름·장면 검색")
            .navigationTitle("스타일·프리셋")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() }.disabled(busy) } }
            .interactiveDismissDisabled(busy)
            .task {
                do {
                    bundled = try BundledFilmLibrary.entries(in: BundledFilmLibrary.root())
                    company = try CompanyFilmLibrary.entries(in: CompanyFilmLibrary.root())
                    try await reload()
                }
                catch { message = error.localizedDescription }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                switch result {
                case .failure(let error): message = error.localizedDescription
                case .success(let urls):
                    busy = true
                    Task {
                        defer { busy = false }
                        do {
                            let report = try await LUTBatchImporter.run(urls, confirmedSRGB: confirmedSRGB)
                            try await reload()
                            message = "가져오기 성공 \(report.imported)개 · 실패 \(report.failures.count)개\n" + report.failures.joined(separator: "\n")
                        } catch { message = error.localizedDescription }
                    }
                }
            }
        }.preferredColorScheme(.dark)
    }
    private func ownRow(_ style: FilmStyle) -> some View {
        Button { select { try await Task.detached { try style.imported() }.value } } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(style.name).font(.headline)
                Text(style.detail).font(.caption).foregroundStyle(.secondary)
                patches(FilmStyle.chart.map(style.color))
            }
        }
    }
    private func externalRow(_ entry: BundledFilmStyle) -> some View {
        Button {
            let confirmed = confirmedSRGB
            select { try await Task.detached { try BundledFilmLibrary.load(entry, in: BundledFilmLibrary.root(), confirmedSRGB: confirmed) }.value }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.name).font(.headline)
                Text("\(entry.detail) · sRGB 해석 가정").font(.caption)
                patches(entry.previewColors.map { SIMD3($0[0], $0[1], $0[2]) })
                Text(entry.requiredCredit).font(.caption2)
            }
        }.disabled(!confirmedSRGB)
    }
    private func companyRow(_ entry: CompanyFilmStyle) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                select { try await CompanyLookCompiler.shared.load(entry, in: CompanyFilmLibrary.root()) }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.name).font(.headline)
                    Text("\(entry.brand) · 비공식 파생/외부 미러 · 권리 미확인").font(.caption2)
                    Text(entry.role == "technical" ? "기술 변환" : "크리에이티브 룩").font(.caption2)
                    if entry.canApply { patches(entry.previewColors.map { SIMD3($0[0], $0[1], $0[2]) }) }
                }
            }.disabled(!confirmedSRGB || !entry.canApply)
            if !entry.canApply { Text("출력 WDR 프로파일 미확인 · 적용 없이 원본 제공").font(.caption) }
            HStack {
                if let original = try? CompanyFilmLibrary.original(entry, in: CompanyFilmLibrary.root()) {
                    ShareLink("원본 cube", item: original)
                }
                if let url = URL(string: entry.source) { Link("출처", destination: url) }
            }.font(.caption)
        }
    }
    private func patches(_ colors: [SIMD3<Double>]) -> some View {
        HStack(spacing: 1) {
            ForEach(colors.indices, id: \.self) { i in
                Rectangle().fill(Color(.sRGB, red: colors[i].x, green: colors[i].y, blue: colors[i].z, opacity: 1)).frame(height: 24)
            }
        }.accessibilityLabel("생성 색상표 미리보기")
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
