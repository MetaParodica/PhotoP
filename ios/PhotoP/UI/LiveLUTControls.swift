import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct LiveLUTControls: View {
    @ObservedObject var model: CameraModel
    @Environment(\.dismiss) private var dismiss
    @State private var profileConfirmed = false
    @State private var importing = false
    @State private var showFavorites = false

    var body: some View {
        NavigationStack {
            Form {
                Section("실시간 LUT") {
                    Text(model.liveLUTTitle ?? "사용자 .cube를 가져오세요")
                    Toggle("LUT 입력·출력이 sRGB임을 확인", isOn: $profileConfirmed)
                    Button(".cube 가져오기") { importing = true }
                        .disabled(!profileConfirmed || model.busy || model.snapshot.isApplyingSettings || model.livePreview != nil || model.snapshot.state != .running)
                    Button("즐겨찾기에서 불러오기") { showFavorites = true }
                        .disabled(model.busy || model.snapshot.isApplyingSettings || model.livePreview != nil || model.snapshot.state != .running)
                    Button("현재 LUT 즐겨찾기에 저장") { Task { await model.favoriteLiveLUT() } }
                        .disabled(model.liveLUTTitle == nil || model.busy)
                    Toggle("미리보기 적용", isOn: Binding(get: { model.livePreview != nil }, set: { value in
                        if value { Task { await model.enableLiveLUT() } }
                        else { model.disableLiveLUT() }
                    }))
                    .disabled(model.busy || model.snapshot.isApplyingSettings || model.liveLUTTitle == nil || model.snapshot.state != .running)
                    Slider(value: $model.liveIntensity, in: 0...1) { Text("LUT 강도") }
                        .disabled(model.livePreview == nil)
                    Text(model.liveIntensity, format: .percent.precision(.fractionLength(0)))
                    Slider(value: $model.liveGrain, in: 0...1) { Text("기본 필름 그레인") }.disabled(model.livePreview == nil)
                    Text("그레인 \(Int(model.liveGrain * 100))% · 기본 단색 입자")
                    Toggle("원본 색상과 비교", isOn: $model.liveCompareOriginal).disabled(model.livePreview == nil)
                    Text("미리보기 전용입니다. 촬영 사진에는 LUT를 굽지 않습니다.").font(.caption)
                }
                Section {
                    Text("현재 입력은 8비트 YUV·BT.709 색역의 SDR만 지원합니다. LUT를 끈 뒤 렌즈 전환·터치 AF/AE·다른 LUT 가져오기를 사용할 수 있습니다.")
                        .font(.caption)
                    if model.busy { ProgressView() }
                    if let message = model.message { Text(message).font(.caption) }
                }
            }
            .navigationTitle("LUT 미리보기")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() } } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.item]) { result in
                switch result {
                case .success(let url): Task { await model.importLiveLUT(url) }
                case .failure(let error): model.message = error.localizedDescription
                }
            }
            .sheet(isPresented: $showFavorites) {
                LUTFavoritesView { imported in try await model.useLiveLUT(imported) }
            }
            .onChange(of: model.liveGrain) { _, _ in model.updateLiveIntensity() }
            .onChange(of: model.liveIntensity) { _, _ in model.updateLiveIntensity() }
            .onChange(of: model.liveCompareOriginal) { _, _ in model.updateLiveIntensity() }
        }.preferredColorScheme(.dark)
    }
}
