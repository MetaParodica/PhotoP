import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

struct SceneLine: Codable, Equatable, Sendable {
    let start: CGPoint
    let end: CGPoint
    var angle: Double { atan2(Double(end.y - start.y), Double(end.x - start.x)) * 180 / .pi }
}

// A fixed, oriented TOP-left raster. Values describe encoded SDR, not raw sensor
// clipping, scene illumination in lux, object classes or photographic quality.
struct ScenePhotometry: Codable, Equatable, Sendable {
    let mean: Double
    let highlights: Double
    let shadows: Double
    let edgeContrast: Double
    let leftRightDifference: Double
    let topBottomDifference: Double
    let mirrorDifference: Double
    let meanRGB: [Double]
    let grid: [Double]
    let side: Int

    func brightness(in region: CGRect) -> Double? {
        let box = region.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !box.isNull, box.width > 0, box.height > 0, side > 0, grid.count == side * side else { return nil }
        var total = 0.0, count = 0
        for y in 0..<side { for x in 0..<side {
            if box.contains(CGPoint(x: (Double(x) + 0.5) / Double(side), y: (Double(y) + 0.5) / Double(side))) {
                total += grid[y * side + x]; count += 1
            }
        } }
        return count > 0 ? total / Double(count) : nil
    }

    static func measure(rgba: [UInt8], side: Int) -> ScenePhotometry? {
        guard (8...128).contains(side), rgba.count == side * side * 4 else { return nil }
        var grid = [Double](repeating: 0, count: side * side)
        var colors = [Double](repeating: 0, count: 3), highlights = 0, shadows = 0
        for i in grid.indices {
            let r = Double(rgba[i * 4]) / 255, g = Double(rgba[i * 4 + 1]) / 255, b = Double(rgba[i * 4 + 2]) / 255
            grid[i] = 0.2126 * r + 0.7152 * g + 0.0722 * b
            colors[0] += r; colors[1] += g; colors[2] += b
            if max(r, g, b) >= 0.98 { highlights += 1 }
            if grid[i] <= 0.04 { shadows += 1 }
        }
        let n = Double(grid.count)
        var edge = 0.0, left = 0.0, right = 0.0, top = 0.0, bottom = 0.0, mirror = 0.0
        for y in 0..<side { for x in 0..<side {
            let value = grid[y * side + x]
            if x < side / 2 { left += value } else { right += value }
            if y < side / 2 { top += value } else { bottom += value }
            mirror += abs(value - grid[y * side + side - 1 - x])
            if x > 0 { edge += abs(value - grid[y * side + x - 1]) }
            if y > 0 { edge += abs(value - grid[(y - 1) * side + x]) }
        } }
        return ScenePhotometry(mean: grid.reduce(0, +) / n, highlights: Double(highlights) / n, shadows: Double(shadows) / n,
            edgeContrast: edge / Double(2 * side * (side - 1)), leftRightDifference: (left - right) / (n / 2),
            topBottomDifference: (top - bottom) / (n / 2), mirrorDifference: mirror / n,
            meanRGB: colors.map { $0 / n }, grid: grid, side: side)
    }

    // Small bounded Hough transform of measured image edges. No downloaded model
    // or semantic interpretation. Maximum 900 sampled edges and six line peaks.
    func lines() -> [SceneLine] {
        guard side >= 8, side <= 128, grid.count == side * side else { return [] }
        var edges: [(Double, Double)] = []
        for y in stride(from: 1, to: side - 1, by: 2) {
            for x in stride(from: 1, to: side - 1, by: 2) {
                let dx = grid[y * side + x + 1] - grid[y * side + x - 1]
                let dy = grid[(y + 1) * side + x] - grid[(y - 1) * side + x]
                if hypot(dx, dy) > 0.22 { edges.append((Double(x) / Double(side - 1), Double(y) / Double(side - 1))) }
            }
        }
        if edges.count > 900 { edges = Array(edges.enumerated().filter { $0.offset % 3 == 0 }.map(\.element).prefix(900)) }
        guard edges.count >= 12 else { return [] }
        var peaks: [(Int, Int, Int)] = []
        for angle in 0..<36 {
            let theta = Double(angle) * .pi / 36, c = cos(theta), s = sin(theta)
            var bins = [Int](repeating: 0, count: 145)
            for (x, y) in edges {
                let index = Int(((x * c + y * s) + 1.5) * 48)
                if bins.indices.contains(index) { bins[index] += 1 }
            }
            for index in bins.indices where bins[index] >= max(10, side / 5) { peaks.append((bins[index], angle, index)) }
        }
        peaks.sort { $0.0 > $1.0 }
        var chosen: [(Int, Int)] = [], output: [SceneLine] = []
        for (_, angle, index) in peaks {
            guard !chosen.contains(where: { min(abs($0.0 - angle), 36 - abs($0.0 - angle)) < 3 && abs($0.1 - index) < 5 }) else { continue }
            let theta = Double(angle) * .pi / 36, c = cos(theta), s = sin(theta), rho = Double(index) / 48 - 1.5
            var points: [CGPoint] = []
            if abs(s) > 0.001 { for x in [0.0, 1.0] { let y = (rho - x * c) / s; if (0...1).contains(y) { points.append(CGPoint(x: x, y: y)) } } }
            if abs(c) > 0.001 { for y in [0.0, 1.0] { let x = (rho - y * s) / c; if (0...1).contains(x) { points.append(CGPoint(x: x, y: y)) } } }
            guard let first = points.first, let last = points.last, hypot(first.x - last.x, first.y - last.y) > 0.35 else { continue }
            output.append(SceneLine(start: first, end: last)); chosen.append((angle, index))
            if output.count == 6 { break }
        }
        return output
    }
}

struct SceneEvidence: Sendable {
    var generatedAt: Double = 0
    var horizonDegrees: Double?
    var rectangles: [[CGPoint]] = [] // top-left origin, TL TR BR BL
    var saliency: [CGRect] = [] // attention regions, NEVER object classification
    var photometry: ScenePhotometry?
    var lines: [SceneLine] = []
    func isFresh(at time: Double) -> Bool { time >= generatedAt && time - generatedAt <= 1.2 }
    var rectangleBounds: [CGRect] {
        rectangles.compactMap { points in
            guard points.count == 4, points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
            let xs = points.map(\.x), ys = points.map(\.y)
            return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        }
    }
    var verticalConvergence: Double? {
        guard let quad = rectangles.first, quad.count == 4 else { return nil }
        let a = atan2(Double(quad[3].x - quad[0].x), Double(quad[3].y - quad[0].y))
        let b = atan2(Double(quad[2].x - quad[1].x), Double(quad[2].y - quad[1].y))
        return abs(a - b) * 180 / .pi
    }
    var intersection: CGPoint? {
        var points: [CGPoint] = []
        for i in lines.indices { for j in lines.indices where j > i {
            let a = lines[i], b = lines[j]
            let dx = a.end.x - a.start.x, dy = a.end.y - a.start.y
            let ex = b.end.x - b.start.x, ey = b.end.y - b.start.y
            let det = dx * ey - dy * ex
            guard abs(det) > 0.15 else { continue }
            let t = ((b.start.x - a.start.x) * ey - (b.start.y - a.start.y) * ex) / det
            let point = CGPoint(x: a.start.x + t * dx, y: a.start.y + t * dy)
            if CGRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9).contains(point) { points.append(point) }
        } }
        guard !points.isEmpty else { return nil }
        return CGPoint(x: points.map(\.x).reduce(0, +) / CGFloat(points.count), y: points.map(\.y).reduce(0, +) / CGFloat(points.count))
    }
}
