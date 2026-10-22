@preconcurrency import ARKit
import AVFoundation
import CoreImage
import CoreVideo
import SwiftUI

private struct RetainedDepthFrame: @unchecked Sendable { let frame: ARFrame }

private final class DepthSessionEvents: NSObject, ARSessionDelegate, @unchecked Sendable {
    var onError: @Sendable (String) -> Void = { _ in }
    var onDistance: @Sendable (Float?, Bool) -> Void = { _, _ in }
    private var lastUpdate = -Double.infinity
    func session(_ session: ARSession, didFailWithError error: Error) { onError(error.localizedDescription) }
    func sessionWasInterrupted(_ session: ARSession) { onError("깊이 카메라가 중단되었습니다. 다시 연결해 주세요.") }
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard frame.timestamp - lastUpdate >= 0.25 else { return }
        lastUpdate = frame.timestamp
        guard let depth = frame.sceneDepth else { onDistance(nil, false); return }
        let map = depth.depthMap
        guard CVPixelBufferLockBaseAddress(map, .readOnly) == kCVReturnSuccess else { onDistance(nil, false); return }
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        guard let address = CVPixelBufferGetBaseAddress(map) else { onDistance(nil, false); return }
        let row = address.advanced(by: (CVPixelBufferGetHeight(map) / 2) * CVPixelBufferGetBytesPerRow(map)).assumingMemoryBound(to: Float.self)
        let distance = row[CVPixelBufferGetWidth(map) / 2]
        onDistance(distance.isFinite && distance > 0 ? distance : nil, depth.confidenceMap != nil)
    }
}

@MainActor
final class DepthCaptureModel: ObservableObject {
    let session = ARSession()
    let supported = ARWorldTrackingConfiguration.isSupported && ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    @Published private(set) var ready = false
    @Published private(set) var busy = false
    @Published private(set) var centerDistance: Float?
    @Published private(set) var latest: StoredDepthCapture?
    @Published var message: String?
    private let events = DepthSessionEvents()
    private var active = false
    init() {
        session.delegate = events
        events.onError = { [weak self] text in Task { @MainActor [weak self] in guard let self, self.active else { return }; self.ready = false; self.message = text } }
        events.onDistance = { [weak self] distance, available in Task { @MainActor [weak self] in guard let self, self.active else { return }; self.centerDistance = distance; self.ready = available } }
    }
    func start() async {
        guard supported, !active else { return }
        active = true
        guard await AVCaptureDevice.requestAccess(for: .video) else { active = false; message = CameraError.permission.localizedDescription; return }
        guard active else { return }
        message = nil
        let configuration = ARWorldTrackingConfiguration()
        configuration.frameSemantics = .sceneDepth
        session.run(configuration)
    }
    func stop() { active = false; session.pause(); ready = false; centerDistance = nil }
    func restart() async { stop(); await start() }
    func capture() async {
        guard !busy else { return }
        guard ready, let frame = session.currentFrame, frame.sceneDepth != nil else { message = "깊이 프레임을 준비 중입니다. 장면이 안정된 뒤 다시 촬영해 주세요."; return }
        busy = true; defer { busy = false }
        let retained = RetainedDepthFrame(frame: frame)
        do {
            latest = try await Task.detached(priority: .userInitiated) {
                let payload = try Self.payload(retained.frame)
                let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                return try DepthCaptureStore.write(payload, documents: documents)
            }.value
        } catch { message = error.localizedDescription }
    }

    nonisolated private static func plane(_ buffer: CVPixelBuffer, bytesPerPixel: Int) throws -> Data {
        guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { throw CameraError.invalidPhotoData }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        guard width > 0, height > 0, width <= 1024, height <= 1024, stride >= width * bytesPerPixel,
              let base = CVPixelBufferGetBaseAddress(buffer) else { throw CameraError.invalidPhotoData }
        var data = Data(capacity: width * height * bytesPerPixel)
        for row in 0..<height { data.append(base.advanced(by: row * stride).assumingMemoryBound(to: UInt8.self), count: width * bytesPerPixel) }
        return data
    }

    nonisolated private static func payload(_ frame: ARFrame) throws -> DepthCapturePayload {
        guard let scene = frame.sceneDepth, let confidenceMap = scene.confidenceMap,
              CVPixelBufferGetPixelFormatType(scene.depthMap) == kCVPixelFormatType_DepthFloat32,
              CVPixelBufferGetPixelFormatType(confidenceMap) == kCVPixelFormatType_OneComponent8,
              CVPixelBufferGetWidth(confidenceMap) == CVPixelBufferGetWidth(scene.depthMap),
              CVPixelBufferGetHeight(confidenceMap) == CVPixelBufferGetHeight(scene.depthMap) else { throw CameraError.invalidPhotoData }
        let depth = try plane(scene.depthMap, bytesPerPixel: 4), confidence = try plane(confidenceMap, bytesPerPixel: 1)
        let image = CIImage(cvPixelBuffer: frame.capturedImage)
        let context = CIContext(options: [.cacheIntermediates: false])
        guard let cg = context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!) else { throw CameraError.invalidPhotoData }
        let jpeg = try SDRImage.rasterize(cg).jpeg()
        let intrinsics = frame.camera.intrinsics, transform = frame.camera.transform
        let metadata = DepthCaptureMetadata(timestamp: frame.timestamp, rgbWidth: cg.width, rgbHeight: cg.height,
            depthWidth: CVPixelBufferGetWidth(scene.depthMap), depthHeight: CVPixelBufferGetHeight(scene.depthMap),
            cameraIntrinsics: (0..<3).flatMap { c in (0..<3).map { r in intrinsics[c][r] } },
            cameraTransform: (0..<4).flatMap { c in (0..<4).map { r in transform[c][r] } },
            depthBytes: depth.count, confidenceBytes: confidence.count, jpegBytes: jpeg.count,
            depthSHA256: LUTPhotoEditor.hash(depth), confidenceSHA256: LUTPhotoEditor.hash(confidence), jpegSHA256: LUTPhotoEditor.hash(jpeg))
        return DepthCapturePayload(metadata: metadata, depth: depth, confidence: confidence, jpeg: jpeg)
    }
}
