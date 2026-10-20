import Foundation
import Metal

final class MetalPreviewDisplay {
    private let pipeline: MTLRenderPipelineState

    init(device: MTLDevice) throws {
        let library = device.makeDefaultLibrary()
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library?.makeFunction(name: "photoPPreviewVertex")
        descriptor.fragmentFunction = library?.makeFunction(name: "photoPPreviewFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
    }

    func encode(image: MTLTexture, destination: MTLTexture, command: MTLCommandBuffer) throws {
        guard destination.pixelFormat == .bgra8Unorm, destination.usage.contains(.renderTarget)
        else { throw MetalLUTError.failed("프리뷰 화면 texture 형식이 유효하지 않습니다.") }
        let inputAspect = Float(image.width) / Float(image.height)
        let outputAspect = Float(destination.width) / Float(destination.height)
        var scale = inputAspect > outputAspect ? SIMD2<Float>(1, outputAspect / inputAspect) : SIMD2<Float>(inputAspect / outputAspect, 1)
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = destination
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { throw MetalLUTError.failed("프리뷰 화면 encoder를 만들 수 없습니다.") }
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(&scale, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
        encoder.setFragmentTexture(image, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
    }
}
