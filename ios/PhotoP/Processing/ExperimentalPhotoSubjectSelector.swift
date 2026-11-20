@preconcurrency import CoreML
@preconcurrency import CoreImage
import CoreVideo
import Foundation
import Accelerate

/// Photo-only initializer of the pinned EdgeTAM conversion. No temporal memory,
/// autofocus, live/video hooks or state shared with the baseline depth estimator.
final class ExperimentalPhotoSubjectSelector {
    static var isBundled: Bool {
        Bundle.main.url(forResource: "ExperimentalPhotoEncoder", withExtension: "mlmodelc") != nil &&
        Bundle.main.url(forResource: "ExperimentalPhotoInitializer", withExtension: "mlmodelc") != nil
    }
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var encoder: MLModel?
    private var initializer: MLModel?
    private let diagnostics: (@Sendable (String) -> Void)?
    init(diagnostics: (@Sendable (String) -> Void)? = nil) { self.diagnostics = diagnostics }

    func refine(original: URL, focus: CGPoint, request: ExperimentalPhotoRequest, preferWholeSubject: Bool = false) throws -> (DepthMatteSurface, ExperimentalDepthRecord) {
        try check(request)
        guard let image = CIImage(contentsOf: original, options: [.applyOrientationProperty: true]),
              image.extent.width.isFinite, image.extent.height.isFinite, image.extent.width > 0, image.extent.height > 0,
              HighResolutionPlan(width: Int(image.extent.width), height: Int(image.extent.height)) != nil,
              focus.x.isFinite, focus.y.isFinite, (0...1).contains(focus.x), (0...1).contains(focus.y) else {
            throw ExperimentalSelectionFailure.invalidOutput
        }
        OnDeviceInferenceGate.lock.lock()
        defer { OnDeviceInferenceGate.lock.unlock(); context.clearCaches() }
        try check(request)
        let trace = ProcessingTrace.begin("Experimental photo selection")
        defer { ProcessingTrace.end("Experimental photo selection", trace) }
        return try autoreleasepool {
            let models = try load()
            var input: CVPixelBuffer?
            guard CVPixelBufferCreate(kCFAllocatorDefault, 1024, 1024, kCVPixelFormatType_32BGRA,
                [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &input) == kCVReturnSuccess,
                  let input else { throw ExperimentalSelectionFailure.invalidOutput }
            // Match the reference SAM2 transform: resize the upright image to
            // the model square, map points/masks inversely to source geometry.
            // RGB normalization is folded into the pinned encoder graph.
            let color = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
            let resized = color.transformed(by: CGAffineTransform(scaleX: 1024 / color.extent.width, y: 1024 / color.extent.height))
            context.render(resized, to: input, bounds: CGRect(x: 0, y: 0, width: 1024, height: 1024),
                           colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            if diagnostics != nil, CVPixelBufferLockBaseAddress(input, .readOnly) == kCVReturnSuccess {
                if let pointer = CVPixelBufferGetBaseAddress(input) {
                    let offset = min(1023, Int(focus.y * 1024)) * CVPixelBufferGetBytesPerRow(input) + min(1023, Int(focus.x * 1024)) * 4
                    let bytes = pointer.assumingMemoryBound(to: UInt8.self)
                    diagnostics?("input RGB at point: \(bytes[offset + 2]),\(bytes[offset + 1]),\(bytes[offset])")
                }
                CVPixelBufferUnlockBaseAddress(input, .readOnly)
            }
            let features = try models.0.prediction(from: MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(pixelBuffer: input)]))
            try check(request)
            let points = try MLMultiArray(shape: [1, 1, 2], dataType: .float16)
            points.dataPointer.assumingMemoryBound(to: Float16.self)[0] = Float16(min(1023.5, Double(focus.x) * 1024))
            points.dataPointer.assumingMemoryBound(to: Float16.self)[1] = Float16(min(1023.5, Double(focus.y) * 1024))
            let labels = try MLMultiArray(shape: [1, 1], dataType: .int32)
            labels.dataPointer.assumingMemoryBound(to: Int32.self)[0] = 1
            let mask = try MLMultiArray(shape: [1, 1, 1024, 1024], dataType: .float16)
            mask.dataPointer.initializeMemory(as: UInt16.self, repeating: 0, count: mask.count)
            var arguments: [String: Any] = ["point_coords": MLFeatureValue(multiArray: points),
                "point_labels": MLFeatureValue(multiArray: labels), "mask_input": MLFeatureValue(multiArray: mask)]
            for name in ["initial_vision_features", "high_res_feature_0", "high_res_feature_1"] {
                guard let feature = features.featureValue(for: name) else { throw ExperimentalSelectionFailure.invalidOutput }
                arguments[name] = feature
            }
            let result = try models.1.prediction(from: MLDictionaryFeatureProvider(dictionary: arguments))
            try check(request)
            guard let embeddings = result.featureValue(for: "upscaled_embedding")?.multiArrayValue,
                  let coefficients = result.featureValue(for: "hyper_in")?.multiArrayValue,
                  let qualities = result.featureValue(for: "candidate_ious")?.multiArrayValue,
                  qualities.shape.map(\.intValue) == [1, 3],
                  let score = result.featureValue(for: "object_score")?.multiArrayValue else { throw ExperimentalSelectionFailure.invalidOutput }
            let dense = try Self.floats(embeddings, shape: [1, 32, 256, 256])
            let weights = try Self.floats(coefficients, shape: [1, 4, 32])
            let candidates = try Self.reconstructMasks(embeddings: dense, coefficients: weights)
            let visible = Self.number(score, index: 0)
            diagnostics?("linear head embedding=\(dense.min() ?? .nan)...\(dense.max() ?? .nan) coefficients=\(weights.min() ?? .nan)...\(weights.max() ?? .nan)")
            var predicted: Float = -.infinity
            var values = candidates[0]
            var largest = 0
            for candidate in 0..<3 {
                let trial = candidates[candidate]
                let quality = Self.number(qualities, index: candidate * qualities.strides[1].intValue)
                let area = trial.reduce(0) { $0 + ($1 > 0 ? 1 : 0) }
                diagnostics?("candidate \(candidate) q=\(quality) area=\(area) min=\(trial.min() ?? .nan) max=\(trial.max() ?? .nan)")
                if !preferWholeSubject, quality > predicted {
                    values = trial; predicted = quality
                } else if preferWholeSubject, area > largest, ExperimentalPhotoMaskPolicy.alpha(logits: trial, width: 256, height: 256,
                    x: Double(focus.x), y: Double(focus.y), predictedIoU: quality, objectScore: visible) != nil {
                    values = trial; predicted = quality; largest = area
                }
            }
            guard let alpha = ExperimentalPhotoMaskPolicy.alpha(logits: values, width: 256, height: 256,
                x: Double(focus.x), y: Double(focus.y), predictedIoU: predicted, objectScore: visible) else {
                throw ExperimentalSelectionFailure.noSubject
            }
            let bytes = alpha.withUnsafeBytes { Data($0) }
            guard let provider = CGDataProvider(data: bytes as CFData),
                  let cg = CGImage(width: 256, height: 256, bitsPerComponent: 32, bitsPerPixel: 32, bytesPerRow: 1024,
                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: [.floatComponents, .byteOrder32Little],
                    provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
                throw ExperimentalSelectionFailure.invalidOutput
            }
            let seed = CIImage(cgImage: cg, options: [.colorSpace: NSNull()])
            guard let refined = try DepthMatteRefiner().refine(color: color, focus: focus, embedded: seed, maximumDimension: 512) else {
                diagnostics?("selected mask rejected by guided matte at original focus")
                throw ExperimentalSelectionFailure.noSubject
            }
            try check(request)
            let record = ExperimentalDepthRecord(outcome: .applied, focusX: Double(focus.x), focusY: Double(focus.y),
                predictedIoU: predicted, objectScore: visible)
            return (refined, record)
        }
    }

