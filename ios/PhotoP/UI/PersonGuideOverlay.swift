import SwiftUI

// Person placement silhouettes on the 3:4 image rect. White outlines are targets, not detections.
struct PersonGuideOverlay: View {
    let guide: PersonGuide
    let opacity: Double
    let snapshot: CompositionSnapshot?
    let live: Bool
    let sourceSize: CGSize?
    var fill = false
    var body: some View {
        GeometryReader { geometry in
            let imageSize = sourceSize ?? CGSize(width: 3, height: 4)
            let rect = GuideGeometry.imageRect(image: imageSize, viewport: geometry.size, fill: fill)
            Canvas { context, _ in
                let placements = guide.placements(aspect: rect.height > 0 ? rect.width / rect.height : 0.75)
                func map(_ p: CGPoint) -> CGPoint { CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height) }
                var clipped = context
                clipped.clip(to: Path(rect))
                for placement in placements {
                    clipped.fill(PersonGuideOverlay.silhouette(placement, map: map), with: .color(.white.opacity(0.12 * opacity)))
                    clipped.stroke(PersonGuideOverlay.silhouette(placement, map: map), with: .color(.white.opacity(0.85 * opacity)),
                                   style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                }
                if let first = placements.first, guide.framing != .full {
                    var eye = Path()
                    eye.move(to: map(.init(x: 0, y: first.eyeY))); eye.addLine(to: map(.init(x: 1, y: first.eyeY)))
                    clipped.stroke(eye, with: .color(.yellow.opacity(0.7 * opacity)), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                    clipped.draw(Text("눈높이").font(.system(size: 9, weight: .semibold)).foregroundStyle(.yellow.opacity(opacity)),
                                 at: map(.init(x: 0.04, y: first.eyeY)) + CGPoint(x: 14, y: -8))
                }
                if guide.framing == .full, let first = placements.first {
                    var feet = Path()
                    let y = first.top + PersonGuide.ankleY * first.scale
                    feet.move(to: map(.init(x: 0, y: y))); feet.addLine(to: map(.init(x: 1, y: y)))
                    clipped.stroke(feet, with: .color(.yellow.opacity(0.7 * opacity)), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                    clipped.draw(Text("발끝").font(.system(size: 9, weight: .semibold)).foregroundStyle(.yellow.opacity(opacity)),
                                 at: map(.init(x: 0.04, y: y)) + CGPoint(x: 10, y: -8))
                }
            }
        }.allowsHitTesting(false)
            .accessibilityElement().accessibilityLabel(guide.framing == .off ? "" : "인물 위치 가이드: \(guide.framing.title), \(guide.position.title)")
            .accessibilityHidden(guide.framing == .off)
            .accessibilityIdentifier("camera.person.guide")
    }

    static func silhouette(_ placement: PersonGuide.Placement, map: (CGPoint) -> CGPoint) -> Path {
        var path = Path()
        let headCenter = placement.point(.init(x: 0, y: 0.065))
        let headTop = placement.point(.init(x: 0, y: 0))
        let headSide = placement.point(.init(x: 0.052, y: 0.065))
        let rx = headSide.x - headCenter.x, ry = headCenter.y - headTop.y
        let a = map(CGPoint(x: headCenter.x - rx, y: headCenter.y - ry)), b = map(CGPoint(x: headCenter.x + rx, y: headCenter.y + ry))
        path.addEllipse(in: CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y))
        let right = PersonGuide.outline.map { map(placement.point($0)) }
        let left = PersonGuide.outline.reversed().map { map(placement.point(.init(x: -$0.x, y: $0.y))) }
        guard let start = right.first else { return path }
        path.move(to: start)
        for point in right.dropFirst() + left { path.addLine(to: point) }
        path.closeSubpath()
        return path
    }
}

private func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint { CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y) }

// Dims the area outside a 1:1 or 16:9 framing guide. The capture itself keeps the native aspect.
struct FramingMaskOverlay: View {
    let aspect: FramingAspect
    var imageSize = CGSize(width: 3, height: 4)
    var fill = false
    var body: some View {
        GeometryReader { geometry in
            let image = GuideGeometry.imageRect(image: imageSize, viewport: geometry.size, fill: fill)
            let frame = aspect.rect(in: image)
            ZStack {
                Path { path in path.addRect(image); path.addRect(frame) }
                    .fill(.black.opacity(0.55), style: FillStyle(eoFill: true))
                Path(frame).stroke(.white.opacity(0.7), lineWidth: 1)
                Text("\(aspect.title) 프레이밍 · 원본 4:3 저장").font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 8).padding(.vertical, 4).background(.black.opacity(0.5), in: Capsule())
                    .position(x: frame.midX, y: max(frame.minY, 96) + 12)
            }
        }.allowsHitTesting(false).accessibilityLabel("\(aspect.title) 프레이밍 가이드. 저장 원본은 4:3입니다.")
    }
}
