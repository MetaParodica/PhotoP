import Foundation

enum DepthLensProfile: String, Codable, CaseIterable, Identifiable, Sendable {
    case natural, portrait, classic
    case vista28, street35, standard50, studio75, velvet85, reach90
    var id: String { rawValue }
    static let legacy: [Self] = [.natural, .portrait, .classic]
    var title: String {
        switch self {
        case .natural: return "Natural"
        case .portrait: return "Portrait"
        case .classic: return "Classic"
        case .vista28: return "Vista 28"
        case .street35: return "Street 35"
        case .standard50: return "Standard 50"
        case .studio75: return "Studio 75"
        case .velvet85: return "Velvet 85"
        case .reach90: return "Reach 90"
        }
    }
    var explanation: String {
        switch self {
        case .natural: return "중립 원형·균일 광량"
        case .portrait: return "부드러운 중심 가중·완만한 전이"
        case .classic: return "가상 6날 조리개·주변부 캣아이"
        default: return "독자 보케 스타일 · 가상 \(Int(focalLengthMM))mm 특성, 실제 광학 줌 아님"
        }
    }
    var focalLengthMM: Double {
        switch self {
        case .vista28: return 28
        case .street35: return 35
        case .studio75: return 75
        case .velvet85: return 85
        case .reach90: return 90
        default: return 50
        }
    }
    var blades: Int {
        switch self {
        case .classic, .vista28: return 6
        case .street35, .standard50, .studio75: return 8
        case .velvet85, .reach90: return 10
        default: return 0
        }
    }
    var catEye: Double {
        switch self {
        case .classic: return 1.2
        case .vista28: return 0.3
        case .street35: return 0.5
        case .standard50: return 0.65
        case .studio75: return 0.85
        case .velvet85: return 1.05
        case .reach90: return 1.4
        default: return 0
        }
    }
    var centerWeight: Double { self == .portrait ? 1.5 : self == .velvet85 ? 0.6 : 0 }

}

struct DepthBokehTap: Sendable {
    let x: Double
    let y: Double
    let weight: Double
}

enum DepthLensKernel {
    // One center + symmetric pairs. CPU reference and GPU shader generation use
    // the very same normalized PSF, not unrelated test-only approximations.
    static func taps(profile: DepthLensProfile, aperture: Double, pairs: Int = 16) -> [DepthBokehTap] {
        let n = min(24, max(4, pairs))
        let f = aperture.isFinite ? min(16, max(1.4, aperture)) : 2.8
        var values = [DepthBokehTap(x: 0, y: 0, weight: 1)]
        for i in 0..<n {
            let r = sqrt((Double(i) + 0.5) / Double(n)), angle = Double(i) * 2.399963229728653
            var shape = 1.0
            if profile.blades > 0 {
                let sector = 2 * Double.pi / Double(profile.blades)
                let local = (angle + sector / 2).truncatingRemainder(dividingBy: sector) - sector / 2
                let polygon = cos(sector / 2) / cos(local)
                shape = 1 + (polygon - 1) * min(1, (f - 1.4) / 6.6)
            }
            let weight = pow(max(0.02, 1 - r * r), profile.centerWeight)
            let x = cos(angle) * r * shape, y = sin(angle) * r * shape
            values.append(.init(x: x, y: y, weight: weight)); values.append(.init(x: -x, y: -y, weight: weight))
        }
        let total = values.reduce(0) { $0 + $1.weight }
        return values.map { .init(x: $0.x, y: $0.y, weight: $0.weight / total) }
    }
    // Coordinates are pixel centers in the full image, including when CI tiles.
    // This is the same radial transform used by the Metal compute kernel.
    static func offset(_ tap: DepthBokehTap, x: Double, y: Double, width: Int, height: Int, profile: DepthLensProfile) -> SIMD2<Double> {
        let edge = Double(max(width, height))
        let radial = SIMD2((x + 0.5 - Double(width) / 2) / edge, (y + 0.5 - Double(height) / 2) / edge)
        let rr = radial.x * radial.x + radial.y * radial.y
        guard rr > 0.00000001 else { return SIMD2(tap.x, tap.y) }
        let axis = radial / sqrt(rr), value = SIMD2(tap.x, tap.y)
        return value - axis * (value.x * axis.x + value.y * axis.y) * min(0.4, rr * profile.catEye)
    }
    static func reference(_ image: [SIMD3<Float>], width: Int, height: Int, radius: Double,
                          profile: DepthLensProfile, aperture: Double = 2.8) -> [SIMD3<Float>]? {
        guard width > 0, height > 0, width <= 1024, height <= 1024, width * height == image.count,
              radius.isFinite, (0...128).contains(radius), image.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) else { return nil }
        let taps = taps(profile: profile, aperture: aperture)
        return (0..<image.count).map { index in
            let x = index % width, y = index / width
            var result = SIMD3<Float>.zero
            for t in taps {
                result += DepthGrid.sample(image, width: width, height: height,
                    x: Double(x) + offset(t, x: Double(x), y: Double(y), width: width, height: height, profile: profile).x * radius,
                    y: Double(y) + offset(t, x: Double(x), y: Double(y), width: width, height: height, profile: profile).y * radius) * Float(t.weight)
            }
            return result
        }
    }
}

