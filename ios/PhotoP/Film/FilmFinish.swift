import Foundation
import Metal

struct FilmFinishSettings: Codable, Equatable, Sendable {
    var fade: Double = 0
    var vignette: Double = 0
    var bloom: Double = 0
    var halation: Double = 0
    var enabled: Bool { fade > 0 || vignette > 0 || bloom > 0 || halation > 0 }
    func validate() throws {
        guard [fade, vignette, bloom, halation].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { throw ImageEditingError.invalid("필름 마감 강도는 0~100%여야 합니다.") }
    }
}
struct ProcessingLookSettings: Codable, Equatable, Sendable {
    var intensity = 1.0
    var grain = GrainSettings()
    var finish = FilmFinishSettings()
    func validate() throws {
        guard intensity.isFinite, (0...1).contains(intensity) else { throw CameraError.invalidSettings }
        try grain.validate(); try finish.validate()
    }
}

// Small creative finishing pass; not a measured emulsion/optics simulation.
// Eight highlight taps at a normalized image radius, identical for both paths.
final class FilmFinishEncoder {
    private struct Parameters { var values: SIMD4<Float>; var size: SIMD2<UInt32>; var padding = SIMD2<UInt32>(repeating: 0) }
    private let bufferPipeline: MTLComputePipelineState
    private let texturePipeline: MTLComputePipelineState
    init(device: MTLDevice) throws {
        bufferPipeline = try MetalPipelineCache.shared.compute("photoPFilmBuffer", device: device)
        texturePipeline = try MetalPipelineCache.shared.compute("photoPFilmTexture", device: device)
    }
    private func parameters(_ settings: FilmFinishSettings, width: Int, height: Int) throws -> Parameters {
        try settings.validate()
        return Parameters(values: .init(Float(settings.fade), Float(settings.vignette), Float(settings.bloom), Float(settings.halation)),
                          size: .init(UInt32(width), UInt32(height)))
    }
    func encode(source: MTLBuffer, destination: MTLBuffer, width: Int, height: Int, settings: FilmFinishSettings, command: MTLCommandBuffer) throws {
        var p = try parameters(settings, width: width, height: height)
        guard let encoder = command.makeComputeCommandEncoder() else { throw MetalLUTError.unavailable }
        encoder.setComputePipelineState(bufferPipeline)
        encoder.setBuffer(source, offset: 0, index: 0); encoder.setBuffer(destination, offset: 0, index: 1)
        encoder.setBytes(&p, length: MemoryLayout<Parameters>.stride, index: 2)
        encoder.dispatchThreads(.init(width: width * height, height: 1, depth: 1), threadsPerThreadgroup: .init(width: bufferPipeline.threadExecutionWidth, height: 1, depth: 1))
        encoder.endEncoding()
    }
    func encode(source: MTLTexture, destination: MTLTexture, settings: FilmFinishSettings, command: MTLCommandBuffer) throws {
        var p = try parameters(settings, width: source.width, height: source.height)
        guard let encoder = command.makeComputeCommandEncoder() else { throw MetalLUTError.unavailable }
        encoder.setComputePipelineState(texturePipeline)
        encoder.setTexture(source, index: 0); encoder.setTexture(destination, index: 1)
        encoder.setBytes(&p, length: MemoryLayout<Parameters>.stride, index: 0)
        let w = texturePipeline.threadExecutionWidth
        encoder.dispatchThreads(.init(width: source.width, height: source.height, depth: 1), threadsPerThreadgroup: .init(width: w, height: 4, depth: 1))
        encoder.endEncoding()
    }
}
