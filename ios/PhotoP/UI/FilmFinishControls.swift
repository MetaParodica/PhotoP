import SwiftUI

struct FilmFinishControls: View {
    @Binding var settings: FilmFinishSettings
    var body: some View {
        VStack {
            Slider(value: $settings.fade, in: 0...1) { Text("페이드") }; Text("페이드 \(Int(settings.fade * 100))%")
            Slider(value: $settings.vignette, in: 0...1) { Text("비네팅") }; Text("비네팅 \(Int(settings.vignette * 100))%")
            Slider(value: $settings.bloom, in: 0...1) { Text("블룸") }; Text("블룸 \(Int(settings.bloom * 100))%")
            Slider(value: $settings.halation, in: 0...1) { Text("레드 할레이션") }; Text("할레이션 \(Int(settings.halation * 100))%")
            Slider(value: $settings.softFocus, in: 0...1) { Text("소프트 포커스") }; Text("소프트 포커스 \(Int(settings.softFocus * 100))%")
            Slider(value: $settings.chromaticAberration, in: 0...1) { Text("색수차") }; Text("색수차 \(Int(settings.chromaticAberration * 100))%")
            Slider(value: $settings.streak, in: 0...1) { Text("가로 빛 번짐") }; Text("가로 빛 번짐 \(Int(settings.streak * 100))%")
            Text("독립적인 창작 효과입니다. 실제 필름 유제의 측정 모델은 아닙니다.").font(.caption)
        }
    }
}
