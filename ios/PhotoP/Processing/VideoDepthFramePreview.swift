@preconcurrency import AVFoundation
@preconcurrency import CoreImage
import Foundation

// Bounded editing preview; does not replay tracking/history from the clip start.
actor VideoDepthFramePreview {
    private var cached: (URL, Double, CIImage, SoftwareDepthField?)?
    private let engine = NaturalDepthEngine()
    private let estimator = ExternalDepthEstimator()
    private let context = CIContext(options: [.cacheIntermediates: false,
        .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!])
    func image(url: URL, time: Double, parameters: VideoDepthKeyframe? = nil) throws -> SDRImage {
        try Task.checkCancellation()
        if cached?.0 != url || cached?.1 != time {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 768,height: 768)
            generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
            let cg = try generator.copyCGImage(at: CMTime(seconds: time,preferredTimescale: 600),actualTime: nil)
            cached = (url,time,CIImage(cgImage: cg),nil)
        }
        guard var snapshot = cached else { throw CameraError.invalidPhotoData }
        var image = snapshot.2
        if let parameters {
            guard parameters.selection == nil, !parameters.requiresTracking else { throw ImageEditingError.invalid("추적 전환은 전체 심도 영상을 만든 후 확인하세요.") }
            if snapshot.3 == nil { snapshot.3 = try estimator.estimate(image); cached = snapshot }
            guard let field = snapshot.3 else { throw CameraError.invalidPhotoData }
            image = try engine.renderField(color: image,field: field,aperture: parameters.aperture,
                focus: parameters.focus,profile: parameters.profile,source: "video-timeline-preview",qualityPairs: 8).image
        }
        try Task.checkCancellation()
        guard let cg = context.createCGImage(image,from: image.extent,format: .RGBA8,colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!) else { throw CameraError.invalidPhotoData }
        return try SDRImage.rasterize(cg)
    }
}
