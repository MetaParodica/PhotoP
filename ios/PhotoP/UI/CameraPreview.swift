import AVFoundation
import SwiftUI
import UIKit

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    var onOrientation: ((CameraOrientation) -> Void)?
    private var lastOrientation: CameraOrientation?
    override func layoutSubviews() {
        super.layoutSubviews()
        updateOrientation()
    }
    func updateOrientation() {
        let orientation: CameraOrientation
        switch window?.windowScene?.interfaceOrientation {
        case .landscapeLeft?: orientation = .landscapeLeft
        case .landscapeRight?: orientation = .landscapeRight
        default: orientation = .portrait
        }
        if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(orientation.rotationAngle) {
            connection.videoRotationAngle = orientation.rotationAngle
        }
        if lastOrientation != orientation { lastOrientation = orientation; onOrientation?(orientation) }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let mirrored: Bool
    let lensID: String?
    var zoom: Double = 1
    var onZoom: (Double) -> Void = { _ in }
    var fill = false
    var onOrientation: (CameraOrientation) -> Void = { _ in }
    var onIndicator: (CGPoint, Bool) -> Void = { _, _ in }
    var onSubjectTap: (CGPoint) -> Void = { _ in }
    let onMeter: (CameraMeteringPoint, String, Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        view.previewLayer.session = session
        view.onOrientation = onOrientation
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        let hold = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.hold(_:)))
        hold.minimumPressDuration = 0.5
        tap.require(toFail: hold)
        view.addGestureRecognizer(tap); view.addGestureRecognizer(hold)
        view.addGestureRecognizer(UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinch(_:))))
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        context.coordinator.parent = self
        view.previewLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        view.onOrientation = onOrientation
        guard let connection = view.previewLayer.connection else { return }
        view.updateOrientation()
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = mirrored
        }
    }
    @MainActor
    final class Coordinator: NSObject {
        var parent: CameraPreview
        private var pinchBase: Double?
        init(_ parent: CameraPreview) { self.parent = parent }

        // Pinch scales the zoom current at gesture start; the service clamps to the device range.
        @objc func pinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began: pinchBase = parent.zoom
            case .changed: if let pinchBase, gesture.scale.isFinite { parent.onZoom(pinchBase * Double(gesture.scale)) }
            default: pinchBase = nil
            }
        }

        @objc func tap(_ gesture: UITapGestureRecognizer) {
            meter(gesture, locked: false)
        }
        @objc func hold(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began else { return }
            meter(gesture, locked: true)
        }
        private func meter(_ gesture: UIGestureRecognizer, locked: Bool) {
            guard let view = gesture.view as? PreviewView, let lensID = parent.lensID,
                  view.previewLayer.connection != nil else { return }
            let location = gesture.location(in: view)
            let imageRect = view.previewLayer.layerRectConverted(fromMetadataOutputRect: CGRect(x: 0, y: 0, width: 1, height: 1))
            guard imageRect.contains(location) else { return }
            // Official AVFoundation image rect accounts for rotation, mirroring,
            // letterboxing and aspect-fill. Delivered Vision pixels are already
            // rotated/mirrored too: DO NOT mirror the subject point a second time.
            if !locked, let imagePoint = GuideGeometry.normalizedPoint(location, in: imageRect) {
                parent.onSubjectTap(imagePoint)
            }
            let point = view.previewLayer.captureDevicePointConverted(fromLayerPoint: location)
            guard let normalized = try? CameraMeteringPoint(x: point.x, y: point.y) else { return }
            parent.onIndicator(CGPoint(x: location.x / max(1, view.bounds.width), y: location.y / max(1, view.bounds.height)), locked)
            parent.onMeter(normalized, lensID, locked)
        }
    }

}

struct ThirdsGrid: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            for fraction in [1.0 / 3, 2.0 / 3] {
                path.move(to: CGPoint(x: size.width * fraction, y: 0))
                path.addLine(to: CGPoint(x: size.width * fraction, y: size.height))
                path.move(to: CGPoint(x: 0, y: size.height * fraction))
                path.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
            }
            context.stroke(path, with: .color(.white.opacity(0.45)), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
