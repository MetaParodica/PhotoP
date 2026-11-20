@preconcurrency import CoreML
@preconcurrency import CoreImage
import CoreVideo
import Foundation

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

    func refine(original: URL, focus: CGPoint, request: ExperimentalPhotoRequest) throws -> (DepthMatteSurface, ExperimentalDepthRecord) {
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
            guard let logits = result.featureValue(for: "low_res_mask")?.multiArrayValue,
                  logits.shape.map(\.intValue) == [1, 1, 256, 256],
                  let iou = result.featureValue(for: "best_iou")?.multiArrayValue,
                  let score = result.featureValue(for: "object_score")?.multiArrayValue else { throw ExperimentalSelectionFailure.invalidOutput }
            let predicted = Self.number(iou, index: 0), visible = Self.number(score, index: 0)
            let sy = logits.strides[2].intValue, sx = logits.strides[3].intValue
            let values = (0..<(256 * 256)).map { Self.number(logits, index: ($0 / 256) * sy + ($0 % 256) * sx) }
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
