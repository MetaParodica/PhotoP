import SwiftUI

@MainActor
struct LongExposureView: View {
    @ObservedObject var model: CameraModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("다중 프레임 합성 · SDR · 최대 1280px") {
                    Picker("합성", selection: $model.longConfiguration.blend) {
                        ForEach(LongExposureConfiguration.Blend.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("총 합성 시간", selection: $model.longConfiguration.duration) {
                        ForEach([1.0, 2, 4, 8, 15, 30, 60, 120, 300], id: \.self) { Text("\(Int($0))초").tag($0) }
                    }
                    Stepper("사용자 지정 \(Int(model.longConfiguration.duration))초", value: $model.longConfiguration.duration, in: 1...300, step: 1)
                    Toggle("평행이동 정렬 · ±8px", isOn: $model.longConfiguration.align)
                    Text("삼각대 권장. 총시간은 실제 센서 셔터시간이 아닙니다. 2fps 이하로 SDR 프레임을 누적합니다. 정렬은 회전·원근 보정을 지원하지 않습니다.").font(.caption)
                    Text("프레임 보관 예산 128MiB에 도달하면 일찍 저장합니다. 심한 발열은 샘플 간격을 늘리고 위험 발열은 작업을 취소합니다.").font(.caption)
                }.disabled(model.busy)
                if let progress = model.longProgress {
                    ProgressView(value: progress.fraction)
                    Text("사용 \(progress.accepted) · 정렬 거부 \(progress.rejected)")
                    if let data = progress.previewJPEG, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFit() }
                }
                if model.busy { Button("합성 취소", role: .destructive) { model.cancelLongExposure() } }
                else {
                    Button("합성 시작") { Task { await model.captureLongExposure() } }
                        .disabled(!model.canCapture || model.rawMode != .processed || model.bracketEnabled)
                    if let url = model.latestComposite {
                        ShareLink("결과 JPEG 공유", item: url)
                        Button("현재 합성 방식·정렬로 재처리") { Task { await model.reprocessLongExposure() } }
                        Button("사진 보관함에 저장") { Task { await model.saveCompositeToPhotos() } }.disabled(model.compositeSavedToPhotos)
                    }
                }
                if let message = model.message { Text(message).font(.caption) }
            }
            .navigationTitle("장노출 합성")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() }.disabled(model.busy) } }
            .interactiveDismissDisabled(model.busy)
        }.preferredColorScheme(.dark)
    }
}
