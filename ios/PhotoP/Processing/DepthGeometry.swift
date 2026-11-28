import Foundation

// Normalized TOP-LEFT coordinates throughout. Intrinsics are not implicitly
// rectified or moved into display space by this companion-image mapping.
struct DepthGeometry: Codable, Equatable, Sendable {
    let colorWidth: Int
    let colorHeight: Int
    let depthWidth: Int
    let depthHeight: Int
    let orientation: UInt32

    var swapsAxes: Bool { (5...8).contains(orientation) }
    var orientedColorWidth: Int { swapsAxes ? colorHeight : colorWidth }
    var orientedColorHeight: Int { swapsAxes ? colorWidth : colorHeight }
    var orientedDepthWidth: Int { swapsAxes ? depthHeight : depthWidth }
    var orientedDepthHeight: Int { swapsAxes ? depthWidth : depthHeight }
    var valid: Bool {
        guard (3...16384).contains(colorWidth), (3...16384).contains(colorHeight),
              colorWidth * colorHeight <= 64_000_000,
              (3...4096).contains(depthWidth), (3...4096).contains(depthHeight),
              depthWidth * depthHeight <= 2_097_152, (1...8).contains(orientation) else { return false }
        let ratio = Double(colorWidth) * Double(depthHeight) / (Double(colorHeight) * Double(depthWidth))
        return abs(ratio - 1) < 0.02
    }

    func matchesOrientedColor(width: Int, height: Int) -> Bool {
        valid && width == orientedColorWidth && height == orientedColorHeight
    }

    func oriented(x: Double, y: Double) -> CGPoint? {
        guard valid, x.isFinite, y.isFinite, (0...1).contains(x), (0...1).contains(y) else { return nil }
        switch orientation {
        case 1: return CGPoint(x: x, y: y)
        case 2: return CGPoint(x: 1-x, y: y)
        case 3: return CGPoint(x: 1-x, y: 1-y)
        case 4: return CGPoint(x: x, y: 1-y)
        case 5: return CGPoint(x: y, y: x)
        case 6: return CGPoint(x: 1-y, y: x)
        case 7: return CGPoint(x: 1-y, y: 1-x)
        case 8: return CGPoint(x: y, y: 1-x)
        default: return nil
        }
    }

    func original(x: Double, y: Double) -> CGPoint? {
        let inverse: UInt32 = orientation == 6 ? 8 : orientation == 8 ? 6 : orientation
        return DepthGeometry(colorWidth: orientedColorWidth, colorHeight: orientedColorHeight,
            depthWidth: orientedDepthWidth, depthHeight: orientedDepthHeight, orientation: inverse).oriented(x: x, y: y)
    }

    // Crop is expressed in the ORIENTED image. A point outside the crop is
    // rejected, never silently clamped onto an unrelated visible subject.
    func display(x: Double, y: Double, crop: CGRect, mirrored: Bool) -> CGPoint? {
        guard let p = oriented(x: x, y: y), crop.minX.isFinite, crop.minY.isFinite,
              crop.width.isFinite, crop.height.isFinite, crop.width > 0, crop.height > 0,
              crop.minX >= 0, crop.minY >= 0, crop.maxX <= 1, crop.maxY <= 1,
              p.x >= crop.minX, p.x <= crop.maxX, p.y >= crop.minY, p.y <= crop.maxY else { return nil }
        let nx = (p.x - crop.minX) / crop.width
        return CGPoint(x: mirrored ? 1-nx : nx, y: (p.y-crop.minY) / crop.height)
    }
}

enum DepthFocusEstimator {
    // Protect a narrow, supported surface under the actual touch even when
    // background pixels outnumber it. An isolated spike cannot pin focus.
    static func value(in field: SoftwareDepthField, x: Double, y: Double) -> Float? {
        guard x.isFinite, y.isFinite, (0...1).contains(x), (0...1).contains(y) else { return nil }
        let cx = min(field.width-1, Int(x * Double(field.width)))
        let cy = min(field.height-1, Int(y * Double(field.height)))
        let anchor = field.inverseDepth[cy * field.width + cx]
        var values: [Float] = []
        for row in max(0, cy-1)...min(field.height-1, cy+1) {
            for col in max(0, cx-1)...min(field.width-1, cx+1) {
                let v = field.inverseDepth[row * field.width + col]
                if v > 0 { values.append(v) }
            }
        }
        guard values.count >= 3 else { return nil }
        if anchor > 0 {
            let scale = field.units == .inverseMetres ? anchor : field.bounds.map { $0.upper-$0.lower } ?? anchor
            let tolerance = max(0.00001, scale * 0.08)
            let support = values.filter { abs($0-anchor) <= tolerance }.sorted()
            if support.count >= 3 { return support[support.count/2] }
        }
        values.sort()
        return values[values.count/2]
    }
}
