import SwiftUI

@MainActor
struct ManualControls: View {
    @ObservedObject var model: CameraModel

    var body: some View {
        NavigationStack {
            Form {
                if let caps = model.snapshot.capabilities {
                    if let readout = model.snapshot.readout {
                        Section("카메라 현재값") { CameraReadoutView(readout: readout) }
                    }
                    Section("노출 · 요청값") {
                        Toggle("수동 ISO · 셔터", isOn: $model.settings.exposure.manual)
                            .disabled(!caps.manualExposure)
                        if model.settings.exposure.manual {
                            valueSlider("ISO", value: $model.settings.exposure.iso, range: caps.iso, logarithmic: true)
                            valueSlider("셔터 (초)", value: $model.settings.exposure.shutterSeconds,
                                        range: caps.shutterSeconds, logarithmic: true)
                        } else {
                            valueSlider("EV", value: $model.settings.exposure.ev, range: caps.exposureBias)
                        }
                        Text("수동 노출에서는 ISO와 셔터를 함께 고정합니다. EV는 자동 노출에서 적용합니다.")
                            .font(.caption)
                    }
                    Section("초점") {
                        Toggle("수동 초점", isOn: $model.settings.focus.manual)
                            .disabled(!caps.manualFocus)
                        if model.settings.focus.manual {
                            valueSlider("렌즈 위치", value: $model.settings.focus.lensPosition, range: 0...1)
                            Text("0~1은 정규화된 렌즈 위치이며 실제 거리(m)가 아닙니다.").font(.caption)
                        }
                    }
                    Section("화이트밸런스") {
                        Toggle("수동 WB", isOn: $model.settings.whiteBalance.manual)
                            .disabled(!caps.manualWhiteBalance)
                        if model.settings.whiteBalance.manual {
                            valueSlider("Kelvin", value: $model.settings.whiteBalance.kelvin, range: 2000...10000)
                            valueSlider("Tint", value: $model.settings.whiteBalance.tint, range: -150...150)
                            Text("변환된 RGB 게인은 기기의 허용 범위로 제한됩니다.").font(.caption)
                        }
                    }
                    Button(model.snapshot.isApplyingSettings ? "변경 확인 중…" : "설정 적용") { Task { await model.applySettings() } }
                        .disabled(model.busy || model.snapshot.isApplyingSettings || model.snapshot.state != .running)
                } else { Text("카메라를 시작하면 지원 범위가 표시됩니다.") }
            }
            .navigationTitle("PRO 설정")
            .toolbar { Button("닫기") { model.showControls = false } }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func valueSlider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>,
                             logarithmic: Bool = false) -> some View {
        VStack(alignment: .leading) {
            Text("\(label): \(value.wrappedValue.formatted(.number.precision(.significantDigits(2...5))))")
                .monospacedDigit()
            if range.lowerBound < range.upperBound {
                if logarithmic && range.lowerBound > 0 {
                    Slider(value: Binding(get: { log10(max(range.lowerBound, value.wrappedValue)) },
                                          set: { value.wrappedValue = pow(10, $0) }),
                           in: log10(range.lowerBound)...log10(range.upperBound))
                        .accessibilityLabel(label)
                } else { Slider(value: value, in: range).accessibilityLabel(label) }
            }
        }
    }
}
