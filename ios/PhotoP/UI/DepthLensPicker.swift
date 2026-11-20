import SwiftUI

// Preserve the familiar three segments and accessibility identity. Extra styles
// use a menu instead of squeezing nine labels into the camera's bottom panel.
struct DepthLensPicker: View {
    @Binding var selection: DepthLensProfile
    var identifier = "depth.lens.profile"
    private var segments: [DepthLensProfile] {
        DepthLensProfile.legacy + (DepthLensProfile.legacy.contains(selection) ? [] : [selection])
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("렌즈", selection: $selection) { ForEach(segments) { Text($0.title).tag($0) } }.pickerStyle(.segmented).accessibilityIdentifier(identifier)
            Menu("추가 렌즈 스타일 · \(selection.title)") {
                ForEach(DepthLensProfile.allCases.filter { !DepthLensProfile.legacy.contains($0) }) { value in
                    Button(value.title) { selection = value }
                }
            }.font(.caption)
            if !DepthLensProfile.legacy.contains(selection) { Text(selection.explanation).font(.caption2).foregroundStyle(.secondary) }
        }
    }
}
