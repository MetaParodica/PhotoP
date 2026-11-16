@preconcurrency import AVFoundation
@preconcurrency import CoreImage
import Foundation

struct LiveDepthSettings: Equatable, Sendable {
    var enabled = false
    var aperture = 2.8
    var focus = CGPoint(x: 0.5, y: 0.5)
    var profile: DepthLensProfile = .natural
    var comparingOriginal = false
}
struct LiveDepthFrame: Sendable {
    let field: SoftwareDepthField
    let matte: DepthMatteSurface?
    let settings: LiveDepthSettings
}
private struct ImmutableDepthBuffer: @unchecked Sendable { let buffer: CVPixelBuffer }

// One inference in flight, one latest field. Model/matte run off capture queue.
// Motion/age invalidates depth instead of presenting an old field as current.
final class LiveDepthAnalyzer: @unchecked Sendable {
    private let lock = NSLock()
    private let analysisQueue = DispatchQueue(label: "com.photop.depth-analysis", qos: .userInitiated)
    private let estimator = ExternalDepthEstimator()
    private let matteRefiner = DepthMatteRefiner()
    private let analysisContext = CIContext(options: [.cacheIntermediates: false])
    private let motionContext = CIContext(options: [.cacheIntermediates: false]) // frameQueue only
    private var settings = LiveDepthSettings()
    private var running = false
    private var busy = false
    private var generation: UInt64 = 0
    private var temporal = DepthTemporalState()
    private var matte: DepthMatteSurface?
    private var size = CGSize.zero
    private var lastOffer = -Double.infinity
    private var lastError: String?
    var errorDescription: String? { lock.withLock { lastError } }

    func configure(_ value: LiveDepthSettings) {
        lock.withLock {
            if value.enabled != settings.enabled { generation &+= 1; temporal.reset(); matte = nil; lastError = nil }
            if value.focus != settings.focus { matte = nil }
            settings = value
        }
    }
    func setRunning(_ value: Bool) {
        lock.withLock { if running != value { generation &+= 1; temporal.reset(); matte = nil }; running = value }
    }
    func invalidate() { lock.withLock { generation &+= 1; temporal.reset(); matte = nil; size = .zero } }

    func offer(_ buffer: CVPixelBuffer, minimumInterval: Double) {
        // Critical thermal budgets use infinity to suspend analysis. In the
        // first frame, infinity - (-infinity) would otherwise admit one job.
        guard minimumInterval.isFinite, minimumInterval >= 0.2 else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let job: (UInt64, LiveDepthSettings)? = lock.withLock {
            guard running, settings.enabled, !settings.comparingOriginal, !busy, now - lastOffer >= max(0.35, minimumInterval) else { return nil }
            busy = true; lastOffer = now; return (generation, settings)
        }
        guard let (epoch, config) = job else { return }
        let owner = ImmutableDepthBuffer(buffer: buffer)
        analysisQueue.async { [self, owner] in
            defer { lock.withLock { busy = false } }
            autoreleasepool {
                do {
                    let space = try LivePreviewImageProcessor.inputColorSpace(owner.buffer, negotiatedSRGB: true)
                    let image = CIImage(cvPixelBuffer: owner.buffer, options: [.colorSpace: space])
                    let prediction = try estimator.estimate(image)
                    let scale = min(1, 160 / max(image.extent.width, image.extent.height))
                    let w = max(3, Int(image.extent.width * scale)), h = max(3, Int(image.extent.height * scale))
                    guard let field = DepthGrid.resized(prediction, width: w, height: h) else { return }
                    let luma = try Self.luminance(image, width: w, height: h, context: analysisContext)
                    let refined = try? matteRefiner.refine(color: image, focus: config.focus, embedded: nil, maximumDimension: 160)
                    lock.withLock {
                        guard running, settings.enabled, generation == epoch else { return }
                        _ = temporal.update(field, luma: luma, time: now, generation: epoch)
                        if settings.focus == config.focus { matte = refined }
                        size = CGSize(width: w, height: h)
                        lastError = nil
                    }
                } catch {
                    lock.withLock { if generation == epoch { temporal.reset(); matte = nil; lastError = error.localizedDescription } }
                }
            }
        }
    }

    // Called only on the capture/render queue. Never waits for Core ML/Vision.
    func current(for image: CIImage) -> LiveDepthFrame? {
        let snapshot = lock.withLock { (running, settings, generation, temporal, matte, size) }
        guard snapshot.0, snapshot.1.enabled, !snapshot.1.comparingOriginal, snapshot.5.width >= 3,
              abs((image.extent.width / image.extent.height) / (snapshot.5.width / snapshot.5.height) - 1) < 0.025,
              let luma = try? Self.luminance(image, width: Int(snapshot.5.width), height: Int(snapshot.5.height), context: motionContext),
              let field = snapshot.3.current(luma: luma, time: ProcessInfo.processInfo.systemUptime, generation: snapshot.2),
              field.bounds != nil,
              field.focusValue(x: Double(snapshot.1.focus.x), y: Double(snapshot.1.focus.y)) != nil else { return nil }
        return .init(field: field, matte: snapshot.4, settings: snapshot.1)
    }
    private static func luminance(_ image: CIImage, width: Int, height: Int, context: CIContext) throws -> [Float] {
        let small = image.transformed(by: CGAffineTransform(scaleX: CGFloat(width) / image.extent.width, y: CGFloat(height) / image.extent.height))
        guard let cg = context.createCGImage(small, from: CGRect(x: 0, y: 0, width: width, height: height), format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!) else { throw CameraError.invalidPhotoData }
        let pixels = try SDRImage.rasterize(cg)
        var result = [Float](repeating: 0, count: width * height)
        for i in result.indices {
            let red = Float(pixels.rgba[i * 4]) * Float(0.2126)
            let green = Float(pixels.rgba[i * 4 + 1]) * Float(0.7152)
            let blue = Float(pixels.rgba[i * 4 + 2]) * Float(0.0722)
            result[i] = (red + green + blue) / 255
        }
        return result
    }
}
