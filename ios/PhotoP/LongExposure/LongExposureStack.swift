import Foundation

struct LongExposureConfiguration: Codable, Equatable, Sendable {
    enum Blend: String, CaseIterable, Identifiable, Codable, Sendable {
        case average, lighten
        var id: String { rawValue }
        var title: String { self == .average ? "평균 · 물결/노이즈" : "Lighten · 빛 궤적" }
    }
    var duration: Double = 4
    var blend: Blend = .average
    var align = false
    func validate() throws {
        guard duration.isFinite, (1...300).contains(duration) else { throw ImageEditingError.invalid("합성 시간은 1~300초입니다.") }
    }
}

// Integer translation only, within ±8 source pixels. Not rotation/perspective
// registration or an assertion of handheld stabilisation quality.
enum TranslationAlignment {
    static func estimate(reference: SDRImage, frame: SDRImage, radius: Int = 8) -> (x: Int, y: Int)? {
        guard reference.width == frame.width, reference.height == frame.height,
              reference.width > radius * 2 + 2, reference.height > radius * 2 + 2,
              reference.rgba.count == reference.width * reference.height * 4,
              frame.rgba.count == reference.rgba.count, (0...8).contains(radius) else { return nil }
        let a = [UInt8](reference.rgba), b = [UInt8](frame.rgba), w = frame.width, h = frame.height
        let stride = max(1, min(w, h) / 48)
        func luma(_ p: [UInt8], _ x: Int, _ y: Int) -> Double {
            let i = (y * w + x) * 4
            return (54 * Double(p[i]) + 183 * Double(p[i + 1]) + 19 * Double(p[i + 2])) / 65280
        }
        var lo = 1.0, hi = 0.0
        for y in Swift.stride(from: radius, to: h - radius, by: stride) {
            for x in Swift.stride(from: radius, to: w - radius, by: stride) { let v = luma(a, x, y); lo = min(lo, v); hi = max(hi, v) }
        }
        guard hi - lo > 0.05 else { return nil }
        var best = Double.infinity, second = Double.infinity, shift = (x: 0, y: 0)
        for dy in -radius...radius { for dx in -radius...radius {
            var error = 0.0, count = 0
            for y in Swift.stride(from: radius, to: h - radius, by: stride) {
                for x in Swift.stride(from: radius, to: w - radius, by: stride) {
                    error += abs(luma(a, x, y) - luma(b, x + dx, y + dy)); count += 1
                }
            }
            error /= Double(max(1, count))
            if error < best { second = best; best = error; shift = (dx, dy) } else { second = min(second, error) }
        } }
        guard best < 0.10, second - best > 0.0001 else { return nil }
        return shift
    }
}

struct LongExposureStack {
    static let maximumDimension = 1280
    private static let linear: [Float] = (0...255).map {
        let v = Float($0) / 255
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }
    let reference: SDRImage
    let configuration: LongExposureConfiguration
    private var values: [SIMD3<Float>]
    private var weights: [UInt32]
    private(set) var accepted = 0
    private(set) var rejected = 0
    var allocatedPixels: Int { values.count }
    init(first: SDRImage, configuration: LongExposureConfiguration) throws {
        try configuration.validate()
        guard first.width > 0, first.height > 0, max(first.width, first.height) <= Self.maximumDimension,
              first.rgba.count == first.width * first.height * 4 else { throw ImageEditingError.invalid("합성 프레임 크기가 유효하지 않습니다.") }
        reference = first; self.configuration = configuration
        values = .init(repeating: .zero, count: first.width * first.height)
        weights = .init(repeating: 0, count: first.width * first.height)
        _ = try add(first)
    }
    @discardableResult mutating func add(_ image: SDRImage) throws -> Bool {
        guard image.width == reference.width, image.height == reference.height, image.rgba.count == reference.rgba.count,
              accepted + rejected < 1200 else { throw ImageEditingError.invalid("프레임 크기 또는 최대 합성 개수 제한을 초과했습니다.") }
        let shift: (x: Int, y: Int)
        if configuration.align && accepted > 0 {
            guard let estimated = TranslationAlignment.estimate(reference: reference, frame: image) else { rejected += 1; return false }
            shift = estimated
        } else { shift = (0, 0) }
        let bytes = [UInt8](image.rgba), w = image.width, h = image.height
        for y in 0..<h { for x in 0..<w {
            let sx = x + shift.x, sy = y + shift.y
            guard sx >= 0, sy >= 0, sx < w, sy < h else { continue }
            let src = (sy * w + sx) * 4, dst = y * w + x
            guard bytes[src + 3] == 255 else { continue }
            let sample = SIMD3(Self.linear[Int(bytes[src])], Self.linear[Int(bytes[src + 1])], Self.linear[Int(bytes[src + 2])])
            weights[dst] += 1
            if configuration.blend == .average { values[dst] += (sample - values[dst]) / Float(weights[dst]) }
            else if weights[dst] == 1 || Self.luminance(sample) > Self.luminance(values[dst]) { values[dst] = sample }
        } }
        accepted += 1
        return true
    }
    private static func luminance(_ v: SIMD3<Float>) -> Float { 0.2126 * v.x + 0.7152 * v.y + 0.0722 * v.z }
    func image() -> SDRImage {
        var data = Data(count: values.count * 4)
        data.withUnsafeMutableBytes { raw in
            let out = raw.bindMemory(to: UInt8.self)
            for i in values.indices {
                for c in 0..<3 {
                    let v = min(max(values[i][c], 0), 1)
                    let encoded = v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
                    out[i * 4 + c] = UInt8(min(max((encoded * 255).rounded(), 0), 255))
                }
                out[i * 4 + 3] = weights[i] > 0 ? 255 : 0
            }
        }
        return SDRImage(rgba: data, width: reference.width, height: reference.height)
    }
}
