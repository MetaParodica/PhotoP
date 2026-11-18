import Foundation
import Metal

struct MonitoringSettings: Equatable, Sendable {
    var histogram = false
    var zebra = false
    var peaking = false
    var waveform = false
    var rgbParade = false
    var vectorscope = false
    var falseColor = false
    var zebraThreshold: Double = 0.95
    var peakingThreshold: Double = 0.2
    var needsStatistics: Bool { histogram || waveform || rgbParade || vectorscope }
    var enabled: Bool { needsStatistics || zebra || peaking || falseColor }
    mutating func disableStatistics() { histogram = false; waveform = false; rgbParade = false; vectorscope = false }
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
    var scopes: PreviewScopeSamples? = nil
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
    private var sampled = MonitoringSettings()
    private var overlay: MTLTexture?
    init(device: MTLDevice) throws {
        guard let function = device.makeDefaultLibrary()?.makeFunction(name: "photoPMonitor"),
              let counts = device.makeBuffer(length: ScopeAnalysisPolicy.count * 4, options: .storageModeShared)
        else { throw MetalLUTError.unavailable }
        self.device = device; self.counts = counts
        counts.contents().initializeMemory(as: UInt8.self, repeating: 0, count: counts.length)
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
        if settings.needsStatistics {
            guard let blit = command.makeBlitCommandEncoder() else { throw MetalLUTError.unavailable }
            blit.fill(buffer: counts, range: 0..<counts.length, value: 0)
            blit.endEncoding()
        }
        sampled = settings
        var flags: UInt32 = 0
        if settings.histogram { flags |= 1 }; if settings.zebra { flags |= 2 }; if settings.peaking { flags |= 4 }
        if settings.waveform { flags |= 8 }; if settings.rgbParade { flags |= 16 }; if settings.vectorscope { flags |= 32 }
        if settings.falseColor { flags |= 64 }
        var p = Parameters(flags: flags,
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
        let pointer = counts.contents().bindMemory(to: UInt32.self, capacity: ScopeAnalysisPolicy.count)
        func read(_ offset: Int, _ count: Int) -> [UInt32] { Array(UnsafeBufferPointer(start: pointer + offset, count: count)) }
        return PreviewHistogram(bins: (0..<4).map { read($0 * 64, 64) }, scopes: .init(
            waveform: sampled.waveform ? read(ScopeAnalysisPolicy.waveformOffset, 4096) : nil,
            parade: sampled.rgbParade ? read(ScopeAnalysisPolicy.paradeOffset, 12288) : nil,
            vectorscope: sampled.vectorscope ? read(ScopeAnalysisPolicy.vectorscopeOffset, 4096) : nil))
    }
}
