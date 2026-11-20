import SwiftUI

@MainActor
final class ExperimentalDepthSettings: ObservableObject {
    static let shared = ExperimentalDepthSettings()
    @Published private(set) var preferences = ExperimentalDepthRuntime.shared.current
    func setPhotoSelection(_ enabled: Bool) {
        ExperimentalDepthRuntime.shared.setPhotoSelection(enabled)
        preferences = ExperimentalDepthRuntime.shared.current
    }
    func setPortraitMatte(_ enabled: Bool) {
        ExperimentalDepthRuntime.shared.setPortraitMatte(enabled)
        preferences = ExperimentalDepthRuntime.shared.current
    }
}

@MainActor
struct ExperimentalDepthSettingsView: View {
    @ObservedObject private var settings = ExperimentalDepthSettings.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("정밀 피사체 선택 · 사진 전용", isOn: Binding(
                get: { settings.preferences.photoSubjectSelection },
                set: { settings.setPhotoSelection($0) }))
                .accessibilityIdentifier("experiments.depth.photoSelection")
                .disabled(!ExperimentalPhotoSubjectSelector.isBundled && !settings.preferences.photoSubjectSelection)
            Text("촬영 후 사진과 명시적 재분석에 적용합니다. 처리 시간이 늘거나 경계가 부정확할 수 있습니다. 기존 사진·영상·라이브 심도는 그대로 사용할 수 있습니다.")
                .font(.caption).foregroundStyle(.secondary)
            Text(ExperimentalPhotoSubjectSelector.isBundled ? "사진 심도를 켜고 피사체를 터치하세요. 다음 사진에서 모델을 준비해 분석합니다." : "정밀 선택 모델이 포함되지 않은 빌드입니다. 기존 심도 기능을 사용합니다.")
                .font(.caption2).foregroundStyle(.secondary)
                .accessibilityIdentifier("experiments.depth.availability")
            Toggle("인물 경계 개선 · 사진 전용", isOn: Binding(
                get: { settings.preferences.photoPortraitMatte }, set: { settings.setPortraitMatte($0) }))
                .accessibilityIdentifier("experiments.depth.portraitMatte")
                .disabled((!ExperimentalPortraitMatte.isBundled || !ExperimentalPhotoSubjectSelector.isBundled) && !settings.preferences.photoPortraitMatte)
            Text("선택한 인물의 경계를 추가 분석합니다. 인물을 확인하지 못하면 기존 방식으로 처리하며, 준비와 처리에 시간이 걸릴 수 있습니다.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
