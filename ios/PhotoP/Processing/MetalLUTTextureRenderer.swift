import Foundation
import Metal

// Owned by the live frame queue. Encodes work without CPU readback or GPU waits.
final class MetalLUTTextureRenderer {
    let device: MTLDevice
    private let pipeline: MTLComputePipelineState
    private let finish: FilmFinishEncoder
    private var finishScratch: MTLTexture?
    private let resources: MetalLUTResources

    init(lut: CubeLUT, device: MTLDevice) throws {
        self.device = device
        finish = try FilmFinishEncoder(device: device)
        resources = try MetalLUTResources(lut: lut, device: device)
        pipeline = try MetalPipelineCache.shared.compute("photoPLUTTexture", device: device)
    }

    func encode(source: MTLTexture, destination: MTLTexture, intensity: Double, grain: GrainSettings = GrainSettings(), effects: FilmFinishSettings = FilmFinishSettings(), command: MTLCommandBuffer) throws {
        try effects.validate()
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
        let lutOutput: MTLTexture
        if effects.enabled {
            if finishScratch?.width != source.width || finishScratch?.height != source.height || finishScratch?.pixelFormat != destination.pixelFormat {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: destination.pixelFormat, width: source.width, height: source.height, mipmapped: false)
                descriptor.storageMode = .private; descriptor.usage = [.shaderRead, .shaderWrite]
                finishScratch = device.makeTexture(descriptor: descriptor)
            }
            guard let scratch = finishScratch else { throw MetalLUTError.unavailable }; lutOutput = scratch
        } else { finishScratch = nil; lutOutput = destination }
        var parameters = try resources.parameters(intensity: intensity, pixelCount: source.width * source.height, width: source.width, height: source.height, grain: grain)
        guard let encoder = command.makeComputeCommandEncoder() else { throw MetalLUTError.failed("LUT encoder를 만들 수 없습니다.") }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(source, index: 0)
        encoder.setTexture(lutOutput, index: 1)
        encoder.setBuffer(resources.table, offset: 0, index: 0)
        encoder.setBytes(&parameters, length: MemoryLayout<MetalLUTResources.Parameters>.stride, index: 1)
        let w = pipeline.threadExecutionWidth
        let h = max(1, min(8, pipeline.maxTotalThreadsPerThreadgroup / w))
        encoder.dispatchThreads(MTLSize(width: source.width, height: source.height, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: w, height: h, depth: 1))
        encoder.endEncoding()
        if effects.enabled { try finish.encode(source: lutOutput, destination: destination, settings: effects, command: command) }
    }
}
