import Foundation

// Export limits, not camera capabilities. 8064x6048 (48.8MP) stays full size.
// In-memory preview/Metal jobs retain their separate, smaller safety limit.
struct ImagePixelRegion: Equatable, Sendable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
    var maxX: Int { x + width }
    var maxY: Int { y + height }
}

struct HighResolutionPlan: Sendable {
    static let maximumPixels = 64_000_000
    static let maximumDimension = 16_384
    static let tileSide = 1024
    struct Tile: Equatable, Sendable {
        let output: ImagePixelRegion
        let input: ImagePixelRegion // includes neighbour samples, clipped to image
    }
    let width: Int
    let height: Int
    let halo: Int
    var byteCount: Int { width * height * 4 }
    var minimumFreeBytes: Int64 { Int64(byteCount) + 64 * 1024 * 1024 }
    init?(width: Int, height: Int, halo: Int = 0) {
        guard width > 0, height > 0, width <= Self.maximumDimension, height <= Self.maximumDimension,
              height <= Self.maximumPixels / width, (0...512).contains(halo) else { return nil }
        self.width = width; self.height = height; self.halo = halo
    }
    var tiles: [Tile] {
        var result: [Tile] = []
        for y in stride(from: 0, to: height, by: Self.tileSide) {
            for x in stride(from: 0, to: width, by: Self.tileSide) {
                let right = min(width, x + Self.tileSide), bottom = min(height, y + Self.tileSide)
                let left = max(0, x - halo), top = max(0, y - halo)
                result.append(Tile(output: .init(x: x, y: y, width: right - x, height: bottom - y),
                    input: .init(x: left, y: top, width: min(width, right + halo) - left, height: min(height, bottom + halo) - top)))
            }
        }
        return result
    }
    static func halo(longEdge: Int, neighbours: Bool, chromaticAberration: Double, streak: Bool) -> Int? {
        guard (1...maximumDimension).contains(longEdge), chromaticAberration.isFinite, (0...1).contains(chromaticAberration) else { return nil }
        let radius = max(1, Int((Double(longEdge) * 2 / 1024).rounded()))
        let fringe = Int(ceil(Double(longEdge) * 0.006 * chromaticAberration))
        return max(neighbours ? radius : 0, fringe, streak ? radius * 8 : 0)
    }
}