    private func check(_ request: ExperimentalPhotoRequest) throws {
        try Task.checkCancellation()
        guard request.isCurrent else { throw ExperimentalSelectionFailure.disabled }
    }
    private static func number(_ values: MLMultiArray, index: Int) -> Float {
        switch values.dataType {
        case .float16: return Float(values.dataPointer.assumingMemoryBound(to: Float16.self)[index])
        case .float32: return values.dataPointer.assumingMemoryBound(to: Float.self)[index]
        case .double: return Float(values.dataPointer.assumingMemoryBound(to: Double.self)[index])
        default: return .nan
        }
    }
    private static func floats(_ values: MLMultiArray, shape: [Int]) throws -> [Float] {
        guard values.dataType == .float32, values.shape.map(\.intValue) == shape else { throw ExperimentalSelectionFailure.invalidOutput }
        return try values.withUnsafeBytes { raw in
            let strides = values.strides.map(\.intValue)
            let last = zip(shape, strides).reduce(0) { $0 + ($1.0 - 1) * $1.1 }
            guard strides.allSatisfy({ $0 >= 0 }), last >= 0, last < raw.count / 4 else { throw ExperimentalSelectionFailure.invalidOutput }
            let pointer = raw.bindMemory(to: Float.self)
            var contiguous = true, step = 1
            for d in shape.indices.reversed() { if shape[d] > 1 && strides[d] != step { contiguous = false }; step *= shape[d] }
            if contiguous { return Array(pointer.prefix(step)) }
            return (0..<step).map { index in
                var remaining = index, offset = 0
                for d in shape.indices.reversed() { offset += (remaining % shape[d]) * strides[d]; remaining /= shape[d] }
                return pointer[offset]
            }
        }
    }
    /// SAM2's unchanged final linear head: [3,32] × [32,pixels]. The
    /// single-mask token (row zero) is intentionally excluded for one-point SAM2.
    /// Reconstructing FP32 logits avoids the released model's zero mask output
    /// on the tested Core ML CPU runtime; no learned parameters are replaced.
    static func reconstructMasks(embeddings: [Float], coefficients: [Float], spatialCount: Int = 256 * 256) throws -> [[Float]] {
        guard spatialCount > 0, spatialCount <= 256 * 256, embeddings.count == 32 * spatialCount,
              coefficients.count == 4 * 32, embeddings.allSatisfy(\.isFinite), coefficients.allSatisfy(\.isFinite) else {
            throw ExperimentalSelectionFailure.invalidOutput
        }
        var output = [Float](repeating: 0, count: 3 * spatialCount)
        coefficients.withUnsafeBufferPointer { c in embeddings.withUnsafeBufferPointer { e in
            output.withUnsafeMutableBufferPointer { out in
                vDSP_mmul(c.baseAddress!.advanced(by: 32), 1, e.baseAddress!, 1, out.baseAddress!, 1,
                          3, vDSP_Length(spatialCount), 32)
            }
        } }
        return (0..<3).map { Array(output[($0 * spatialCount)..<(($0 + 1) * spatialCount)]) }
    }
    private func load() throws -> (MLModel, MLModel) {
        if let encoder, let initializer { return (encoder, initializer) }
        guard let first = Bundle.main.url(forResource: "ExperimentalPhotoEncoder", withExtension: "mlmodelc"),
              let second = Bundle.main.url(forResource: "ExperimentalPhotoInitializer", withExtension: "mlmodelc") else {
            throw ExperimentalSelectionFailure.unavailable
        }
        let configuration = MLModelConfiguration()
        #if targetEnvironment(simulator)
        configuration.computeUnits = .cpuOnly
        #else
        // FP32 initializer can use GPU; an ANE-only request would force it to CPU.
        configuration.computeUnits = .all
        #endif
        let encoder = try MLModel(contentsOf: first, configuration: configuration)
        let initializer = try MLModel(contentsOf: second, configuration: configuration)
        guard let image = encoder.modelDescription.inputDescriptionsByName["image"]?.imageConstraint,
              image.pixelsWide == 1024, image.pixelsHigh == 1024 else { throw ExperimentalSelectionFailure.invalidOutput }
        let shapes = ["initial_vision_features": [1,256,64,64], "high_res_feature_0": [1,32,256,256], "high_res_feature_1": [1,64,128,128]]
        for (name, shape) in shapes {
            guard encoder.modelDescription.outputDescriptionsByName[name]?.multiArrayConstraint?.shape.map(\.intValue) == shape,
                  initializer.modelDescription.inputDescriptionsByName[name]?.multiArrayConstraint?.shape.map(\.intValue) == shape else {
                throw ExperimentalSelectionFailure.invalidOutput
            }
        }
        self.encoder = encoder; self.initializer = initializer
        return (encoder, initializer)
    }
}
