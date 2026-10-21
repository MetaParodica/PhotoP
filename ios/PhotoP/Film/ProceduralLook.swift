import Foundation

// Spatial effects cannot be represented by a color LUT. An identity carrier reuses
// the existing import/recipe plumbing; intensity is zero and the finish pass does the work.
struct ProceduralLook: Identifiable, Sendable {
    let id: String
    let name: String
    let detail: String
    let settings: ProcessingLookSettings
    var category: String { "광학·공간" }
    func imported() throws -> ImportedLUT {
        var lines = ["TITLE \"PhotoP identity carrier - spatial effects\"", "LUT_3D_SIZE 2"]
        for b in 0...1 { for g in 0...1 { for r in 0...1 { lines.append("\(r) \(g) \(b)") } } }
        let data = Data(lines.joined(separator: "\n").utf8), hash = LUTPhotoEditor.hash(data)
        let provenance = LUTProvenance(identifier: "photop.spatial.\(id).v1", name: name, creator: "PhotoP Project", source: "photop-style://spatial/\(id)/v1",
            kind: "original-spatial-effects", license: "PhotoP-Style-Permission-1", commercialUseAllowed: true, redistributionAllowed: true,
            inputColorSpace: "sRGB", outputColorSpace: "sRGB", requiredCredit: "PhotoP Project", sourceSHA256: hash, renderLUTSHA256: hash,
            minimumIntensity: 0, maximumIntensity: 1, previewDescription: "Spatial preset parameters in recipe; identity color carrier; not a film or lens measurement")
        return ImportedLUT(data: data, lut: try CubeLUT.parse(String(decoding: data, as: UTF8.self)), displayName: name, preset: settings, provenance: provenance)
    }
    static let all: [ProceduralLook] = [
        .init(id: "soft-lens", name: "Soft Lens", detail: "부드러운 디테일·옅은 블룸", settings: .init(intensity: 0, finish: .init(bloom: 0.15, softFocus: 0.5))),
        .init(id: "night-streak", name: "Night Streak", detail: "밝은 광원의 가로 빛 번짐", settings: .init(intensity: 0, finish: .init(halation: 0.2, streak: 0.7))),
        .init(id: "vintage-optics", name: "Vintage Optics", detail: "색수차·비네팅·그레인", settings: .init(intensity: 0, grain: .init(amount: 0.15), finish: .init(vignette: 0.4, chromaticAberration: 0.6))),
        .init(id: "dream-glass", name: "Dream Glass", detail: "부드러운 초점·페이드·블룸", settings: .init(intensity: 0, finish: .init(fade: 0.2, bloom: 0.4, softFocus: 0.7))),
        .init(id: "mist-light", name: "Mist Light", detail: "가벼운 디퓨전·그레인", settings: .init(intensity: 0, grain: .init(amount: 0.2), finish: .init(bloom: 0.3, softFocus: 0.2))),
        .init(id: "glow-portrait", name: "Glow Portrait", detail: "부드러운 윤곽·따뜻한 명부 확산", settings: .init(intensity: 0, finish: .init(bloom: 0.25, halation: 0.12, softFocus: 0.25))),
        .init(id: "film-projector", name: "Film Projector", detail: "그레인·페이드·주변부 색수차", settings: .init(intensity: 0, grain: .init(amount: 0.4), finish: .init(fade: 0.25, vignette: 0.5, chromaticAberration: 0.2))),
        .init(id: "clear-star", name: "Clear Star", detail: "절제된 가로 광원 확산", settings: .init(intensity: 0, finish: .init(vignette: 0.1, streak: 0.35)))
    ]
}
