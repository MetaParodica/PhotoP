@preconcurrency import CoreImage
@preconcurrency import CoreML
@preconcurrency import Vision
import Foundation

/// Independent still-photo adapter. The upstream recurrent model is initialized
/// and refined on ONE selected photograph; no state is carried into other photos.
final class ExperimentalPortraitMatte {
    static var modelFolder: URL? { Bundle.main.url(forResource: "ExperimentalPortraitMatte", withExtension: nil) }
    static var isBundled: Bool {
        guard let root = modelFolder else { return false }
        return MatAnyoneCoreML.modelNames.allSatisfy { FileManager.default.fileExists(atPath: root.appendingPathComponent($0 + ".mlmodelc").path) }
    }
    private let context = CIContext(options: [.cacheIntermediates: false])

    func refine(original: URL, focus: CGPoint, request: ExperimentalPhotoRequest) throws -> (DepthMatteSurface, ExperimentalPortraitRecord) {
        try check(request)
        guard let folder = Self.modelFolder, Self.isBundled else { throw ExperimentalSelectionFailure.unavailable }
        // The selection initializer is a seed dependency, even when the generic
        // photo-selection option is off. Pick a larger valid candidate for the
        // explicit person intent, rather than a nested garment mask.
        let seed = try ExperimentalPhotoSubjectSelector().refine(original: original, focus: focus, request: request, preferWholeSubject: true).0
        guard let color = CIImage(contentsOf: original, options: [.applyOrientationProperty: true]),
              color.extent.width.isFinite, color.extent.height.isFinite,
              color.extent.width > 0, color.extent.height > 0, color.extent.width <= 16384, color.extent.height <= 16384,
              let geometry = ExperimentalPortraitGeometry(sourceWidth: Int(color.extent.width), sourceHeight: Int(color.extent.height)) else {
            throw ExperimentalSelectionFailure.invalidOutput
        }
        OnDeviceInferenceGate.lock.lock()
        defer { OnDeviceInferenceGate.lock.unlock(); context.clearCaches() }
        try check(request)
        let span = ProcessingTrace.begin("Experimental photo portrait matte")
        defer { ProcessingTrace.end("Experimental photo portrait matte", span) }
        return try autoreleasepool {
            try confirmPerson(color: color, focus: focus, seed: seed)
            try check(request)
            #if targetEnvironment(simulator)
            let units = MLComputeUnits.cpuOnly
            #else
            let units = MLComputeUnits.all
            #endif
            let model = try MatAnyoneCoreML(modelsDir: folder, computeUnits: units)
            guard model.workingW == 288, model.workingH == 512, model.modelURLs.count == 6 else {
                throw ExperimentalSelectionFailure.invalidOutput
            }
            let extent = CGRect(x: 0, y: 0, width: 288, height: 512)
            let upright = color.transformed(by: CGAffineTransform(translationX: -color.extent.minX, y: -color.extent.minY))
            let placed = upright.transformed(by: CGAffineTransform(scaleX: CGFloat(geometry.width) / upright.extent.width,
                y: CGFloat(geometry.height) / upright.extent.height)).transformed(by: CGAffineTransform(translationX: CGFloat(geometry.x),
                y: CGFloat(512 - geometry.y - geometry.height)))
            let working = placed.composited(over: CIImage(color: .black).cropped(to: extent)).cropped(to: extent)
            guard let cg = context.createCGImage(working, from: extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else {
                throw ExperimentalSelectionFailure.invalidOutput
            }
            let raster = try SDRImage.rasterize(cg), count = 288 * 512
            var rgb = [Float](repeating: 0, count: count * 3), mask = [Float](repeating: 0, count: count)
            raster.rgba.withUnsafeBytes { raw in
                let bytes = raw.bindMemory(to: UInt8.self)
                for i in 0..<count {
                    rgb[i] = Float(bytes[i * 4]) / 255
                    rgb[count + i] = Float(bytes[i * 4 + 1]) / 255
                    rgb[2 * count + i] = Float(bytes[i * 4 + 2]) / 255
                }
            }
            for y in 0..<geometry.height { for x in 0..<geometry.width {
                let sx = (Double(x) + 0.5) * Double(seed.width) / Double(geometry.width) - 0.5
                let sy = (Double(y) + 0.5) * Double(seed.height) / Double(geometry.height) - 0.5
                mask[(geometry.y + y) * 288 + geometry.x + x] = DepthGrid.sample(seed.alpha, width: seed.width, height: seed.height, x: sx, y: sy) >= 0.5 ? 1 : 0
            } }
            try check(request)
            let engine = MatAnyoneCoreMLEngine(model: model)
            let alpha = try engine.seed(image: .init(data: rgb, shape: [1, 3, 512, 288]), seedMask: mask, warmup: 10)
            try check(request)
            guard alpha.count == count, alpha.allSatisfy({ $0.isFinite && (-0.001...1.001).contains($0) }) else {
                throw ExperimentalSelectionFailure.invalidOutput
            }
            // Preserve floating neural alpha. Color unmixing may change colors,
            // but the coarse-Vision color-line solver must not overwrite alpha.
            let small = try SDRImage.decode(original, previewMaxDimension: 512)
            var unpadded = [Float](repeating: 0, count: small.width * small.height)
            for y in 0..<small.height { for x in 0..<small.width {
                let sx = Double(geometry.x) + (Double(x) + 0.5) * Double(geometry.width) / Double(small.width) - 0.5
                let sy = Double(geometry.y) + (Double(y) + 0.5) * Double(geometry.height) / Double(small.height) - 0.5
                unpadded[y * small.width + x] = min(1, max(0, DepthGrid.sample(alpha, width: 288, height: 512, x: sx, y: sy)))
            } }
            let px = min(small.width - 1, Int(focus.x * CGFloat(small.width)))
            let py = min(small.height - 1, Int(focus.y * CGFloat(small.height)))
            let area = unpadded.reduce(0) { $0 + ($1 > 0.5 ? 1 : 0) }
            guard unpadded[py * small.width + px] > 0.5, area >= 9, Double(area) / Double(unpadded.count) < 0.995 else {
                throw ExperimentalSelectionFailure.noSubject
            }
            func linear(_ c: UInt8) -> Float {
                let value = Float(c) / 255
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            let colors: [SIMD3<Float>] = small.rgba.withUnsafeBytes { raw in
                let bytes = raw.bindMemory(to: UInt8.self)
                return (0..<(small.width * small.height)).map { i in SIMD3(linear(bytes[i * 4]), linear(bytes[i * 4 + 1]), linear(bytes[i * 4 + 2])) }
            }
            guard let surface = DepthMatteCore.refine(alpha: unpadded, color: colors, width: small.width, height: small.height, preserveAlpha: true) else {
                throw ExperimentalSelectionFailure.invalidOutput
            }
            try check(request)
            return (surface, ExperimentalPortraitRecord(outcome: .applied, focusX: Double(focus.x), focusY: Double(focus.y)))
        }
    }

    private func check(_ request: ExperimentalPhotoRequest) throws {
        try Task.checkCancellation()
        guard request.isCurrent else { throw ExperimentalSelectionFailure.disabled }
    }
    private func confirmPerson(color: CIImage, focus: CGPoint, seed: DepthMatteSurface) throws {
        let scale = min(1, 1024 / max(color.extent.width, color.extent.height))
        let image = color.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let people = VNDetectHumanRectanglesRequest(); people.upperBodyOnly = true
        let faces = VNDetectFaceRectanglesRequest()
        try VNImageRequestHandler(ciImage: image).perform([people, faces])
        let visionPoint = CGPoint(x: focus.x, y: 1 - focus.y)
        let insideHuman = people.results?.contains { $0.confidence >= 0.3 && $0.boundingBox.contains(visionPoint) } == true
        let selectedFaces = (faces.results ?? []).filter { face in
            let rect = face.boundingBox
            return DepthGrid.sample(seed.alpha, width: seed.width, height: seed.height,
                x: Double(rect.midX) * Double(seed.width) - 0.5,
                y: Double(1 - rect.midY) * Double(seed.height) - 0.5) > 0.5
        }
        guard selectedFaces.count <= 1 else { throw ExperimentalSelectionFailure.ambiguousPerson }
        guard insideHuman || selectedFaces.count == 1 else { throw ExperimentalSelectionFailure.notPerson }
    }
}
