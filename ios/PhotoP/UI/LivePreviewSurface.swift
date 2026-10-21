import SwiftUI
import QuartzCore

@MainActor
final class LivePreviewView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }
    var metalLayer: CAMetalLayer { layer as! CAMetalLayer }
    var preview: LiveLUTPreview? {
        didSet {
            guard oldValue !== preview else { return }
            oldValue?.detach(metalLayer)
            guard let preview else { return }
            metalLayer.device = preview.device
            metalLayer.pixelFormat = .bgra8Unorm
            metalLayer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
            metalLayer.framebufferOnly = true
            metalLayer.maximumDrawableCount = 2
            metalLayer.isOpaque = true
            preview.attach(metalLayer)
        }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = window?.screen.scale ?? traitCollection.displayScale
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
    }
}

struct LivePreviewSurface: UIViewRepresentable {
    let preview: LiveLUTPreview
    func makeUIView(context: Context) -> LivePreviewView {
        let view = LivePreviewView()
        view.preview = preview
        return view
    }
    func updateUIView(_ view: LivePreviewView, context: Context) { view.preview = preview }
    static func dismantleUIView(_ view: LivePreviewView, coordinator: ()) { view.preview = nil }
}
