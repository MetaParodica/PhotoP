@preconcurrency import AVFoundation
@preconcurrency import CoreVideo
import CoreImage

struct LongExposureProgress: Sendable {
    let fraction: Double
    let accepted: Int
    let rejected: Int
    let previewJPEG: Data?
}

struct LongExposureClock {
    private(set) var firstFrame: TimeInterval?
    mutating func startIfNeeded(at time: TimeInterval) -> Bool {
        guard time.isFinite, firstFrame == nil else { return false }
        firstFrame = time
        return true
    }
    func elapsed(at time: TimeInterval) -> TimeInterval {
        guard let firstFrame, time.isFinite else { return 0 }
        return max(0, time - firstFrame)
    }
}

final class LongExposureCapture: NSObject, @unchecked Sendable, AVCaptureVideoDataOutputSampleBufferDelegate {
    let frameQueue = DispatchQueue(label: "com.photop.long-exposure", qos: .userInitiated)
    private let configuration: LongExposureConfiguration
    private let archive: LongExposureArchive
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var stack: LongExposureStack?
    private var ended = false
    private var clock = LongExposureClock()
    private var lastFrame = -Double.infinity
    private var lastPreview = -Double.infinity
    private var timer: DispatchWorkItem?
    private let onProgress: @Sendable (LongExposureProgress) -> Void
    private let completion: @Sendable (Result<URL, Error>) -> Void

    init(configuration: LongExposureConfiguration, archive: LongExposureArchive,
         onProgress: @escaping @Sendable (LongExposureProgress) -> Void,
         completion: @escaping @Sendable (Result<URL, Error>) -> Void) throws {
        try configuration.validate()
        self.configuration = configuration; self.archive = archive
        self.onProgress = onProgress; self.completion = completion
        super.init()
    }
    func start() {
        frameQueue.async { [self] in
            guard !ended, timer == nil else { return }
            // Give the newly attached stream time to deliver its first frame. The
            // requested exposure duration starts with that frame, not session setup.
            let work = DispatchWorkItem { [weak self] in self?.fail(ImageEditingError.invalid("장노출 입력 프레임이 도착하지 않았습니다. 카메라를 다시 연결해 주세요.")) }
            timer = work
            frameQueue.asyncAfter(deadline: .now() + 10, execute: work)
        }
    }
    func cancel() { frameQueue.async { [self] in fail(CancellationError()) } }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !ended, timer != nil, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if clock.startIfNeeded(at: now) {
            timer?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.finish(reason: "duration") }
            timer = work
            frameQueue.asyncAfter(deadline: .now() + configuration.duration, execute: work)
        }
        if clock.elapsed(at: now) >= configuration.duration { finish(reason: "duration"); return }
        if ProcessInfo.processInfo.thermalState == .critical { fail(ImageEditingError.invalid("발열로 합성을 중단했습니다.")); return }
        let interval = ProcessInfo.processInfo.thermalState == .serious ? 1.0 : 0.5
        guard now - lastFrame >= interval else { return }
        lastFrame = now
        do {
            let space = try LivePreviewImageProcessor.inputColorSpace(buffer, negotiatedSRGB: true)
            let source = CIImage(cvPixelBuffer: buffer, options: [.colorSpace: space])
            let scale = min(1, 1280 / max(source.extent.width, source.extent.height))
            let scaled = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            guard let cg = context.createCGImage(scaled, from: scaled.extent, format: .RGBA8,
                                                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!) else { throw CameraError.invalidPhotoData }
            let image = try SDRImage.rasterize(cg)
            guard try archive.append(image) else { finish(reason: "128MiB archive budget"); return }
            if stack == nil { stack = try LongExposureStack(first: image, configuration: configuration) }
            else { try stack?.add(image) }
            let preview: Data?
            if now - lastPreview >= 1 { preview = try stack?.image().resized(maximumDimension: 256).jpeg(); lastPreview = now }
            else { preview = nil }
            onProgress(.init(fraction: min(clock.elapsed(at: now) / configuration.duration, 1), accepted: stack?.accepted ?? 0,
                             rejected: stack?.rejected ?? 0, previewJPEG: preview))
        } catch { fail(error) }
    }
    private func finish(reason: String) {
        guard !ended else { return }
        do {
            guard let stack else { throw CameraError.missingPhoto }
            let url = try archive.finish(stack: stack, elapsed: clock.elapsed(at: ProcessInfo.processInfo.systemUptime), reason: reason)
            onProgress(.init(fraction: 1, accepted: stack.accepted, rejected: stack.rejected,
                             previewJPEG: try? stack.image().resized(maximumDimension: 256).jpeg()))
            ended = true; timer?.cancel(); timer = nil; completion(.success(url))
        } catch { fail(error) }
    }
    private func fail(_ error: Error) {
        guard !ended else { return }
        ended = true; timer?.cancel(); timer = nil; archive.cancel(); completion(.failure(error))
    }
}
