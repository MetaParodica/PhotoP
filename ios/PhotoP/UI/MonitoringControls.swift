import SwiftUI

@MainActor
struct MonitoringControls: View {
    @ObservedObject var model: CameraModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("SDR 프리뷰 분석 · LUT 적용 전") {
                    Toggle("RGB·휘도 히스토그램", isOn: $model.monitoring.histogram)
                    Toggle("Zebra · 밝은 채널", isOn: $model.monitoring.zebra)
                    Slider(value: $model.monitoring.zebraThreshold, in: 0.5...1) { Text("Zebra 임계값") }
                    Text("Zebra \(Int(model.monitoring.zebraThreshold * 100))%")
                    Toggle("포커스 피킹 · 빨간 경계", isOn: $model.monitoring.peaking)
                    Slider(value: $model.monitoring.peakingThreshold, in: 0.01...1) { Text("피킹 경계 임계값") }
                    Text("피킹 경계 \(Int(model.monitoring.peakingThreshold * 100))%")
                }.disabled(model.busy)
                Section {
                    Button(model.livePreview == nil ? "모니터 켜기" : "현재 프리뷰에 적용") { Task { await model.enableMonitoring() } }
                        .disabled(!model.monitoring.enabled || model.busy || model.snapshot.isApplyingSettings || model.snapshot.state != .running)
                    Button("LUT·모니터 모두 끄기") { model.disableLiveLUT() }.disabled(model.livePreview == nil || model.busy)
                    Text("히스토그램은 최대 256px 격자의 표본이며 초당 최대 4회 갱신합니다. Zebra는 SDR 채널값, 피킹은 명암 경계입니다. RAW 센서 클리핑이나 정확한 초점 거리를 측정하지 않습니다.")
                        .font(.caption)
                    Text("현재 모니터를 켠 동안 렌즈 전환·터치 AF/AE·RAW 촬영을 제한합니다. 사진 원본에는 보조 표시를 넣지 않습니다.").font(.caption)
                    if let message = model.message { Text(message).font(.caption) }
                }
            }
            .navigationTitle("촬영 보조")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() } } }
            .onChange(of: model.monitoring) { _, _ in model.updateMonitoring() }
        }.preferredColorScheme(.dark)
    }
}

struct PreviewHistogramView: View {
    let histogram: PreviewHistogram
    var body: some View {
        VStack(spacing: 2) {
            Canvas { context, size in
                let peak = Double(histogram.bins.flatMap { $0 }.max() ?? 0)
                guard peak > 0 else { return }
                let colors: [Color] = [.red, .green, .blue, .white]
                for (channel, bins) in histogram.bins.enumerated() where channel < 4 {
                    var path = Path()
                    for (index, value) in bins.enumerated() {
                        let point = CGPoint(x: Double(index) / 63 * size.width,
                                            y: size.height * (1 - Double(value) / peak))
                        if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                    context.stroke(path, with: .color(colors[channel]), lineWidth: 1)
                }
            }.frame(width: 120, height: 44)
            Text("SDR RGB/Y · \(histogram.sampleCount) 표본").font(.system(size: 8))
        }.padding(5).background(.black.opacity(0.65))
            .accessibilityLabel("SDR RGB 및 휘도 히스토그램, 표본 \(histogram.sampleCount)개")
            .allowsHitTesting(false)
    }
}
