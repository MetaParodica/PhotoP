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
                    Section("사진 해상도 상한") {
                        Picker("요청 크기", selection: $model.photoResolution) {
                            Text("현재 포맷 최대").tag(Optional<PhotoResolution>.none)
                            ForEach(caps.photoResolutions) { item in Text(item.title).tag(Optional(item)) }
                        }.disabled(model.busy || model.rawMode != .processed || model.bracketEnabled)
                        Text("현재 활성 포맷이 제공하는 값만 표시합니다. 요청 상한이며 실제 파일은 더 작을 수 있습니다. RAW·브래킷은 기존 최대 상한 정책을 유지합니다.").font(.caption)
                        if let actual = model.latestPhotoResolution { Text("최근 저장 파일: \(actual.title)").font(.caption) }
                        Text("편집본은 12.6MP 이하입니다. 고해상도 촬영 원본은 보존됩니다.").font(.caption)
                    }
                    Section("노출 · 요청값") {
                        Toggle("수동 ISO · 셔터", isOn: $model.settings.exposure.manual)
                            .disabled(!caps.manualExposure)
                            .onChange(of: model.settings.exposure.manual) { _, value in if value { model.settings.exposure.locked = false } }
                        Toggle("AE Lock", isOn: $model.settings.exposure.locked)
                            .disabled(!caps.exposureLock)
                            .onChange(of: model.settings.exposure.locked) { _, value in if value { model.settings.exposure.manual = false } }
                        if model.settings.exposure.manual {
                            valueSlider("ISO", value: $model.settings.exposure.iso, range: caps.iso, logarithmic: true)
                            valueSlider("셔터 (초)", value: $model.settings.exposure.shutterSeconds,
                                        range: caps.shutterSeconds, logarithmic: true)
                        } else if !model.settings.exposure.locked {
                            valueSlider("EV", value: $model.settings.exposure.ev, range: caps.exposureBias)
                        }
                        Text("수동 노출에서는 ISO와 셔터를 함께 고정합니다. EV는 자동 노출에서 적용합니다.")
                            .font(.caption)
                    }
                    Section("노출 브라케팅") {
                        Toggle("3장 노출 브래킷", isOn: $model.bracketEnabled)
                            .disabled(caps.maximumBracketCount < 3 || model.busy)
                        Picker("EV 간격", selection: $model.bracketStep) {
                            Text("±0.5 EV").tag(0.5)
                            Text("±1 EV").tag(1.0)
                            Text("±2 EV").tag(2.0)
                        }.disabled(model.busy)
                        Text("현재 EV를 중심으로 3장 원본을 별도 저장합니다. HDR 합성은 후속 단계입니다.").font(.caption)
                        if let reason = model.bracketUnavailableReason { Text(reason).font(.caption) }
                    }
                    Section("초점") {
                        Toggle("수동 초점", isOn: $model.settings.focus.manual)
                            .disabled(!caps.manualFocus)
                            .onChange(of: model.settings.focus.manual) { _, value in if value { model.settings.focus.locked = false } }
                        Toggle("AF Lock", isOn: $model.settings.focus.locked)
                            .disabled(!caps.focusLock)
                            .onChange(of: model.settings.focus.locked) { _, value in if value { model.settings.focus.manual = false } }
                        if model.settings.focus.manual {
                            valueSlider("렌즈 위치", value: $model.settings.focus.lensPosition, range: 0...1)
                            Text("0~1은 정규화된 렌즈 위치이며 실제 거리(m)가 아닙니다.").font(.caption)
                        }
                    }
                    Section("화이트밸런스") {
                        Toggle("수동 WB", isOn: $model.settings.whiteBalance.manual)
                            .disabled(!caps.manualWhiteBalance)
                            .onChange(of: model.settings.whiteBalance.manual) { _, value in if value { model.settings.whiteBalance.locked = false } }
                        Toggle("WB Lock", isOn: $model.settings.whiteBalance.locked)
                            .disabled(!caps.whiteBalanceLock)
                            .onChange(of: model.settings.whiteBalance.locked) { _, value in if value { model.settings.whiteBalance.manual = false } }
                        if model.settings.whiteBalance.manual {
                            valueSlider("Kelvin", value: $model.settings.whiteBalance.kelvin, range: 2000...10000)
                            valueSlider("Tint", value: $model.settings.whiteBalance.tint, range: -150...150)
                            Text("변환된 RGB 게인은 기기의 허용 범위로 제한됩니다.").font(.caption)
                        }
                    }
                    Text("Lock은 설정 적용 시점의 현재값을 유지합니다. 잠금 해제 후 다시 적용하면 자동 제어로 돌아갑니다.").font(.caption)
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
