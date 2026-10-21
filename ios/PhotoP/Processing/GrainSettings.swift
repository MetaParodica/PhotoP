import Foundation

// Basic monochrome value noise, not a measured film-stock emulation.
struct GrainSettings: Codable, Equatable, Sendable {
    var amount: Double = 0
    var seed: UInt32 = 1

    func validate() throws {
        guard amount.isFinite, (0...1).contains(amount) else {
            throw ImageEditingError.invalid("그레인 강도는 0~100%여야 합니다.")
        }
    }

    // Reference for the shared Metal implementation. Coordinates are normalized
    // to a 512-cell long edge, so a saved seed survives preview/export resizing.
    func noise(x: Int, y: Int, width: Int, height: Int) -> Float {
        let scale = Float(512) / Float(max(width, height))
        let px = (Float(x) + 0.5) * scale, py = (Float(y) + 0.5) * scale
        let ix = UInt32(floor(px)), iy = UInt32(floor(py))
        let fx = px - floor(px), fy = py - floor(py)
        let tx = fx * fx * (3 - 2 * fx), ty = fy * fy * (3 - 2 * fy)
        func value(_ x: UInt32, _ y: UInt32) -> Float {
            var h = (x &* 1664525) &+ (y &* 1013904223) &+ seed
            h = (h ^ (h >> 16)) &* 1664525 &+ 1013904223
            h ^= h >> 13
            return Float(h & 65535) / 32767.5 - 1
        }
        let a = value(ix, iy) * (1 - tx) + value(ix &+ 1, iy) * tx
        let b = value(ix, iy &+ 1) * (1 - tx) + value(ix &+ 1, iy &+ 1) * tx
        return a * (1 - ty) + b * ty
    }
}
