@preconcurrency import CoreImage
@preconcurrency import Metal
@preconcurrency import MetalPerformanceShaders
import Foundation

// Capture/export executor ONLY. Never used by live preview. GPU work and one
// bounded readback happen once; the derived field is saved for all re-edits.
final class NativeDepthRefiner {
    private let context = CIContext(options: [.cacheIntermediates: false,
        .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!])

    func refine(_ field: SoftwareDepthField, color: CIImage) throws -> SoftwareDepthField {
        guard field.nativeMetadata != nil, field.nativeMetadata?.refinement == nil,
              field.bounds != nil,
              let size = DepthRefinementPolicy.outputSize(colorWidth: Int(color.extent.width), colorHeight: Int(color.extent.height),
                  depthWidth: field.width, depthHeight: field.height),
              let device = MTLCreateSystemDefaultDevice(), MPSSupportsMTLDevice(device) else { return field }
        let trace = ProcessingTrace.begin("Native guided depth refinement")
        defer { ProcessingTrace.end("Native guided depth refinement", trace); context.clearCaches() }
        try Task.checkCancellation()
        let valid = field.inverseDepth.filter { $0 > 0 }
        guard let lo = valid.min(), let hi = valid.max(), hi > lo,
              let queue = device.makeCommandQueue(), let command = queue.makeCommandBuffer() else { return field }
        let range = hi-lo
        guard range.isFinite else { throw CameraError.invalidPhotoData }
        func texture(_ width: Int, _ height: Int, _ format: MTLPixelFormat, shared: Bool = false) throws -> MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height, mipmapped: false)
            d.storageMode = shared ? .shared : .private
            d.usage = [.shaderRead, .shaderWrite, .renderTarget]
            guard let t = device.makeTexture(descriptor: d) else { throw CameraError.configuration }
            return t
        }
        let source = try texture(field.width, field.height, .r32Float, shared: true)
        let weights = try texture(field.width, field.height, .r32Float, shared: true)
        let lowGuide = try texture(field.width, field.height, .rgba16Float)
        let highGuide = try texture(size.width, size.height, .rgba16Float)
        let coefficients = try texture(field.width, field.height, .rgba32Float, shared: true)
        let output = try texture(size.width, size.height, .r32Float, shared: true)
        let normalized = field.inverseDepth.map { $0 > 0 ? ($0-lo)/range : 0 }
        let validity = field.inverseDepth.map { $0 > 0 ? Float(1) : 0 }
        normalized.withUnsafeBytes { source.replace(region: .init(origin: .init(x: 0, y: 0, z: 0), size: .init(width: field.width, height: field.height, depth: 1)),
            mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: field.width*4) }
        validity.withUnsafeBytes { weights.replace(region: .init(origin: .init(x: 0, y: 0, z: 0), size: .init(width: field.width, height: field.height, depth: 1)),
            mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: field.width*4) }
        let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
        func guide(_ t: MTLTexture) {
            let scaled = color.transformed(by: CGAffineTransform(scaleX: CGFloat(t.width)/color.extent.width, y: CGFloat(t.height)/color.extent.height))
            // CI is bottom-left; uploaded field/Metal readback rows are top-left.
            let topDown = scaled.transformed(by: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: CGFloat(t.height)))
            context.render(topDown, to: t, commandBuffer: command,
                bounds: CGRect(x: 0, y: 0, width: t.width, height: t.height), colorSpace: space)
        }
        command.label = "PhotoP native guided depth"
        guide(lowGuide); guide(highGuide)
        let filter = MPSImageGuidedFilter(device: device, kernelDiameter: 5)
        filter.epsilon = 0.0001
        filter.encodeRegression(to: command, sourceTexture: source, guidanceTexture: lowGuide,
            weightsTexture: weights, destinationCoefficientsTexture: coefficients)
        filter.encodeReconstruction(to: command, guidanceTexture: highGuide, coefficientsTexture: coefficients, destinationTexture: output)
        command.commit(); command.waitUntilCompleted()
        guard command.status == .completed else { throw command.error ?? CameraError.configuration }
        try Task.checkCancellation()
        // Coefficients A describe the learned RGB/depth relationship. Uniform
        // guidance has A~=0 and must not turn a depth jump into an average.
        // This is structural evidence, not a sensor confidence/probability.
        var coefficientValues = [Float](repeating: 0,count: field.width*field.height*4)
        coefficientValues.withUnsafeMutableBytes { coefficients.getBytes($0.baseAddress!,bytesPerRow: field.width*16,
            from: .init(origin: .init(x: 0,y: 0,z: 0),size: .init(width: field.width,height: field.height,depth: 1)),mipmapLevel: 0) }
        let evidence: [UInt8] = (0..<(field.width*field.height)).map { i in
            let r = coefficientValues[i*4], g = coefficientValues[i*4+1], b = coefficientValues[i*4+2]
            return r.isFinite && g.isFinite && b.isFinite && abs(r)+abs(g)+abs(b) > 0.05 ? 1 : 0
        }
        var values = [Float](repeating: 0, count: size.width*size.height)
        values.withUnsafeMutableBytes { output.getBytes($0.baseAddress!, bytesPerRow: size.width*4,
            from: .init(origin: .init(x: 0, y: 0, z: 0), size: .init(width: size.width, height: size.height, depth: 1)), mipmapLevel: 0) }
        for i in values.indices { values[i] = values[i]*range+lo }
        guard let refined = DepthRefinementPolicy.constrained(base: field, candidate: values, width: size.width, height: size.height,guideEvidence: evidence,
            isCancelled: { Task.isCancelled }) else {
            try Task.checkCancellation(); throw CameraError.invalidPhotoData
        }
        return refined
    }
}
