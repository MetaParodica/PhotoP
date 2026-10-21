import Foundation
import Metal

// Owned by the live frame queue. Encodes work without CPU readback or GPU waits.
final class MetalLUTTextureRenderer {
    let device: MTLDevice
    private let pipeline: MTLComputePipelineState
    private let resources: MetalLUTResources

    init(lut: CubeLUT, device: MTLDevice) throws {
        guard let function = device.makeDefaultLibrary()?.makeFunction(name: "photoPLUTTexture")
        else { throw MetalLUTError.failed("Metal texture LUT 셰이더를 찾을 수 없습니다.") }
        self.device = device
        resources = try MetalLUTResources(lut: lut, device: device)
        pipeline = try device.makeComputePipelineState(function: function)
    }

    func encode(source: MTLTexture, destination: MTLTexture, intensity: Double, grain: GrainSettings = GrainSettings(), command: MTLCommandBuffer) throws {
        let supported: Set<MTLPixelFormat> = [.rgba8Unorm, .bgra8Unorm]
        guard source !== destination, source.textureType == .type2D, destination.textureType == .type2D,
              source.sampleCount == 1, destination.sampleCount == 1,
              source.width == destination.width, source.height == destination.height,
              source.width <= MetalLUTRenderer.maximumPixels, source.height <= MetalLUTRenderer.maximumPixels / source.width,
              supported.contains(source.pixelFormat), supported.contains(destination.pixelFormat),
              source.usage.contains(.shaderRead), destination.usage.contains(.shaderWrite),
              source.device.registryID == device.registryID, destination.device.registryID == device.registryID,
              command.commandQueue.device.registryID == device.registryID, command.status == .notEnqueued
        else { throw MetalLUTError.failed("LUT texture 형식·크기·GPU 작업이 유효하지 않습니다.") }
        var parameters = try resources.parameters(intensity: intensity, pixelCount: source.width * source.height, width: source.width, height: source.height, grain: grain)
        guard let encoder = command.makeComputeCommandEncoder() else { throw MetalLUTError.failed("LUT encoder를 만들 수 없습니다.") }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(source, index: 0)
        encoder.setTexture(destination, index: 1)
        encoder.setBuffer(resources.table, offset: 0, index: 0)
        encoder.setBytes(&parameters, length: MemoryLayout<MetalLUTResources.Parameters>.stride, index: 1)
        let w = pipeline.threadExecutionWidth
        let h = max(1, min(8, pipeline.maxTotalThreadsPerThreadgroup / w))
        encoder.dispatchThreads(MTLSize(width: source.width, height: source.height, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: w, height: h, depth: 1))
        encoder.endEncoding()
    }
}
