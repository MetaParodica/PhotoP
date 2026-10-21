import Foundation
import Metal

struct MonitoringSettings: Equatable, Sendable {
    var histogram = false
    var zebra = false
    var peaking = false
    var zebraThreshold: Double = 0.95
    var peakingThreshold: Double = 0.2
    var enabled: Bool { histogram || zebra || peaking }
    func validate() throws {
        guard zebraThreshold.isFinite, (0.5...1).contains(zebraThreshold),
              peakingThreshold.isFinite, (0.01...1).contains(peakingThreshold) else {
            throw ImageEditingError.invalid("모니터 임계값이 유효하지 않습니다.")
        }
    }
}

struct PreviewHistogram: Sendable {
    // 64 bins each, in R/G/B/encoded-luma order; zero-alpha samples omitted.
    let bins: [[UInt32]]
    var sampleCount: UInt32 { bins.first?.reduce(0, +) ?? 0 }
}

// Owned by the frame queue. Histogram is read only after GPU completion and
// before releasing the single in-flight ticket. No image pixels leave the GPU.
final class MetalPreviewMonitor {
    private struct Parameters {
        var flags: UInt32
        var step: UInt32
        var zebra: Float
        var peaking: Float
    }
    private let device: MTLDevice
    private let pipeline: MTLComputePipelineState
    private let counts: MTLBuffer
    private var overlay: MTLTexture?
    init(device: MTLDevice) throws {
        guard let function = device.makeDefaultLibrary()?.makeFunction(name: "photoPMonitor"),
              let counts = device.makeBuffer(length: 4 * 64 * 4, options: .storageModeShared)
        else { throw MetalLUTError.unavailable }
        self.device = device; self.counts = counts
        pipeline = try device.makeComputePipelineState(function: function)
    }
    func encode(source: MTLTexture, graded: MTLTexture, settings: MonitoringSettings,
                command: MTLCommandBuffer) throws -> MTLTexture {
        try settings.validate()
        guard source.textureType == .type2D, graded.textureType == .type2D,
              source.pixelFormat == .rgba8Unorm, graded.pixelFormat == .rgba8Unorm,
              source.width <= 1024, source.height <= 1024,
              source.width == graded.width, source.height == graded.height,
              source.sampleCount == 1, graded.sampleCount == 1,
              source.usage.contains(.shaderRead), graded.usage.contains(.shaderRead),
              source.device.registryID == device.registryID, graded.device.registryID == device.registryID,
              command.commandQueue.device.registryID == device.registryID, command.status == .notEnqueued
        else { throw ImageEditingError.invalid("모니터 입력 texture가 유효하지 않습니다.") }
        if !settings.enabled { return graded }
        if overlay?.width != source.width || overlay?.height != source.height {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: source.width, height: source.height, mipmapped: false)
            descriptor.storageMode = .private; descriptor.usage = [.shaderRead, .shaderWrite]
            overlay = device.makeTexture(descriptor: descriptor)
        }
        guard let overlay else { throw MetalLUTError.unavailable }
        if settings.histogram {
            guard let blit = command.makeBlitCommandEncoder() else { throw MetalLUTError.unavailable }
            blit.fill(buffer: counts, range: 0..<counts.length, value: 0)
            blit.endEncoding()
        }
        var p = Parameters(flags: (settings.histogram ? 1 : 0) | (settings.zebra ? 2 : 0) | (settings.peaking ? 4 : 0),
                           step: UInt32(max(1, (max(source.width, source.height) + 255) / 256)),
                           zebra: Float(settings.zebraThreshold), peaking: Float(settings.peakingThreshold))
        guard let encoder = command.makeComputeCommandEncoder() else { throw MetalLUTError.unavailable }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(source, index: 0); encoder.setTexture(graded, index: 1); encoder.setTexture(overlay, index: 2)
        encoder.setBuffer(counts, offset: 0, index: 0)
        encoder.setBytes(&p, length: MemoryLayout<Parameters>.stride, index: 1)
        let w = pipeline.threadExecutionWidth
        encoder.dispatchThreads(MTLSize(width: source.width, height: source.height, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: w, height: max(1, min(8, pipeline.maxTotalThreadsPerThreadgroup / w)), depth: 1))
        encoder.endEncoding()
        return overlay
    }
    func histogram() -> PreviewHistogram {
        let pointer = counts.contents().bindMemory(to: UInt32.self, capacity: 256)
        return PreviewHistogram(bins: (0..<4).map { Array(UnsafeBufferPointer(start: pointer + $0 * 64, count: 64)) })
    }
}
