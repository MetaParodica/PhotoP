import Foundation
import Metal

// Shared CPU/Metal ABI and table validation for still and live texture paths.
struct MetalLUTResources {
    struct Parameters {
        var minimum: SIMD4<Float>
        var maximum: SIMD4<Float>
        var dimension: UInt32
        var intensity: Float
        var pixelCount: UInt32
        var padding: UInt32 = 0
        var width: UInt32 = 1
        var height: UInt32 = 1
        var grainAmount: Float = 0
        var grainSeed: UInt32 = 1
    }
    let lut: CubeLUT
    let table: MTLBuffer

    init(lut: CubeLUT, device: MTLDevice) throws {
        for channel in 0..<3 {
            let width = Float(lut.domainMax[channel]) - Float(lut.domainMin[channel])
            guard width.isFinite, width > 0 else { throw MetalLUTError.failed("GPU에서 표현할 수 없는 LUT 입력 범위입니다.") }
        }
        let safeMagnitude = Double(Float.greatestFiniteMagnitude) / 4
        guard lut.values.allSatisfy({ value in (0..<3).allSatisfy { abs(value[$0]) <= safeMagnitude } })
        else { throw MetalLUTError.failed("GPU 보간에서 안정적으로 표현할 수 없는 LUT 출력값입니다.") }
        let values = lut.values.map { SIMD4<Float>(Float($0.x), Float($0.y), Float($0.z), 0) }
        guard let table = values.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) })
        else { throw MetalLUTError.failed("LUT 메모리를 확보할 수 없습니다.") }
        self.lut = lut
        self.table = table
    }

    func parameters(intensity: Double, pixelCount: Int, width: Int = 1, height: Int = 1, grain: GrainSettings = GrainSettings()) throws -> Parameters {
        try grain.validate()
        guard intensity.isFinite, (0...1).contains(intensity), pixelCount > 0,
              pixelCount <= MetalLUTRenderer.maximumPixels else { throw MetalLUTError.failed("LUT 크기와 강도가 유효하지 않습니다.") }
        return Parameters(minimum: SIMD4(Float(lut.domainMin.x), Float(lut.domainMin.y), Float(lut.domainMin.z), 0),
                          maximum: SIMD4(Float(lut.domainMax.x), Float(lut.domainMax.y), Float(lut.domainMax.z), 0),
                          dimension: UInt32(lut.dimension), intensity: Float(intensity), pixelCount: UInt32(pixelCount), width: UInt32(width), height: UInt32(height),
                          grainAmount: Float(grain.amount), grainSeed: grain.seed)
    }
}