enum DepthGrid {
    static func sample(_ values: [Float], width: Int, height: Int, x: Double, y: Double) -> Float {
        let px = min(Double(width - 1), max(0, x)), py = min(Double(height - 1), max(0, y))
        let ix = Int(px), iy = Int(py), jx = min(width - 1, ix + 1), jy = min(height - 1, iy + 1)
        let dx = Float(px - Double(ix)), dy = Float(py - Double(iy))
        return (values[iy * width + ix] * (1 - dx) + values[iy * width + jx] * dx) * (1 - dy)
             + (values[jy * width + ix] * (1 - dx) + values[jy * width + jx] * dx) * dy
    }
    static func sample(_ values: [SIMD3<Float>], width: Int, height: Int, x: Double, y: Double) -> SIMD3<Float> {
        let px = min(Double(width - 1), max(0, x)), py = min(Double(height - 1), max(0, y))
        let ix = Int(px), iy = Int(py), jx = min(width - 1, ix + 1), jy = min(height - 1, iy + 1)
        let dx = Float(px - Double(ix)), dy = Float(py - Double(iy))
        let a = values[iy * width + ix] * (1 - dx) + values[iy * width + jx] * dx
        let b = values[jy * width + ix] * (1 - dx) + values[jy * width + jx] * dx
        return a * (1 - dy) + b * dy
    }
    static func resized(_ field: SoftwareDepthField, width: Int, height: Int) -> SoftwareDepthField? {
        guard width >= 3, height >= 3, width <= 1024, height <= 1024 else { return nil }
        if field.width == width && field.height == height { return field }
        let data = (0..<(width * height)).map { index -> Float in
            let x = (Double(index % width) + 0.5) * Double(field.width) / Double(width) - 0.5
            let y = (Double(index / width) + 0.5) * Double(field.height) / Double(height) - 0.5
            // Do not interpolate invalid depth as a real distance.
            let px = min(field.width - 1, max(0, Int(x.rounded()))), py = min(field.height - 1, max(0, Int(y.rounded())))
            return field.inverseDepth[py * field.width + px]
        }
        return field.resampled(width: width,height: height,inverseDepth: data)
    }
}

struct DepthAffineCalibration: Sendable {
    let scale: Double
    let offset: Double
    let normalizedError: Double
    let support: Int
}

