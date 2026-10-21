import SwiftUI

// Draws an annotated composition preset: white thirds, dashed zones/points/lines and handwritten notes.
struct CompositionPresetOverlay: View {
    let preset: CompositionPreset
    var opacity: Double = 1
    var showNotes = true
    var lineScale: CGFloat = 1
    var body: some View {
        GeometryReader { geometry in
            let rect = GuideGeometry.imageRect(image: CGSize(width: 3, height: 4), viewport: geometry.size)
            Canvas { context, _ in
                CompositionPresetOverlay.draw(preset, in: rect, context: context, opacity: opacity, showNotes: showNotes, lineScale: lineScale)
            }
        }.allowsHitTesting(false)
            .accessibilityElement().accessibilityLabel("구도 가이드: \(preset.title). \(preset.detail)")
            .accessibilityIdentifier(showNotes ? "camera.composition.preset" : "")
            // Card thumbnails reuse this view; only the viewfinder overlay is exposed.
            .accessibilityHidden(!showNotes)
    }

    static func draw(_ preset: CompositionPreset, in rect: CGRect, context: GraphicsContext, opacity: Double, showNotes: Bool, lineScale: CGFloat) {
        func map(_ p: CGPoint) -> CGPoint { CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height) }
        var c = context
        c.clip(to: Path(rect))
        let white = Color.white.opacity(0.9 * opacity)
        let dashed = StrokeStyle(lineWidth: 1.4 * lineScale, lineCap: .round, dash: [5 * lineScale, 4 * lineScale])
        if preset.thirds {
            var grid = Path()
            for f in [1.0 / 3, 2.0 / 3] {
                grid.move(to: map(.init(x: f, y: 0))); grid.addLine(to: map(.init(x: f, y: 1)))
                grid.move(to: map(.init(x: 0, y: f))); grid.addLine(to: map(.init(x: 1, y: f)))
            }
            c.stroke(grid, with: .color(.white.opacity(0.75 * opacity)), lineWidth: 0.8 * lineScale)
        }
        var shadowed = c
        shadowed.addFilter(.shadow(color: .black.opacity(0.55), radius: 1.5 * lineScale))
        for mark in preset.marks {
            switch mark {
            case .zone(let zone):
                let a = map(zone.origin), b = map(.init(x: zone.maxX, y: zone.maxY))
                shadowed.stroke(Path(CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)), with: .color(white), style: dashed)
            case .point(let center, let radius):
                let p = map(center), r = radius * rect.width
                shadowed.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(white), style: dashed)
            case .line(let points, let closed):
                guard let first = points.first else { continue }
                var path = Path(); path.move(to: map(first))
                for point in points.dropFirst() { path.addLine(to: map(point)) }
                if closed { path.closeSubpath() }
                shadowed.stroke(path, with: .color(white), style: dashed)
            case .note(let text, let at, let target):
                guard showNotes else { continue }
                let anchor = map(at)
                shadowed.draw(Text(text).font(.custom("Noteworthy-Bold", size: 13)).foregroundStyle(white), at: anchor)
                if let target { shadowed.stroke(arrow(from: anchor, to: map(target), lines: text.split(separator: "\n").count), with: .color(white), lineWidth: 1.3) }
            }
        }
    }

    // Curved hand-drawn style arrow leaving the note toward the target.
    static func arrow(from note: CGPoint, to target: CGPoint, lines: Int) -> Path {
        let dx = target.x - note.x, dy = target.y - note.y
        let length = max(1, (dx * dx + dy * dy).squareRoot())
        let ux = dx / length, uy = dy / length
        let clearance = CGFloat(8 * max(1, lines) + 6)
        let start = CGPoint(x: note.x + ux * clearance, y: note.y + uy * clearance)
        let control = CGPoint(x: (start.x + target.x) / 2 - uy * 18, y: (start.y + target.y) / 2 + ux * 18)
        var path = Path()
        path.move(to: start)
        path.addQuadCurve(to: target, control: control)
        let hx = target.x - control.x, hy = target.y - control.y
        let h = max(1, (hx * hx + hy * hy).squareRoot())
        let bx = hx / h, by = hy / h
        path.move(to: target); path.addLine(to: CGPoint(x: target.x - bx * 7 - by * 4, y: target.y - by * 7 + bx * 4))
        path.move(to: target); path.addLine(to: CGPoint(x: target.x - bx * 7 + by * 4, y: target.y - by * 7 - bx * 4))
        return path
    }
}

