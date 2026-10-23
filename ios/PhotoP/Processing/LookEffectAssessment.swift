import Foundation

// Deterministic color-table diagnostic, NOT camera preview, a photo-quality
// score, or proof that a particular scene should visibly change.
struct LookEffectAssessment: Sendable {
    let meanChannelChange: Double
    let notice: String?
    static func evaluate(_ lut: CubeLUT, intensity: Double, grain: Double, spatial: Bool) throws -> LookEffectAssessment {
        guard intensity.isFinite, (0...1).contains(intensity), grain.isFinite, (0...1).contains(grain) else { throw CubeLUTError.invalid("룩 강도가 유효하지 않습니다.") }
        var total = 0.0
        for b in 0...4 { for g in 0...4 { for r in 0...4 {
            let input = SIMD3(Double(r), Double(g), Double(b)) / 4
            let output = try lut.sample(input, intensity: intensity)
            for c in 0..<3 { total += abs(min(1, max(0, output[c])) - input[c]) }
        } } }
        let mean = total / (125 * 3)
        let notice: String?
        if intensity == 0, grain == 0, !spatial { notice = "강도 0% · 색상·입자·마감 효과가 모두 꺼져 있습니다." }
        else if mean < 1.0 / 255, grain > 0 || spatial {
            notice = "색상 변화보다 입자·공간 효과가 중심인 룩입니다. 광원·질감이 적은 장면에서는 차이가 작을 수 있습니다."
        } else if mean < 1.0 / 255 {
            notice = "표준 색 샘플에서 변화가 작은 LUT입니다. 강도 또는 다른 룩을 확인하세요. 원본 표를 임의로 증폭하지 않습니다."
        } else { notice = nil }
        return LookEffectAssessment(meanChannelChange: mean, notice: notice)
    }
}