enum DepthFusionCore {
    static func calibrate(predicted: [Float], measured: [Float]) -> DepthAffineCalibration? {
        guard predicted.count == measured.count, predicted.count >= 32 else { return nil }
        let stride = max(1, predicted.count / 2048)
        var pairs: [(Double, Double)] = []
        for i in Swift.stride(from: 0, to: predicted.count, by: stride) {
            let p = predicted[i], m = measured[i]
            if p.isFinite, m.isFinite, p > 0, m > 0 { pairs.append((Double(p), Double(m))) }
        }
        guard pairs.count >= 32 else { return nil }
        func fit(_ points: [(Double, Double)]) -> (Double, Double)? {
            let n = Double(points.count)
            let x = points.reduce(0) { $0 + $1.0 } / n, y = points.reduce(0) { $0 + $1.1 } / n
            let variance = points.reduce(0) { $0 + pow($1.0 - x, 2) }
            let covariance = points.reduce(0) { $0 + ($1.0 - x) * ($1.1 - y) }
            guard variance > 0.00000001 else { return nil }
            let a = covariance / variance, b = y - a * x
            return a.isFinite && b.isFinite && a > 0 ? (a, b) : nil
        }
        guard let initial = fit(pairs) else { return nil }
        let residuals = pairs.map { abs($0.1 - (initial.0 * $0.0 + initial.1)) }.sorted()
        let cutoff = max(0.00001, residuals[Int(Double(residuals.count - 1) * 0.8)])
        pairs = pairs.filter { abs($0.1 - (initial.0 * $0.0 + initial.1)) <= cutoff }
        guard pairs.count >= 32, let result = fit(pairs) else { return nil }
        let targets = pairs.map(\.1).sorted(), span = targets.last! - targets.first!
        guard span > 0.00001 else { return nil }
        let error = pairs.reduce(0) { $0 + abs($1.1 - (result.0 * $1.0 + result.1)) } / Double(pairs.count) / span
        guard error <= 0.08 else { return nil }
        return .init(scale: result.0, offset: result.1, normalizedError: error, support: pairs.count)
    }
    static func fuse(measured: SoftwareDepthField, predicted: SoftwareDepthField) -> (field: SoftwareDepthField, calibration: DepthAffineCalibration?, filled: Int) {
        guard let prediction = DepthGrid.resized(predicted, width: measured.width, height: measured.height),
              let calibration = calibrate(predicted: prediction.inverseDepth, measured: measured.inverseDepth) else { return (measured, nil, 0) }
        let valid = measured.inverseDepth.filter { $0 > 0 }, ceiling = Double(valid.max() ?? 1) * 3
        var data = measured.inverseDepth, filled = 0
        for i in data.indices where data[i] == 0 && prediction.inverseDepth[i] > 0 {
            let value = calibration.scale * Double(prediction.inverseDepth[i]) + calibration.offset
            if value.isFinite, value > 0, value <= ceiling { data[i] = Float(value); filled += 1 }
        }
        guard let field = SoftwareDepthField(width: measured.width, height: measured.height, inverseDepth: data, units: measured.units, nativeMetadata: measured.nativeMetadata) else { return (measured, nil, 0) }
        return (field, calibration, filled)
    }
}

struct DepthMatteSurface: Sendable {
    let id = UUID()
    let width: Int
    let height: Int
    let alpha: [Float]
    let foreground: [SIMD3<Float>]
    let background: [SIMD3<Float>]

    func encoded() -> Data {
        var words: [UInt32] = []; words.reserveCapacity(width * height * 7)
        for i in alpha.indices {
            for v in [alpha[i], foreground[i].x, foreground[i].y, foreground[i].z,
                      background[i].x, background[i].y, background[i].z] { words.append(v.bitPattern.littleEndian) }
        }
        return words.withUnsafeBytes { Data($0) }
    }
    static func decode(_ data: Data, width: Int, height: Int) -> Self? {
        guard width >= 3, height >= 3, width <= 512, height <= 512, data.count == width * height * 28 else { return nil }
        let values: [Float] = data.withUnsafeBytes { raw in
            (0..<(width * height * 7)).map { Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self))) }
        }
        guard values.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return nil }
        var alpha: [Float] = [], f: [SIMD3<Float>] = [], b: [SIMD3<Float>] = []
        for i in 0..<(width * height) {
            let o = i * 7; alpha.append(values[o]); f.append(SIMD3(values[o + 1], values[o + 2], values[o + 3])); b.append(SIMD3(values[o + 4], values[o + 5], values[o + 6]))
        }
        return .init(width: width, height: height, alpha: alpha, foreground: f, background: b)
    }
}

