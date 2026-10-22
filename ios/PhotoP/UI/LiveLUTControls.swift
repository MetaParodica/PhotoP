import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct LiveLUTControls: View {
    @ObservedObject var model: CameraModel
    @Environment(\.dismiss) private var dismiss
    @State private var profileConfirmed = false
    @State private var importing = false
    @State private var showFavorites = false
    @State private var showStyles = false
    @State private var savePreset = false
    @State private var presetName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("촬영 결과 룩 · 미리보기 없음") {
                    Text(model.liveLUTTitle ?? "사용자 .cube를 가져오세요")
                    if let credit = model.liveCredit { Text(credit).font(.caption2).textSelection(.enabled) }
                    Toggle("LUT 입력·출력이 sRGB임을 확인", isOn: $profileConfirmed)
                    Button(".cube / Hald PNG 가져오기") { importing = true }
                        .disabled(!profileConfirmed || model.busy || model.snapshot.isApplyingSettings)
                    Button("즐겨찾기에서 불러오기") { showFavorites = true }
                        .disabled(model.busy || model.snapshot.isApplyingSettings)
                    Button("스타일·사용자 프리셋") { showStyles = true }
                        .disabled(model.busy || model.snapshot.isApplyingSettings)
                    Button("전체 룩 저장") { savePreset = true }.disabled(model.busy || !model.liveUsesLUT)
                    Button("현재 LUT 즐겨찾기에 저장") { Task { await model.favoriteLiveLUT() } }
                        .disabled(model.liveLUTTitle == nil || model.busy)
                    Button("룩 적용 해제") { Task { await model.selectOriginalLook() } }.disabled(!model.liveUsesLUT || model.busy)
                    Slider(value: $model.liveIntensity, in: 0...1) { Text("LUT 강도") }
                        .disabled(!model.liveUsesLUT)
                    Text(model.liveIntensity, format: .percent.precision(.fractionLength(0)))
                    Slider(value: $model.liveGrain, in: 0...1) { Text("기본 필름 그레인") }.disabled(!model.liveUsesLUT)
                    Text("그레인 \(Int(model.liveGrain * 100))% · 기본 단색 입자")
                    FilmFinishControls(settings: $model.liveFinish).disabled(!model.liveUsesLUT)
                    Text("카메라·예시 미리보기에는 룩을 적용하지 않습니다. 촬영 후 SDR JPEG 결과물을 만들고 원본은 그대로 보존합니다. RAW와 영상에는 적용하지 않습니다.").font(.caption)
                }
                Section {
                    Text("발열·저전력 상태에 따라 처리 해상도와 분석 빈도를 자동으로 낮춥니다. 센서 프레임레이트와 사진 해상도는 이 설정으로 변경하지 않습니다.").font(.caption)
                    Text("카메라는 sRGB SDR 프리뷰를 제공합니다. 프리뷰 중에도 터치 초점·길게 눌러 AE/AF 고정을 사용할 수 있습니다.")
                        .font(.caption)
                    if model.busy { ProgressView() }
                    if let message = model.message { Text(message).font(.caption) }
                }
            }
            .navigationTitle("촬영 룩")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() } } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.item]) { result in
                switch result {
                case .success(let url): Task { await model.importLiveLUT(url) }
                case .failure(let error): model.message = error.localizedDescription
                }
            }
            .alert("전체 룩 저장", isPresented: $savePreset) {
                TextField("프리셋 이름", text: $presetName)
                Button("저장") { Task { await model.saveLivePreset(name: presetName) } }
                Button("취소", role: .cancel) { }
            }
            .sheet(isPresented: $showStyles) {
                FilmStylesView { imported in try await model.useLiveLUT(imported) }
            }
            .sheet(isPresented: $showFavorites) {
                LUTFavoritesView { imported in try await model.useLiveLUT(imported) }
            }
            .onChange(of: model.liveFinish) { _, _ in model.updateLiveIntensity() }
            .onChange(of: model.liveGrain) { _, _ in model.updateLiveIntensity() }
            .onChange(of: model.liveIntensity) { _, _ in model.updateLiveIntensity() }
            .onChange(of: model.liveCompareOriginal) { _, _ in model.updateLiveIntensity() }
        }.preferredColorScheme(.dark)
    }
}
