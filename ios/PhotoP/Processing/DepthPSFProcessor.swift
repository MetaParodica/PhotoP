@preconcurrency import CoreImage
@preconcurrency import Metal
import Foundation

// CI supplies linear, premultiplied textures and owns the command-buffer lifetime.
// No synchronous readback, full-resolution intermediate, or per-pixel CPU loop.
final class DepthPSFProcessor: CIImageProcessorKernel {
    private final class Pipelines: @unchecked Sendable {
        let lock = NSLock()
        var values: [UInt64: MTLComputePipelineState] = [:]
        func pipeline(_ device: MTLDevice) throws -> MTLComputePipelineState {
            lock.lock(); defer { lock.unlock() }
            if let value = values[device.registryID] { return value }
            guard let function = device.makeDefaultLibrary()?.makeFunction(name: "photopDepthPSF") else { throw CameraError.configuration }
            let value = try device.makeComputePipelineState(function: function)
            if values.count >= 4 { values.removeAll() }
            values[device.registryID] = value
            return value
        }
    }
    private static let pipelines = Pipelines()
    override class var outputFormat: CIFormat { .RGBAh }
    override class func formatForInput(at input: Int32) -> CIFormat { .RGBAh }
    override class func roi(forInput input: Int32, arguments: [String: Any]?, outputRect: CGRect) -> CGRect {
        outputRect.insetBy(dx: -ceil(arguments?["radius"] as? Double ?? 0) - 2,
                           dy: -ceil(arguments?["radius"] as? Double ?? 0) - 2)
    }
    override class func process(with inputs: [CIImageProcessorInput]?, arguments: [String: Any]?, output: CIImageProcessorOutput) throws {
        guard let input = inputs?.first, let source = input.metalTexture, let destination = output.metalTexture,
              let command = output.metalCommandBuffer, let encoder = command.makeComputeCommandEncoder(),
              let radius = arguments?["radius"] as? Double, let catEye = arguments?["catEye"] as? Double,
              let extent = (arguments?["extent"] as? CIVector)?.cgRectValue,
              var taps = arguments?["taps"] as? [SIMD4<Float>], (9...49).contains(taps.count) else { throw CameraError.configuration }
        defer { encoder.endEncoding() }
        let state = try pipelines.pipeline(destination.device)
        var parameters = [
            SIMD4<Float>(Float(input.region.minX), Float(input.region.minY), Float(output.region.minX), Float(output.region.minY)),
            SIMD4<Float>(Float(extent.midX), Float(extent.midY), Float(max(extent.width, extent.height)), Float(radius)),
            SIMD4<Float>(Float(catEye), Float(taps.count), 0, 0)]
        encoder.setComputePipelineState(state)
        encoder.setTexture(source, index: 0); encoder.setTexture(destination, index: 1)
        encoder.setBytes(&parameters, length: parameters.count * MemoryLayout<SIMD4<Float>>.stride, index: 0)
        encoder.setBytes(&taps, length: taps.count * MemoryLayout<SIMD4<Float>>.stride, index: 1)
        let w = state.threadExecutionWidth, h = max(1, min(8, state.maxTotalThreadsPerThreadgroup / w))
        encoder.dispatchThreads(MTLSize(width: destination.width, height: destination.height, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: w, height: h, depth: 1))
    }
}
