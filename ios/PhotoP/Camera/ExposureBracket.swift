import AVFoundation

struct ExposureBracketPlan: Sendable {
    let biases: [Double]
    static func make(center: Double, step: Double, limits: ClosedRange<Double>, maximumCount: Int,
                     rawMode: RawCaptureMode, live: Bool, exposureMode: AVCaptureDevice.ExposureMode?) throws -> Self {
        guard maximumCount >= 3, rawMode == .processed, !live, exposureMode == .continuousAutoExposure,
              center.isFinite, step.isFinite, (0.5...2).contains(step) else { throw CameraError.invalidSettings }
        let biases = [center - step, center, center + step]
        guard biases.allSatisfy({ $0.isFinite && limits.contains($0) }),
              Set(biases.map { Float($0) }).count == 3 else { throw CameraError.invalidSettings }
        return Self(biases: biases)
    }
}

struct CapturedSeries: Sendable {
    let photos: [CapturedPhoto]
    let requestedBiases: [Double]?
}

// Sequence counts are 1-based for brackets. The request ID is checked by the
// adapter before any delivery reaches this value; callbacks may arrive unordered.
struct PhotoSeriesDelivery {
    let format: PhotoFileFormat
    let biases: [Double]?
    private var received: [Int: CapturedPhoto] = [:]
    private var invalid = false
    init(format: PhotoFileFormat, biases: [Double]?) { self.format = format; self.biases = biases }
    var expectedCount: Int { biases?.count ?? 1 }
    mutating func receive(_ data: Data?, isRaw: Bool, sequence: Int, bracketBias: Double?) throws {
        do {
            guard !invalid, expectedCount == 1 || expectedCount == 3, let data, isRaw == (format == .dng), (1...expectedCount).contains(sequence),
                  received[sequence] == nil else { throw CameraError.invalidPhotoData }
            if let biases {
                guard let bracketBias, bracketBias.isFinite, abs(bracketBias - biases[sequence - 1]) < 0.001 else { throw CameraError.invalidPhotoData }
            } else if bracketBias != nil { throw CameraError.invalidPhotoData }
            received[sequence] = try CapturedPhoto(data: data, expectedFormat: format)
        } catch { invalid = true; throw error }
    }
    func result() throws -> CapturedSeries {
        guard !invalid, expectedCount == 1 || expectedCount == 3, received.count == expectedCount else { throw CameraError.missingPhoto }
        return CapturedSeries(photos: try (1...expectedCount).map {
            guard let photo = received[$0] else { throw CameraError.missingPhoto }; return photo
        }, requestedBiases: biases)
    }
}