enum DepthMatteCore {
    static func clamp(_ c: SIMD3<Float>) -> SIMD3<Float> { SIMD3(min(1, max(0, c.x)), min(1, max(0, c.y)), min(1, max(0, c.z))) }
    static func unmix(image: SIMD3<Float>, background: SIMD3<Float>, alpha: Float) -> SIMD3<Float> {
        guard alpha.isFinite, alpha > 0.05, alpha < 0.98 else { return clamp(image) }
        return clamp((image - background * (1 - alpha)) / alpha)
    }
    static func refine(alpha: [Float], color: [SIMD3<Float>], width: Int, height: Int, preserveAlpha: Bool = false) -> DepthMatteSurface? {
        guard width >= 3, height >= 3, width <= 1024, height <= 1024, width * height == alpha.count,
              alpha.count == color.count, alpha.allSatisfy(\.isFinite),
              color.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) else { return nil }
        let a = alpha.map { min(1, max(0, $0)) }
        var refined = a, foreground = color, background = color
        for y in 0..<height { for x in 0..<width {
            let i = y * width + x
            // Reliable seeds are constraints, not samples to blur across an edge.
            guard a[i] > 0.02, a[i] < 0.98 else { continue }
            var sum: Float = 0, weight: Float = 0
            for dy in -1...1 { for dx in -1...1 {
                let px = min(width - 1, max(0, x + dx)), py = min(height - 1, max(0, y + dy)), j = py * width + px
                let d = color[j] - color[i], distance = d.x * d.x + d.y * d.y + d.z * d.z
                let w = exp(-distance / 0.025 - Float(dx * dx + dy * dy) / 3)
                sum += a[j] * w; weight += w
            } }
            if !preserveAlpha { refined[i] = min(1, max(0, a[i] * 0.5 + sum / max(0.0001, weight) * 0.5)) }
            guard refined[i] > 0.03, refined[i] < 0.97 else { continue }
            var bg = SIMD3<Float>.zero, bgWeight: Float = 0
            var fg = SIMD3<Float>.zero, fgWeight: Float = 0
            for dy in -4...4 { for dx in -4...4 {
                let px = min(width - 1, max(0, x + dx)), py = min(height - 1, max(0, y + dy)), j = py * width + px
                if a[j] < 0.08 {
                    let w = 1 / Float(1 + dx * dx + dy * dy)
                    bg += color[j] * w; bgWeight += w
                } else if a[j] > 0.98 {
                    let w = 1 / Float(1 + dx * dx + dy * dy)
                    fg += color[j] * w; fgWeight += w
                }
            } }
            if bgWeight > 0 {
                bg /= bgWeight; background[i] = bg
                if fgWeight > 0, !preserveAlpha {
                    fg /= fgWeight
                    let line = fg - bg, observed = color[i] - bg
                    let contrast = line.x * line.x + line.y * line.y + line.z * line.z
                    if contrast > 0.04 {
                        let candidate = min(1, max(0, (observed.x * line.x + observed.y * line.y + observed.z * line.z) / contrast))
                        let residual = observed - line * candidate
                        let error = residual.x * residual.x + residual.y * residual.y + residual.z * residual.z
                        // Only an observed foreground/background color line supplies
                        // evidence. Ambiguous glass/reflections keep the input mask.
                        let confidence = max(0, 1 - error / 0.015) * min(1, contrast / 0.2)
                        let correction = min(0.35, max(-0.35, candidate - refined[i]))
                        refined[i] = min(1, max(0, refined[i] + correction * confidence * 0.85))
                    }
                }
                foreground[i] = color[i] * 0.25 + unmix(image: color[i], background: bg, alpha: refined[i]) * 0.75
            }
        } }
        return .init(width: width, height: height, alpha: refined, foreground: foreground, background: background)
    }
}

