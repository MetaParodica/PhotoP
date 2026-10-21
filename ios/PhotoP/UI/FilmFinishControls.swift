import SwiftUI

struct FilmFinishControls: View {
    @Binding var settings: FilmFinishSettings
    var body: some View {
        VStack {
            Slider(value: $settings.fade, in: 0...1) { Text("페이드") }; Text("페이드 \(Int(settings.fade * 100))%")
            Slider(value: $settings.vignette, in: 0...1) { Text("비네팅") }; Text("비네팅 \(Int(settings.vignette * 100))%")
            Slider(value: $settings.bloom, in: 0...1) { Text("블룸") }; Text("블룸 \(Int(settings.bloom * 100))%")
            Slider(value: $settings.halation, in: 0...1) { Text("레드 할레이션") }; Text("할레이션 \(Int(settings.halation * 100))%")
            Text("독립적인 창작 효과입니다. 실제 필름 유제의 측정 모델은 아닙니다.").font(.caption)
        }
    }
}
