import Foundation
import CryptoKit

struct LUTProvenance: Codable, Equatable, Sendable {
    let identifier: String
    let name: String
    let creator: String
    let source: String
    let kind: String
    let license: String
    let commercialUseAllowed: Bool
    let redistributionAllowed: Bool
    let inputColorSpace: String
    let outputColorSpace: String
    let requiredCredit: String
    let sourceSHA256: String
    let renderLUTSHA256: String
    let minimumIntensity: Double
    let maximumIntensity: Double
    let previewDescription: String
}

struct FilmStyle: Identifiable, Sendable {
    let id: String
    let name: String
    let category: String
    let detail: String
    let saturation: Double
    let contrast: Double
    let gamma: Double
    let lift: Double
    let tint: SIMD3<Double>
    var monochrome = false
    var recommended = ProcessingLookSettings()
    func color(_ input: SIMD3<Double>) -> SIMD3<Double> {
        let luminance = input.x * 0.2126 + input.y * 0.7152 + input.z * 0.0722
        let base = monochrome ? SIMD3<Double>(repeating: luminance) : SIMD3<Double>(repeating: luminance) + (input - SIMD3<Double>(repeating: luminance)) * saturation
        var output = SIMD3<Double>()
        for c in 0..<3 {
            let value = min(max(base[c], 0), 1)
            let curved = (pow(value, gamma) - 0.5) * contrast + 0.5
            let tinted = lift + (1 - lift) * curved + (monochrome ? 0 : tint[c] * (0.25 + luminance * (1 - luminance)))
            output[c] = min(max(tinted, 0), 1)
        }
        return output
    }
    func imported() throws -> ImportedLUT {
        let n = 17
        var lines = ["TITLE \"PhotoP \(name) v1\"", "LUT_3D_SIZE \(n)"]
        for b in 0..<n { for g in 0..<n { for r in 0..<n {
            let v = color(SIMD3(Double(r), Double(g), Double(b)) / Double(n - 1))
            lines.append(String(format: "%.7f %.7f %.7f", locale: Locale(identifier: "en_US_POSIX"), v.x, v.y, v.z))
        } } }
        let text = lines.joined(separator: "\n"), data = Data(text.utf8)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let provenance = LUTProvenance(identifier: "photop.\(id).v1", name: name, creator: "PhotoP Project", source: "photop-style://\(id)/v1",
            kind: "original-procedural", license: "PhotoP-Style-Permission-1", commercialUseAllowed: true, redistributionAllowed: true,
            inputColorSpace: "sRGB", outputColorSpace: "sRGB", requiredCredit: "PhotoP Project", sourceSHA256: hash, renderLUTSHA256: hash,
            minimumIntensity: 0, maximumIntensity: 1, previewDescription: "Generated sRGB color patches; not a photographed film chart")
        return ImportedLUT(data: data, lut: try CubeLUT.parse(text), displayName: name, preset: recommended, provenance: provenance)
    }
    static let all: [FilmStyle] = [
        .init(id: "amber-portrait", name: "Amber Portrait", category: "인물", detail: "따뜻한 피부·부드러운 대비", saturation: 0.94, contrast: 0.95, gamma: 0.98, lift: 0.015, tint: .init(0.025, 0.006, -0.018)),
        .init(id: "quiet-documentary", name: "Quiet Documentary", category: "스트리트", detail: "절제된 채도·담백한 톤", saturation: 0.76, contrast: 1.04, gamma: 1.02, lift: 0.018, tint: .init(0.008, -0.004, -0.008)),
        .init(id: "copper-night", name: "Copper Night", category: "야경", detail: "구릿빛·낮춘 검정", saturation: 0.88, contrast: 1.1, gamma: 1.05, lift: 0.008, tint: .init(0.04, -0.015, -0.025)),
        .init(id: "pastel-day", name: "Pastel Day", category: "파스텔", detail: "밝은 중간톤·부드러운 색", saturation: 0.72, contrast: 0.9, gamma: 0.93, lift: 0.025, tint: .init(0.012, 0.006, 0.016)),
        .init(id: "forest-slide", name: "Forest Slide", category: "풍경", detail: "선명한 녹색·깊은 대비", saturation: 1.13, contrast: 1.08, gamma: 1.03, lift: 0, tint: .init(-0.01, 0.024, -0.012)),
        .init(id: "silver-mono", name: "Silver Mono", category: "흑백", detail: "부드러운 단색 계조", saturation: 0, contrast: 1.02, gamma: 0.96, lift: 0.012, tint: .zero, monochrome: true),
        .init(id: "graphite", name: "Graphite", category: "흑백", detail: "강한 단색 대비", saturation: 0, contrast: 1.2, gamma: 1.08, lift: 0, tint: .zero, monochrome: true),
        .init(id: "soft-neutral", name: "Soft Neutral", category: "미니멀", detail: "중립색·낮은 대비", saturation: 0.98, contrast: 0.94, gamma: 1, lift: 0.005, tint: .zero),
        .init(id: "golden-travel", name: "Golden Travel", category: "여행", detail: "황금빛·생생한 중간톤", saturation: 1.04, contrast: 1.02, gamma: 0.97, lift: 0.006, tint: .init(0.035, 0.018, -0.028)),
        .init(id: "cool-architecture", name: "Cool Architecture", category: "건축", detail: "차가운 중립·선명한 구조", saturation: 0.87, contrast: 1.06, gamma: 1, lift: 0.004, tint: .init(-0.014, 0.002, 0.027)),
        .init(id: "dream-warm", name: "Dream Warm", category: "빈티지", detail: "따뜻한 페일 톤", saturation: 0.81, contrast: 0.91, gamma: 0.95, lift: 0.04, tint: .init(0.032, 0.004, -0.016)),
        .init(id: "deep-cinema", name: "Deep Cinema", category: "시네마", detail: "깊은 대비·절제된 색", saturation: 0.82, contrast: 1.12, gamma: 1.06, lift: 0.009, tint: .init(-0.006, 0.009, 0.019))
    ]
    static func search(_ query: String, category: String) -> [FilmStyle] {
        all.filter { (category == "전체" || $0.category == category) && (query.isEmpty || "\($0.name) \($0.category) \($0.detail)".localizedCaseInsensitiveContains(query)) }
    }
    static let chart: [SIMD3<Double>] = [.init(0.15,0.15,0.15), .init(0.4,0.4,0.4), .init(0.8,0.8,0.8),
        .init(0.76,0.52,0.39), .init(0.48,0.29,0.2), .init(0.9,0.1,0.1), .init(0.1,0.8,0.2), .init(0.1,0.2,0.9),
        .init(0.9,0.8,0.1), .init(0.1,0.7,0.8), .init(0.7,0.1,0.8), .init(0.95,0.95,0.95)]
}
