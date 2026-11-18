import Foundation

enum ExposureFusionFailure: LocalizedError, Equatable {
    case invalidInput, insufficientDetail, alignment, ghost, originalsChanged
    var errorDescription: String? {
        switch self {
        case .invalidInput: return "노출 융합은 같은 크기의 SDR 사진 3장(최대12.6MP)만 지원합니다."
        case .insufficientDetail: return "정렬을 확인할 밝기·윤곽 표본이 부족하여 노출 융합을 거부했습니다."
        case .alignment: return "정렬 이동 또는 잔차가 허용치를 넘어 노출 융합을 거부했습니다."
        case .ghost: return "프레임 사이 움직임·고스트가 의심되어 노출 융합을 거부했습니다."
        case .originalsChanged: return "원본 해시가 달라 노출 융합을 중단했습니다. 원본을 덮어쓰지 않았습니다."
        }
    }
}

struct ExposureFusionWeights: Codable, Equatable, Sendable {
    var contrast = 0.3
    var saturation = 0.2
    var wellExposedness = 1.0
    var valid: Bool { [contrast, saturation, wellExposedness].allSatisfy { $0.isFinite && (0...2).contains($0) } }
}

struct ExposureFusionRegistration: Codable, Equatable, Sendable {
    let x: Int
    let y: Int
    let logExposureOffset: Double
    let residual: Double
    let ghostFraction: Double
    let usableFraction: Double
    static let reference = Self(x: 0, y: 0, logExposureOffset: 0, residual: 0, ghostFraction: 0, usableFraction: 1)
}

/// Conservative translation-only, exposure-normalized registration. These are
/// provisional SDR thresholds, not calibrated camera/quality guarantees.
struct ExposureFusionPolicy: Sendable {
    var searchRadius = 6
    var maximumResidual = 0.18 // RMS log2 encoded-luma difference after offset removal
    var ghostThreshold = 0.45
    var maximumGhostFraction = 0.035
    var minimumUsableFraction = 0.35
    var minimumTexture = 0.025
    var weights = ExposureFusionWeights()

    func validateBiases(_ biases: [Double]) throws {
        guard biases.count == 3, biases.allSatisfy(\.isFinite), biases[0] < biases[1], biases[1] < biases[2],
              biases[2] - biases[0] <= 4.001 else { throw ExposureFusionFailure.invalidInput }
    }
    func register(reference: [Float], candidate: [Float], width: Int, height: Int) throws -> ExposureFusionRegistration {
        guard (1...8).contains(searchRadius), (24...256).contains(width), (24...256).contains(height),
              reference.count == width * height, candidate.count == reference.count,
              reference.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
              candidate.allSatisfy({ $0.isFinite && (0...1).contains($0) }), weights.valid,
              maximumResidual.isFinite, maximumResidual > 0, ghostThreshold.isFinite, ghostThreshold > 0,
              maximumGhostFraction.isFinite, (0...1).contains(maximumGhostFraction),
              minimumUsableFraction.isFinite, (0.1...1).contains(minimumUsableFraction),
              minimumTexture.isFinite, minimumTexture > 0 else { throw ExposureFusionFailure.invalidInput }
        let a = reference.map { log2(max(0.001, Double($0))) }
        let b = candidate.map { log2(max(0.001, Double($0))) }
        let margin = searchRadius + 1
        let total = (width - margin * 2) * (height - margin * 2)
        guard total >= 36 else { throw ExposureFusionFailure.insufficientDetail }
        let mean = a.reduce(0, +) / Double(a.count)
        let texture = sqrt(a.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(a.count))
        guard texture >= minimumTexture else { throw ExposureFusionFailure.insufficientDetail }
        var best: ExposureFusionRegistration?
        for dy in -searchRadius...searchRadius { for dx in -searchRadius...searchRadius {
            var count = 0, sum = 0.0, squares = 0.0
            for y in margin..<(height - margin) { for x in margin..<(width - margin) {
                let i = y * width + x, j = (y + dy) * width + x + dx
                guard (0.03...0.97).contains(reference[i]), (0.03...0.97).contains(candidate[j]) else { continue }
                let delta = b[j] - a[i]
                count += 1; sum += delta; squares += delta * delta
            } }
            let fraction = Double(count) / Double(total)
            guard fraction >= minimumUsableFraction else { continue }
            let offset = sum / Double(count)
            let residual = sqrt(max(0, squares / Double(count) - offset * offset))
            let score = residual + Double(dx * dx + dy * dy) * 1e-7
            let previous = best.map { $0.residual + Double($0.x * $0.x + $0.y * $0.y) * 1e-7 } ?? .infinity
            if score < previous {
                best = .init(x: dx, y: dy, logExposureOffset: offset, residual: residual, ghostFraction: 0, usableFraction: fraction)
            }
        } }
        guard let best else { throw ExposureFusionFailure.insufficientDetail }
        guard abs(best.x) < searchRadius, abs(best.y) < searchRadius else { throw ExposureFusionFailure.alignment }
        var count = 0, ghosts = 0
        for y in margin..<(height - margin) { for x in margin..<(width - margin) {
            let i = y * width + x, j = (y + best.y) * width + x + best.x
            guard (0.03...0.97).contains(reference[i]), (0.03...0.97).contains(candidate[j]) else { continue }
            count += 1
            if abs(b[j] - a[i] - best.logExposureOffset) > ghostThreshold { ghosts += 1 }
        } }
        let ghostFraction = Double(ghosts) / Double(max(1, count))
        if ghostFraction > maximumGhostFraction { throw ExposureFusionFailure.ghost }
        if best.residual > maximumResidual { throw ExposureFusionFailure.alignment }
        return .init(x: best.x, y: best.y, logExposureOffset: best.logExposureOffset,
                     residual: best.residual, ghostFraction: ghostFraction, usableFraction: best.usableFraction)
    }
}
