@preconcurrency import CoreML
@preconcurrency import CoreImage
import CoreVideo
import Foundation

// Each instance has one processing/analysis executor; never called on MainActor.
// No downloads, image upload, or third-party runtime. Core ML normalization is
// already embedded in this exact pinned model: do not normalize a second time.
final class ExternalDepthEstimator {
    private var model: MLModel?
    private let context = CIContext(options: [.cacheIntermediates: false])

    func estimate(_ image: CIImage) throws -> SoftwareDepthField {
        OnDeviceInferenceGate.lock.lock(); defer { OnDeviceInferenceGate.lock.unlock() }
        try Task.checkCancellation()
        let model: MLModel
        if let loaded = self.model { model = loaded }
        else {
            guard let url = Bundle.main.url(forResource: "DepthAnythingV2SmallF16", withExtension: "mlmodelc") else {
                throw ImageEditingError.invalid("AI 깊이 모델이 앱에 없습니다. 원본은 보존됩니다.")
            }
            let configuration = MLModelConfiguration(); configuration.computeUnits = .all
            model = try MLModel(contentsOf: url, configuration: configuration)
            guard let input = model.modelDescription.inputDescriptionsByName["image"]?.imageConstraint,
                  input.pixelsWide == 518, input.pixelsHigh == 392,
                  let output = model.modelDescription.outputDescriptionsByName["depth"]?.imageConstraint,
                  output.pixelsWide == 518, output.pixelsHigh == 392,
                  output.pixelFormatType == kCVPixelFormatType_OneComponent16Half else {
                throw ImageEditingError.invalid("AI 모델 입력/출력 계약이 다릅니다. 원본은 보존됩니다.")
            }
            self.model = model
        }
        var input: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, 518, 392, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &input) == kCVReturnSuccess,
              let input else { throw CameraError.invalidPhotoData }
        let extent = image.extent
        guard extent.width.isFinite, extent.height.isFinite, extent.width > 0, extent.height > 0,
              extent.width <= 16384, extent.height <= 16384 else { throw CameraError.invalidPhotoData }
        guard let geometry = DepthModelGeometry(sourceWidth: Int(extent.width), sourceHeight: Int(extent.height)) else {
            throw ImageEditingError.invalid("AI 깊이 입력의 화면 비율이 지원 범위를 벗어납니다.")
        }
        // Preserve aspect (apart from pixel rounding), edge-pad, and unpad the
        // output. The publisher's stretch benchmark is NOT our measured quality.
        let resized = image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: CGAffineTransform(scaleX: CGFloat(geometry.width) / extent.width, y: CGFloat(geometry.height) / extent.height))
            .transformed(by: CGAffineTransform(translationX: CGFloat(geometry.x), y: CGFloat(392 - geometry.y - geometry.height)))
            .clampedToExtent().cropped(to: CGRect(x: 0, y: 0, width: 518, height: 392))
        context.render(resized, to: input, bounds: CGRect(x: 0, y: 0, width: 518, height: 392),
                       colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        let provider = try MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(pixelBuffer: input)])
        let prediction = try model.prediction(from: provider)
        try Task.checkCancellation()
        guard let map = prediction.featureValue(for: "depth")?.imageBufferValue,
              CVPixelBufferGetWidth(map) == 518, CVPixelBufferGetHeight(map) == 392,
              CVPixelBufferGetPixelFormatType(map) == kCVPixelFormatType_OneComponent16Half,
              CVPixelBufferLockBaseAddress(map, .readOnly) == kCVReturnSuccess else { throw CameraError.invalidPhotoData }
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly); context.clearCaches() }
        guard let base = CVPixelBufferGetBaseAddress(map) else { throw CameraError.invalidPhotoData }
        let stride = CVPixelBufferGetBytesPerRow(map)
        guard stride >= 518 * 2 else { throw CameraError.invalidPhotoData }
        var values = [Float](repeating: 0, count: geometry.width * geometry.height)
        for row in 0..<geometry.height {
            let pixels = base.advanced(by: (row + geometry.y) * stride).assumingMemoryBound(to: UInt16.self)
            for col in 0..<geometry.width { values[row * geometry.width + col] = Float(Float16(bitPattern: pixels[col + geometry.x])) }
        }
        guard let field = SoftwareDepthField(width: geometry.width, height: geometry.height, inverseDepth: values, units: .relativeInverse) else {
            throw ImageEditingError.invalid("AI 깊이 결과가 유효하지 않습니다. 원본은 보존됩니다.")
        }
        return field
    }
}
