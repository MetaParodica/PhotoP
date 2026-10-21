import Foundation
import Metal

// SDR, encoded sRGB, premultiplied RGBA8. Color conversion belongs to the caller.
// Actor isolation keeps buffer reuse and GPU waits away from the main actor.
actor MetalLUTRenderer {
    // Includes nominal 12MP iPhone photos (4032 × 3024 = 12,192,768 pixels).
    static let maximumPixels = 12_600_000
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState
    private let finish: FilmFinishEncoder
    private let resources: MetalLUTResources
    private var sourceBuffer: MTLBuffer?
    private var destinationBuffer: MTLBuffer?

    init(lut: CubeLUT) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue()
        else { throw MetalLUTError.unavailable }
        guard let function = device.makeDefaultLibrary()?.makeFunction(name: "photoPLUT")
        else { throw MetalLUTError.failed("Metal LUT 셰이더를 찾을 수 없습니다.") }
        self.device = device
        self.queue = queue
        self.pipeline = try device.makeComputePipelineState(function: function)
        self.finish = try FilmFinishEncoder(device: device)
        self.resources = try MetalLUTResources(lut: lut, device: device)
    }

    func render(_ rgba: Data, width: Int, height: Int, intensity: Double, grain: GrainSettings = GrainSettings(), effects: FilmFinishSettings = FilmFinishSettings()) throws -> Data {
        try grain.validate()
        try effects.validate()
        guard width > 0, height > 0, width <= Self.maximumPixels,
              height <= Self.maximumPixels / width, intensity.isFinite, (0...1).contains(intensity)
        else { throw MetalLUTError.failed("SDR 처리는 최대 12.6MP이며 크기와 강도가 유효해야 합니다.") }
        let count = width * height
        let byteCount = count * 4
        guard rgba.count == byteCount else { throw MetalLUTError.failed("RGBA 데이터 크기가 이미지와 다릅니다.") }
        // Preserve exact source bytes at strength zero, including transparent pixels.
        if intensity == 0 && grain.amount == 0 && !effects.enabled { return rgba }
        if sourceBuffer?.length != byteCount || destinationBuffer?.length != byteCount {
            sourceBuffer = device.makeBuffer(length: byteCount, options: .storageModeShared)
            destinationBuffer = device.makeBuffer(length: byteCount, options: .storageModeShared)
        }
        guard let sourceBuffer, let destinationBuffer,
              let command = queue.makeCommandBuffer(), let encoder = command.makeComputeCommandEncoder()
        else { throw MetalLUTError.failed("GPU 작업 메모리를 확보할 수 없습니다.") }
        rgba.withUnsafeBytes { sourceBuffer.contents().copyMemory(from: $0.baseAddress!, byteCount: byteCount) }
        var parameters = try resources.parameters(intensity: intensity, pixelCount: count, width: width, height: height, grain: grain)
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(sourceBuffer, offset: 0, index: 0)
        encoder.setBuffer(destinationBuffer, offset: 0, index: 1)
        encoder.setBuffer(resources.table, offset: 0, index: 2)
        encoder.setBytes(&parameters, length: MemoryLayout<MetalLUTResources.Parameters>.stride, index: 3)
        let group = min(pipeline.threadExecutionWidth, pipeline.maxTotalThreadsPerThreadgroup)
        encoder.dispatchThreads(MTLSize(width: count, height: 1, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: group, height: 1, depth: 1))
        encoder.endEncoding()
        if effects.enabled { try finish.encode(source: destinationBuffer, destination: sourceBuffer, width: width, height: height, settings: effects, command: command) }
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else { throw MetalLUTError.failed(command.error?.localizedDescription ?? "GPU LUT 처리가 실패했습니다.") }
        return Data(bytes: (effects.enabled ? sourceBuffer : destinationBuffer).contents(), count: byteCount)
    }
}

enum MetalLUTError: LocalizedError {
    case unavailable
    case failed(String)
    var errorDescription: String? {
        switch self {
        case .unavailable: return "이 환경에서는 Metal을 사용할 수 없습니다."
        case .failed(let reason): return reason
        }
    }
}