// Horizontal card picker under the viewfinder, shared by composition guides and looks.
struct CameraCarouselItem: Identifiable {
    let id: String
    let title: String
    var selected = false
    let thumbnail: AnyView
    let action: () -> Void
}

struct CameraCarousel: View {
    let title: String
    let items: [CameraCarouselItem]
    let identifier: String
    private let accent = Color(red: 0.78, green: 0.69, blue: 1)
    var body: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items) { item in
                        Button(action: item.action) {
                            VStack(spacing: 4) {
                                item.thumbnail
                                    .accessibilityHidden(true)
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 12).stroke(item.selected ? accent : .white.opacity(0.15), lineWidth: item.selected ? 2 : 0.5)
                                    }
                                    .overlay {
                                        if item.selected {
                                            Image(systemName: "checkmark").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                                                .shadow(radius: 3)
                                        }
                                    }
                                Text(item.title).font(.system(size: 10, weight: .medium)).lineLimit(1)
                                    .foregroundStyle(item.selected ? accent : .white.opacity(0.85)).frame(width: 68)
                            }
                        }.buttonStyle(.plain).id(item.id)
                            .accessibilityIdentifier("camera.card.\(item.id)")
                            .accessibilityLabel(item.title).accessibilityAddTraits(item.selected ? .isSelected : [])
                    }
                }.padding(.horizontal, 16)
            }
            .onAppear { if let selected = items.first(where: \.selected) { reader.scrollTo(selected.id, anchor: .center) } }
        }.frame(height: 88)
            .accessibilityElement(children: .contain).accessibilityLabel(title)
            .accessibilityIdentifier(identifier)
    }
}

// Thumbnail tiles for carousel cards.
struct GuideThumbnail: View {
    let preset: CompositionPreset?
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.22, green: 0.24, blue: 0.3), Color(red: 0.14, green: 0.13, blue: 0.18)], startPoint: .top, endPoint: .bottom)
            if let preset { CompositionPresetOverlay(preset: preset, showNotes: false, lineScale: 0.6) }
            else { Image(systemName: "nosign").font(.system(size: 20)).foregroundStyle(.white.opacity(0.6)) }
        }
    }
}

struct SymbolThumbnail: View {
    let symbol: String
    var body: some View {
        ZStack {
            Color(white: 0.16)
            Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(.white.opacity(0.8))
        }
    }
}

struct LookThumbnail: View {
    // Generated sample scene (not a photo): sky, distant hills, foliage, ground, shadow, with a skin tone disc.
    static let scene: [SIMD3<Double>] = [.init(0.55, 0.72, 0.92), .init(0.78, 0.84, 0.92), .init(0.42, 0.52, 0.45),
                                         .init(0.3, 0.52, 0.24), .init(0.62, 0.5, 0.36), .init(0.12, 0.12, 0.13), .init(0.86, 0.64, 0.52)]
    let colors: [SIMD3<Double>]
    private func color(_ i: Int) -> Color {
        let v = colors.indices.contains(i) ? colors[i] : .zero
        return Color(.sRGB, red: v.x, green: v.y, blue: v.z, opacity: 1)
    }
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    LinearGradient(colors: [color(0), color(1)], startPoint: .top, endPoint: .bottom).frame(height: g.size.height * 0.45)
                    color(2).frame(height: g.size.height * 0.12)
                    color(3).frame(height: g.size.height * 0.18)
                    LinearGradient(colors: [color(4), color(5)], startPoint: .top, endPoint: .bottom)
                }
                Circle().fill(color(6)).frame(width: g.size.width * 0.3).offset(x: g.size.width * 0.58, y: g.size.height * 0.28)
            }
        }
    }
}
