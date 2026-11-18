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
                    ScopeControls(settings: $model.monitoring)
                    Toggle("Zebra · 밝은 채널", isOn: $model.monitoring.zebra)
                    Slider(value: $model.monitoring.zebraThreshold, in: 0.5...1) { Text("Zebra 임계값") }
                    Text("Zebra \(Int(model.monitoring.zebraThreshold * 100))%")
                    Toggle("포커스 피킹 · 초록 경계", isOn: $model.monitoring.peaking)
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

struct ScopeControls: View {
    @Binding var settings: MonitoringSettings
    var body: some View {
        Group {
            Text("SDR 프리뷰 분석 · LUT 적용 전").font(.caption)
            Toggle("휘도 파형", isOn: $settings.waveform).accessibilityIdentifier("camera.monitor.waveform")
            Toggle("RGB 퍼레이드", isOn: $settings.rgbParade).accessibilityIdentifier("camera.monitor.parade")
            Toggle("벡터스코프", isOn: $settings.vectorscope).accessibilityIdentifier("camera.monitor.vectorscope")
            Toggle("False color", isOn: $settings.falseColor).accessibilityIdentifier("camera.monitor.falseColor")
            if settings.falseColor {
                Text("SDR 휘도: 0–3% 보라 · 3–10% 파랑 · 10–40% 어두운 회색 · 40–60% 초록 · 60–90% 밝은 회색 · 90–97% 노랑 · 97–100% 빨강. Zebra·피킹 대신 표시합니다.").font(.caption2)
            }
            Text("최대256px 격자·초당 최대4회 통계. 센서/RAW·HDR·Log 측정이나 정확한 IRE 계측이 아닙니다. 원본에는 보조 표시를 넣지 않습니다.").font(.caption2)
        }
    }
}

struct PreviewMonitoringReadouts: View {
    let statistics: PreviewHistogram
    let settings: MonitoringSettings
    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if settings.histogram { PreviewHistogramView(histogram: statistics) }
            if let samples = statistics.scopes {
                if settings.waveform, let counts = samples.waveform {
                    ScopeDensityView(counts: counts, kind: .waveform)
                }
                if settings.rgbParade, let counts = samples.parade {
                    ScopeDensityView(counts: counts, kind: .parade)
                }
                if settings.vectorscope, let counts = samples.vectorscope {
                    ScopeDensityView(counts: counts, kind: .vectorscope)
                }
            }
        }.allowsHitTesting(false).accessibilityIdentifier("camera.monitor.readouts")
    }
}

private struct ScopeDensityView: View {
    enum Kind { case waveform, parade, vectorscope }
    let counts: [UInt32]
    let kind: Kind
    private var title: String {
        switch kind {
        case .waveform: return "SDR 프리뷰 분석 · 휘도 파형 0–100%"
        case .parade: return "SDR 프리뷰 분석 · R / G / B"
        case .vectorscope: return "SDR 프리뷰 분석 · Cb→ / Cr↑"
        }
    }
    var body: some View {
        VStack(spacing: 2) {
            Canvas { context, size in
                let channels = kind == .parade ? 3 : 1
                guard counts.count == channels * 4096 else { return }
                var grid = Path()
                for i in 0...4 {
                    let y = size.height * Double(i) / 4
                    grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(grid, with: .color(.white.opacity(0.2)), lineWidth: 0.5)
                if kind == .vectorscope {
                    context.stroke(Path(ellipseIn: CGRect(x: size.width * 0.05, y: size.height * 0.05, width: size.width * 0.9, height: size.height * 0.9)), with: .color(.white.opacity(0.3)), lineWidth: 0.5)
                }
                let peak = Double(counts.max() ?? 0)
                guard peak > 0 else { return }
                let colors: [Color] = kind == .parade ? [.red, .green, .blue] : kind == .waveform ? [.green] : [.white]
                for channel in 0..<channels { for x in 0..<64 { for y in 0..<64 {
                    let index = channel * 4096 + (kind == .vectorscope ? y * 64 + x : x * 64 + y)
                    let value = counts[index]; guard value > 0 else { continue }
                    let rect = CGRect(x: Double(channel * 64 + x) / Double(channels * 64) * size.width,
                                      y: Double(63 - y) / 64 * size.height,
                                      width: size.width / Double(channels * 64), height: size.height / 64)
                    context.fill(Path(rect), with: .color(colors[channel].opacity(max(0.15, sqrt(Double(value) / peak)))))
                } } }
            }.frame(width: kind == .vectorscope ? 96 : 160, height: kind == .vectorscope ? 96 : 64)
            Text(title).font(.system(size: 8))
        }.padding(5).background(.black.opacity(0.7)).accessibilityLabel(title)
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
