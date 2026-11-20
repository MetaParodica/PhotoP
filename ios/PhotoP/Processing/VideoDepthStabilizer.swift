@preconcurrency import CoreImage
import Foundation

// Offline executor only: one previous small RGB image and one depth field.
// No flow/registration => current estimate, never an unregistered temporal mean.
final class VideoDepthStabilizer {
    private let motion = DepthMotionEstimator()
    private var temporal = DepthTemporalState()
    private var previous: CGImage?
    private var previousTime = -Double.infinity
    private var retry = InferenceRetryBackoff()
    private(set) var registeredFrames = 0
    private(set) var rejectedHistoryFrames = 0
    func reset() { temporal.reset(); previous = nil; previousTime = -Double.infinity }
    func update(image: CIImage, field: SoftwareDepthField, time: Double) throws -> SoftwareDepthField {
        try Task.checkCancellation()
        let scale = min(1, 160 / Double(max(field.width, field.height)))
        let w = max(3, Int(Double(field.width) * scale)), h = max(3, Int(Double(field.height) * scale))
        let current = try motion.image(image, width: w, height: h)
        let pixels = try SDRImage.rasterize(current)
        let smallLuma: [Float] = (0..<(w*h)).map { i in
            (Float(pixels.rgba[4*i]) * 0.2126 + Float(pixels.rgba[4*i+1]) * 0.7152 + Float(pixels.rgba[4*i+2]) * 0.0722) / 255
        }
        let luma: [Float] = (0..<field.inverseDepth.count).map { i in
            DepthGrid.sample(smallLuma, width: w, height: h,
                x: (Double(i % field.width) + 0.5) * Double(w) / Double(field.width) - 0.5,
                y: (Double(i / field.width) + 0.5) * Double(h) / Double(field.height) - 0.5)
        }
        var registered = false
        if let previous, previous.width == w, previous.height == h, time > previousTime,
           time - previousTime <= 0.25, retry.canAttempt(at: time) {
            do {
                let flow = try motion.backwardFlow(current: current, previous: previous)
                retry.reset()
                let xs = flow.map(\.x), ys = flow.map(\.y)
                let expanded: [SIMD2<Float>] = (0..<field.inverseDepth.count).map { i in
                    let x = (Double(i % field.width) + 0.5) * Double(w) / Double(field.width) - 0.5
                    let y = (Double(i / field.width) + 0.5) * Double(h) / Double(field.height) - 0.5
                    return SIMD2(DepthGrid.sample(xs, width: w, height: h, x: x, y: y) * Float(field.width) / Float(w),
                                 DepthGrid.sample(ys, width: w, height: h, x: x, y: y) * Float(field.height) / Float(h))
                }
                registered = temporal.alignHistory(backwardFlow: expanded, currentLuma: luma)
            } catch is CancellationError { throw CancellationError() }
            catch { retry.failed(at: time) }
        }
        if registered { registeredFrames += 1 } else { rejectedHistoryFrames += 1; temporal.reset() }
        let result = temporal.update(field, luma: luma, time: time, generation: 1, requireRegistration: true) ?? field
        previous = current; previousTime = time
        return result
    }
}
