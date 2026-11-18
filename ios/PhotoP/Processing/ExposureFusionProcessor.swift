import Foundation
import Metal

struct ExposureFusionManifest: Codable {
    struct Frame: Codable { let filename: String; let sha256: String; let requestedEV: Double }
    let version: Int
    let frames: [Frame]
    let registrations: [ExposureFusionRegistration]
    let weights: ExposureFusionWeights
    let policy: ExposureFusionPolicy?
    let width: Int
    let height: Int
    let analysisWidth: Int
    let analysisHeight: Int
    let contract: String
}

actor ExposureFusionProcessor {
    static let shared = ExposureFusionProcessor()
    private struct Parameters {
        var width: UInt32, height: UInt32
        var x0: Int32, y0: Int32, x2: Int32, y2: Int32
        var contrast: Float, saturation: Float, exposure: Float
    }
    func fuse(originals: [URL], biases: [Double], documents: URL? = nil,
              policy: ExposureFusionPolicy = ExposureFusionPolicy()) throws -> URL {
        try policy.validateBiases(biases)
        guard originals.count == 3, Set(originals.map(\.standardizedFileURL)).count == 3 else { throw ExposureFusionFailure.invalidInput }
        for url in originals {
            let info = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard info.isRegularFile == true, info.isSymbolicLink != true,
                  let size = info.fileSize, (1...268_435_456).contains(size),
                  ["jpg", "jpeg", "heic"].contains(url.pathExtension.lowercased()) else { throw ExposureFusionFailure.invalidInput }
        }
        try Task.checkCancellation()
        let hashes = try originals.map { try LUTPhotoEditor.hashFile($0) }
        let previews = try originals.map { try SDRImage.decode($0, previewMaxDimension: 192) }
        let w = previews[1].width, h = previews[1].height
        guard previews.allSatisfy({ $0.width == w && $0.height == h }) else { throw ExposureFusionFailure.invalidInput }
        let lumas: [[Float]] = previews.map { image in
            let bytes = [UInt8](image.rgba)
            var result = [Float](); result.reserveCapacity(w * h)
            for i in 0..<(w * h) {
                let r = Float(bytes[i * 4]), g = Float(bytes[i * 4 + 1]), b = Float(bytes[i * 4 + 2])
                result.append((r * 54.0 + g * 183.0 + b * 19.0) / 65_280.0)
            }
            return result
        }
        let registrations = try [policy.register(reference: lumas[1], candidate: lumas[0], width: w, height: h),
                                 .reference, policy.register(reference: lumas[1], candidate: lumas[2], width: w, height: h)]
        try Task.checkCancellation()
        let pixels = try render(originals: originals, registrations: registrations, analysisWidth: w, analysisHeight: h, weights: policy.weights)
        let root = try documents ?? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = root.appendingPathComponent("FusionResults")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let id = UUID().uuidString
        let final = folder.appendingPathComponent(id)
        let pending = folder.appendingPathComponent(".pending-" + id)
        try FileManager.default.createDirectory(at: pending, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: pending) }
        try Task.checkCancellation()
        let options: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        try pixels.jpeg().write(to: pending.appendingPathComponent("photo.jpg"), options: options)
        let manifest = ExposureFusionManifest(version: 1, frames: originals.indices.map {
            .init(filename: originals[$0].lastPathComponent, sha256: hashes[$0], requestedEV: biases[$0])
        }, registrations: registrations, weights: policy.weights, policy: policy, width: pixels.width, height: pixels.height,
            analysisWidth: w, analysisHeight: h,
            contract: "SDR encoded-sRGB; translation-only; smoothed quality weights, single scale; center-only uncovered borders; no HDR/gain map/LUT; originals preserved")
        try JSONEncoder().encode(manifest).write(to: pending.appendingPathComponent("recipe.json"), options: options)
        guard try originals.map({ try LUTPhotoEditor.hashFile($0) }) == hashes else { throw ExposureFusionFailure.originalsChanged }
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: pending, to: final)
        return final.appendingPathComponent("photo.jpg")
    }
    private func render(originals: [URL], registrations: [ExposureFusionRegistration], analysisWidth: Int, analysisHeight: Int,
                        weights: ExposureFusionWeights) throws -> SDRImage {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { throw MetalLUTError.unavailable }
        let pipeline = try MetalPipelineCache.shared.compute("photoPExposureFusion", device: device)
        var buffers: [MTLBuffer] = [], width = 0, height = 0
        for url in originals {
            try Task.checkCancellation()
            let buffer = try autoreleasepool { () throws -> MTLBuffer in
                let pixels = try SDRImage.decode(url)
                if width == 0 { width = pixels.width; height = pixels.height }
                guard width == pixels.width, height == pixels.height,
                      let buffer = pixels.rgba.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: pixels.rgba.count, options: .storageModeShared) })
                else { throw ExposureFusionFailure.invalidInput }
                return buffer
            }
            buffers.append(buffer)
        }
        guard let output = device.makeBuffer(length: width * height * 4, options: .storageModeShared),
              let command = queue.makeCommandBuffer(), let encoder = command.makeComputeCommandEncoder() else { throw MetalLUTError.unavailable }
        func shift(_ value: Int, _ full: Int, _ small: Int) -> Int32 { Int32((Double(value) * Double(full) / Double(small)).rounded()) }
        var p = Parameters(width: UInt32(width), height: UInt32(height),
            x0: shift(registrations[0].x, width, analysisWidth), y0: shift(registrations[0].y, height, analysisHeight),
            x2: shift(registrations[2].x, width, analysisWidth), y2: shift(registrations[2].y, height, analysisHeight),
            contrast: Float(weights.contrast), saturation: Float(weights.saturation), exposure: Float(weights.wellExposedness))
        encoder.setComputePipelineState(pipeline)
        for i in 0..<3 { encoder.setBuffer(buffers[i], offset: 0, index: i) }
        encoder.setBuffer(output, offset: 0, index: 3)
        encoder.setBytes(&p, length: MemoryLayout<Parameters>.stride, index: 4)
        let group = min(pipeline.threadExecutionWidth, pipeline.maxTotalThreadsPerThreadgroup)
        encoder.dispatchThreads(MTLSize(width: width * height, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: group, height: 1, depth: 1))
        encoder.endEncoding(); command.commit(); command.waitUntilCompleted()
        guard command.status == .completed else { throw MetalLUTError.failed(command.error?.localizedDescription ?? "노출 융합 GPU 실패") }
        try Task.checkCancellation()
        return SDRImage(rgba: Data(bytes: output.contents(), count: width * height * 4), width: width, height: height)
    }
}
