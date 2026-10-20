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
    private let table: MTLBuffer
    private let lut: CubeLUT
    private var sourceBuffer: MTLBuffer?
    private var destinationBuffer: MTLBuffer?

    private struct Parameters {
        var minimum: SIMD4<Float>
        var maximum: SIMD4<Float>
        var dimension: UInt32
        var intensity: Float
        var pixelCount: UInt32
        var padding: UInt32 = 0
    }

    init(lut: CubeLUT) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue()
        else { throw MetalLUTError.unavailable }
        guard let function = device.makeDefaultLibrary()?.makeFunction(name: "photoPLUT")
        else { throw MetalLUTError.failed("Metal LUT 셰이더를 찾을 수 없습니다.") }
        for channel in 0..<3 {
            let width = Float(lut.domainMax[channel]) - Float(lut.domainMin[channel])
            guard width.isFinite, width > 0 else { throw MetalLUTError.failed("GPU에서 표현할 수 없는 LUT 입력 범위입니다.") }
        }
        // Keep interpolation differences and weighted sums representable in Float.
        let safeMagnitude = Double(Float.greatestFiniteMagnitude) / 4
        guard lut.values.allSatisfy({ value in (0..<3).allSatisfy { abs(value[$0]) <= safeMagnitude } })
        else { throw MetalLUTError.failed("GPU 보간에서 안정적으로 표현할 수 없는 LUT 출력값입니다.") }
        let values = lut.values.map { SIMD4<Float>(Float($0.x), Float($0.y), Float($0.z), 0) }
        guard let table = values.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) })
        else { throw MetalLUTError.failed("LUT 메모리를 확보할 수 없습니다.") }
        self.device = device
        self.queue = queue
        self.pipeline = try device.makeComputePipelineState(function: function)
        self.table = table
        self.lut = lut
    }

    func render(_ rgba: Data, width: Int, height: Int, intensity: Double) throws -> Data {
        guard width > 0, height > 0, width <= Self.maximumPixels,
              height <= Self.maximumPixels / width, intensity.isFinite, (0...1).contains(intensity)
        else { throw MetalLUTError.failed("SDR 처리는 최대 12.6MP이며 크기와 강도가 유효해야 합니다.") }
        let count = width * height
        let byteCount = count * 4
        guard rgba.count == byteCount else { throw MetalLUTError.failed("RGBA 데이터 크기가 이미지와 다릅니다.") }
        // Preserve exact source bytes at strength zero, including transparent pixels.
        if intensity == 0 { return rgba }
        if sourceBuffer?.length != byteCount || destinationBuffer?.length != byteCount {
            sourceBuffer = device.makeBuffer(length: byteCount, options: .storageModeShared)
            destinationBuffer = device.makeBuffer(length: byteCount, options: .storageModeShared)
        }
        guard let sourceBuffer, let destinationBuffer,
              let command = queue.makeCommandBuffer(), let encoder = command.makeComputeCommandEncoder()
        else { throw MetalLUTError.failed("GPU 작업 메모리를 확보할 수 없습니다.") }
        rgba.withUnsafeBytes { sourceBuffer.contents().copyMemory(from: $0.baseAddress!, byteCount: byteCount) }
        var parameters = Parameters(minimum: SIMD4(Float(lut.domainMin.x), Float(lut.domainMin.y), Float(lut.domainMin.z), 0),
                                    maximum: SIMD4(Float(lut.domainMax.x), Float(lut.domainMax.y), Float(lut.domainMax.z), 0),
                                    dimension: UInt32(lut.dimension), intensity: Float(intensity), pixelCount: UInt32(count))
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(sourceBuffer, offset: 0, index: 0)
        encoder.setBuffer(destinationBuffer, offset: 0, index: 1)
        encoder.setBuffer(table, offset: 0, index: 2)
        encoder.setBytes(&parameters, length: MemoryLayout<Parameters>.stride, index: 3)
        let group = min(pipeline.threadExecutionWidth, pipeline.maxTotalThreadsPerThreadgroup)
        encoder.dispatchThreads(MTLSize(width: count, height: 1, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: group, height: 1, depth: 1))
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else { throw MetalLUTError.failed(command.error?.localizedDescription ?? "GPU LUT 처리가 실패했습니다.") }
        return Data(bytes: destinationBuffer.contents(), count: byteCount)
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
