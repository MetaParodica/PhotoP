import SwiftUI

// A single contextual panel keeps the viewfinder and shutter in the same place.
enum CameraTool: String, CaseIterable, Identifiable {
    case iso, shutter, ev, whiteBalance, focus, looks, guide, monitor, format, longExposure, video
    var id: String { rawValue }
    var title: String {
        switch self {
        case .iso: return "ISO"; case .shutter: return "셔터"; case .ev: return "노출 보정"
        case .whiteBalance: return "화이트밸런스"; case .focus: return "초점"; case .looks: return "룩"
        case .guide: return "구도"; case .monitor: return "노출 보조"; case .format: return "촬영 포맷"
        case .longExposure: return "장노출 합성"; case .video: return "영상 촬영"
        }
    }
    var symbol: String {
        switch self {
        case .iso: return "camera.aperture"; case .shutter: return "timer"; case .ev: return "plusminus"
        case .whiteBalance: return "thermometer.medium"; case .focus: return "viewfinder"; case .looks: return "camera.filters"
        case .guide: return "square.split.2x2"; case .monitor: return "waveform.path"; case .format: return "photo"
        case .longExposure: return "moon.stars"; case .video: return "video"
        }
    }
}

enum CameraControlScale {
    static func unit(_ value: Double, range: ClosedRange<Double>, logarithmic: Bool) -> Double {
        guard range.lowerBound < range.upperBound else { return 0 }
        let value = min(max(value, range.lowerBound), range.upperBound)
        if logarithmic && range.lowerBound > 0 {
            return log(value / range.lowerBound) / log(range.upperBound / range.lowerBound)
        }
        return (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }
    static func value(_ unit: Double, range: ClosedRange<Double>, logarithmic: Bool) -> Double {
        let t = min(max(unit, 0), 1)
        if logarithmic && range.lowerBound > 0 { return range.lowerBound * pow(range.upperBound / range.lowerBound, t) }
        return range.lowerBound + (range.upperBound - range.lowerBound) * t
    }
    static func shutter(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "—" }
        return seconds >= 1 ? String(format: "%.1f s", seconds) : "1/\(Int((1 / seconds).rounded()))"
    }
}

struct CameraGlass: ViewModifier {
    var radius: CGFloat = 24
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: radius))
        } else {
            glass(content)
        }
    }
    @ViewBuilder private func glass(_ content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius))
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }
    private func fallback(_ content: Content) -> some View {
        content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(.white.opacity(0.16), lineWidth: 0.5))
    }
}
extension View {
    func cameraGlass(radius: CGFloat = 24) -> some View { modifier(CameraGlass(radius: radius)) }
}

struct CameraIconButton: View {
    let symbol: String
    let label: String
    var selected = false
    var size: CGFloat = 46
    var badge: String? = nil
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size * 0.4, weight: .medium))
                .foregroundStyle(selected ? Color(red: 0.78, green: 0.69, blue: 1) : .white)
                .frame(width: size, height: size).contentShape(Circle())
                .overlay(alignment: .bottomTrailing) {
                    if let badge {
                        Text(badge).font(.system(size: 8, weight: .heavy, design: .rounded)).foregroundStyle(.black)
                            .padding(.horizontal, 3).background(Color(red: 0.78, green: 0.69, blue: 1), in: Capsule())
                    }
                }
        }.buttonStyle(.plain).cameraGlass(radius: size / 2)
            .accessibilityLabel(label).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct CameraValueSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var logarithmic = false
    var display: (Double) -> String = { $0.formatted(.number.precision(.fractionLength(0))) }
    let onCommit: () -> Void
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(title).foregroundStyle(.secondary)
                Spacer()
                Text(display(value)).font(.system(.title3, design: .rounded, weight: .semibold)).monospacedDigit()
            }
            Slider(value: Binding(get: { CameraControlScale.unit(value, range: range, logarithmic: logarithmic) },
                                  set: { value = CameraControlScale.value($0, range: range, logarithmic: logarithmic); onCommit() }),
                   in: 0...1)
                .disabled(range.lowerBound == range.upperBound)
                .accessibilityLabel(title).accessibilityValue(display(value))
            HStack { Text(display(range.lowerBound)); Spacer(); Text(display(range.upperBound)) }
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}

// Discrete settings stay inside the dock rather than opening a system popup over
// the camera image. Horizontal scrolling also works inside the vertical panel.
struct CameraChoice<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let values: [Value]
    let identifier: String
    var key: (Value) -> String = { String(describing: $0) }
    let label: (Value) -> String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(values, id: \.self) { value in
                        Button { selection = value } label: {
                            Text(label(value)).font(.caption.weight(.semibold)).padding(.horizontal, 12).frame(minHeight: 36)
                                .background(selection == value ? Color.purple.opacity(0.45) : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain).accessibilityLabel(label(value))
                            .accessibilityIdentifier(identifier + "." + key(value))
                            .accessibilityAddTraits(selection == value ? .isSelected : [])
                    }
                }
            }.frame(height: 40)
        }.accessibilityElement(children: .contain).accessibilityIdentifier(identifier)
    }
}
