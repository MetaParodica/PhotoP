import AVFoundation
import SwiftUI
import UIKit

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let mirrored: Bool
    let lensID: String?
    let onMeter: (CameraMeteringPoint, String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.videoGravity = .resizeAspect
        view.previewLayer.session = session
        view.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:))))
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        context.coordinator.parent = self
        guard let connection = view.previewLayer.connection else { return }
        if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = mirrored
        }
    }
    final class Coordinator: NSObject {
        var parent: CameraPreview
        init(_ parent: CameraPreview) { self.parent = parent }

        @objc func tap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? PreviewView, let lensID = parent.lensID,
                  view.previewLayer.connection != nil else { return }
            let location = gesture.location(in: view)
            let imageRect = view.previewLayer.layerRectConverted(fromMetadataOutputRect: CGRect(x: 0, y: 0, width: 1, height: 1))
            guard imageRect.contains(location) else { return }
            let point = view.previewLayer.captureDevicePointConverted(fromLayerPoint: location)
            guard let normalized = try? CameraMeteringPoint(x: point.x, y: point.y) else { return }
            parent.onMeter(normalized, lensID)
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
