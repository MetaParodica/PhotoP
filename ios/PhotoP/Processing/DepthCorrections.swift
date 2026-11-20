import Foundation

struct DepthBrushPoint: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
    var valid: Bool { x.isFinite && y.isFinite && (0...1).contains(x) && (0...1).contains(y) }
}
enum DepthBrushMode: String, Codable, CaseIterable, Sendable { case foreground, background }
struct DepthBrushStroke: Codable, Hashable, Sendable {
    var points: [DepthBrushPoint]
    var mode: DepthBrushMode
    var radius: Double // fraction of image long edge; isotropic in image pixels
    var softness: Double
    var protectedRange: ClosedRange<Float>?
    var valid: Bool {
        !points.isEmpty && points.count <= 128 && points.allSatisfy(\.valid) && radius.isFinite && (0.003...0.2).contains(radius) &&
        softness.isFinite && (0...1).contains(softness) && (protectedRange.map {
            $0.lowerBound.isFinite && $0.upperBound.isFinite && $0.lowerBound > 0 && $0.upperBound >= $0.lowerBound
        } ?? true)
    }
}
struct DepthCorrections: Codable, Hashable, Sendable {
    var version = 1
    var strokes: [DepthBrushStroke] = []
    var valid: Bool { version == 1 && strokes.count <= 64 && strokes.reduce(0) { $0 + $1.points.count } <= 1024 && strokes.allSatisfy(\.valid) }
    func applying(to base: SoftwareDepthField) -> SoftwareDepthField? {
        guard valid else { return nil }
        guard !strokes.isEmpty else { return base }
        guard let bounds = base.bounds else { return nil }
        var values = base.inverseDepth
        let w = base.width, h = base.height, edge = Double(max(w,h))
        let sx = Double(w) / edge, sy = Double(h) / edge
        for stroke in strokes {
            let points = stroke.points.map { SIMD2($0.x * sx, $0.y * sy) }
            let r = stroke.radius, inner = r * (1 - stroke.softness)
            let x0 = max(0, Int(floor((points.map(\.x).min()! - r) * edge)))
            let x1 = min(w-1, Int(ceil((points.map(\.x).max()! + r) * edge)))
            let y0 = max(0, Int(floor((points.map(\.y).min()! - r) * edge)))
            let y1 = min(h-1, Int(ceil((points.map(\.y).max()! + r) * edge)))
            guard x0 <= x1, y0 <= y1 else { continue }
            for y in y0...y1 { for x in x0...x1 {
                let i = y*w+x
                if let protected = stroke.protectedRange, protected.contains(base.inverseDepth[i]) { continue }
                let p = SIMD2((Double(x)+0.5)/edge, (Double(y)+0.5)/edge)
                var distance2 = Double.infinity
                for j in points.indices {
                    let a = points[j], b = points[min(j+1,points.count-1)], d = b-a, v = p-a
                    let length2 = d.x*d.x+d.y*d.y
                    let t = length2 > 1e-12 ? min(1,max(0,(v.x*d.x+v.y*d.y)/length2)) : 0
                    let delta = v-d*t
                    distance2 = min(distance2,delta.x*delta.x+delta.y*delta.y)
                }
                let distance = sqrt(distance2)
                guard distance <= r else { continue }
                let t = min(1,max(0,(distance-inner)/max(1e-9,r-inner)))
                let weight = Float(1-t*t*(3-2*t))
                let target = stroke.mode == .foreground ? max(values[i],bounds.upper) : (values[i] > 0 ? min(values[i],bounds.lower) : bounds.lower)
                values[i] = values[i]*(1-weight)+target*weight
            } }
        }
        return base.replacingDepthPreservingBounds(values)
    }
}

struct DepthCorrectionHistory: Sendable {
    private(set) var current: DepthCorrections
    private var past: [DepthCorrections] = []
    private var future: [DepthCorrections] = []
    init(_ current: DepthCorrections = .init()) { self.current = current }
    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }
    @discardableResult mutating func append(_ stroke: DepthBrushStroke) -> Bool {
        var next = current; next.strokes.append(stroke)
        guard next.valid else { return false }
        past.append(current); if past.count > 32 { past.removeFirst() }
        future.removeAll(); current = next; return true
    }
    mutating func undo() { guard let last = past.popLast() else { return }; future.append(current); current = last }
    mutating func redo() { guard let next = future.popLast() else { return }; past.append(current); current = next }
}


enum DepthDiagnostic: String, CaseIterable, Hashable, Sendable {
    case result, depth, matte, uncertainty, focusPlane
    var title: String {
        switch self {
        case .result: return "결과"
        case .depth: return "깊이 지도"
        case .matte: return "선택 매트"
        case .uncertainty: return "결측 깊이·혼합 경계"
        case .focusPlane: return "초점면 가이드"
        }
    }
}