struct DepthTemporalState: Sendable {
    private var field: SoftwareDepthField?
    private var luma: [Float] = []
    private var time = -Double.infinity
    private var generation: UInt64 = 0
    private var historyRegistered = false
    mutating func reset() { field = nil; luma = []; time = -Double.infinity; historyRegistered = false }
    // Backward pixel flow: each CURRENT pixel points into the PREVIOUS image.
    // Out-of-view/newly occluded or photometrically inconsistent pixels get no
    // history. Warping never creates metric information or extends its age.
    mutating func alignHistory(backwardFlow: [SIMD2<Float>], currentLuma: [Float]) -> Bool {
        historyRegistered = false
        guard let previous = field, backwardFlow.count == previous.inverseDepth.count,
              luma.count == backwardFlow.count, currentLuma.count == luma.count,
              currentLuma.allSatisfy(\.isFinite) else { return false }
        let w = previous.width, h = previous.height
        var data = [Float](repeating: 0, count: luma.count), alignedLuma = currentLuma
        var accepted = 0
        for i in data.indices {
            let flow = backwardFlow[i]
            guard flow.x.isFinite, flow.y.isFinite else { continue }
            let x = Double(i % w) + Double(flow.x), y = Double(i / w) + Double(flow.y)
            guard x >= 0, y >= 0, x <= Double(w - 1), y <= Double(h - 1),
                  abs(DepthGrid.sample(luma, width: w, height: h, x: x, y: y) - currentLuma[i]) <= 0.06 else { continue }
            let j = min(h - 1, Int(y.rounded())) * w + min(w - 1, Int(x.rounded()))
            guard previous.inverseDepth[j] > 0 else { continue }
            data[i] = previous.inverseDepth[j]
            alignedLuma[i] = DepthGrid.sample(luma, width: w, height: h, x: x, y: y)
            accepted += 1
        }
        guard accepted * 3 >= data.count * 2,
              let aligned = SoftwareDepthField(width: w, height: h, inverseDepth: data, units: previous.units, nativeMetadata: previous.nativeMetadata) else { return false }
        field = aligned; luma = alignedLuma; historyRegistered = true
        return true
    }
    mutating func update(_ next: SoftwareDepthField, luma nextLuma: [Float], time nextTime: Double, generation: UInt64, requireRegistration: Bool = false) -> SoftwareDepthField? {
        guard nextTime.isFinite, nextLuma.count == next.inverseDepth.count, nextLuma.allSatisfy(\.isFinite) else { return nil }
        defer { historyRegistered = false }
        if (!requireRegistration || historyRegistered), generation == self.generation, let previous = field, previous.width == next.width, previous.height == next.height,
           previous.units == next.units, nextTime >= time, nextTime - time <= 1, luma.count == nextLuma.count {
            var old = previous.inverseDepth
            if next.units == .relativeInverse {
                if let fit = DepthFusionCore.calibrate(predicted: old, measured: next.inverseDepth) {
                    old = old.map { $0 > 0 ? Float(fit.scale * Double($0) + fit.offset) : 0 }
                } else {
                    // Relative predictions have no stable scale. A failed fit
                    // must discard history instead of mixing unrelated planes.
                    old = Array(repeating: 0, count: old.count)
                }
            }
            var data = next.inverseDepth
            let span = next.bounds.map { $0.upper - $0.lower } ?? 0
            let tolerance = max(0.001, span * 0.1)
            for i in data.indices where abs(nextLuma[i] - luma[i]) < 0.035 && data[i] > 0 && old[i] > 0 && abs(data[i] - old[i]) <= tolerance {
                data[i] = data[i] * 0.7 + old[i] * 0.3
            }
            field = SoftwareDepthField(width: next.width, height: next.height, inverseDepth: data, units: next.units, nativeMetadata: next.nativeMetadata)
        } else { field = next }
        luma = nextLuma; time = nextTime; self.generation = generation
        return field
    }
    func current(luma current: [Float], time now: Double, generation: UInt64, maximumAge: Double = 0.75) -> SoftwareDepthField? {
        guard let field, now.isFinite, now >= time, now - time <= maximumAge, generation == self.generation,
              current.count == luma.count, current.allSatisfy(\.isFinite) else { return nil }
        var changed = 0
        let masked = field.invalidating { i in
            if abs(current[i] - luma[i]) > 0.06 { changed += 1; return true }
            return false
        }
        guard changed * 3 < current.count else { return nil }
        return masked
    }
}
