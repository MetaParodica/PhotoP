import Foundation
import ImageIO

// Serial, utility-priority caller. Reviews never enter the capture session and
// never modify an image. Cancelled/superseded requests do not write reports.
actor PhotoReviewService {
    static let shared = PhotoReviewService()
    func review(_ url: URL, reference: CaptureGuideReference?, documents: URL? = nil) async throws -> PhotoReviewReport {
        try Task.checkCancellation()
        let hash = try LUTPhotoEditor.hashFile(url)
        let directory = try documents ?? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let root = directory.appendingPathComponent("CoachReviews", isDirectory: true)
        let stored = root.appendingPathComponent(hash + ".json")
        if FileManager.default.fileExists(atPath: stored.path), let file = try? FileHandle(forReadingFrom: stored) {
            defer { try? file.close() }
            if let bytes = try file.read(upToCount: 512 * 1024 + 1), bytes.count <= 512 * 1024,
               let cached = try? JSONDecoder().decode(PhotoReviewReport.self, from: bytes), cached.valid, cached.originalSHA256 == hash {
                try Task.checkCancellation()
                return cached
            }
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw ImageEditingError.invalid("촬영 리뷰용 이미지를 읽을 수 없습니다. 원본은 그대로 유지합니다.")
        }
        let raw = url.pathExtension.lowercased() == "dng"
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: !raw,
            kCGImageSourceCreateThumbnailFromImageIfAbsent: !raw, kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 640, kCGImageSourceShouldCacheImmediately: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageEditingError.invalid(raw ? "RAW 내장 미리보기가 없어 리뷰를 생략합니다. RAW 현상 결과를 가장하지 않습니다." : "SDR 리뷰 이미지를 준비하지 못했습니다.")
        }
        try Task.checkCancellation()
        let snapshot = CompositionAnalyzer.analyzeImage(image, width: image.width, height: image.height,
            scene: .general, time: ProcessInfo.processInfo.systemUptime)
        let report = PhotoReviewReport(originalFilename: url.lastPathComponent, originalSHA256: hash, analyzedAt: Date(),
            sourceDescription: raw ? "RAW 내장 SDR 미리보기 기준 · RAW 현상/센서 평가 아님" : "방향 적용된 640px SDR 이미지 기준 · 센서/HDR/미학 평가 아님",
            findings: PhotoReviewEngine.findings(snapshot: snapshot, reference: reference), reference: reference)
        guard report.valid else { throw CameraError.invalidPhotoData }
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // Bounded derived-report cache. Reaching capacity never deletes photos
        // or blocks a new in-memory review; no silent recursive cache removal.
        let entries = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        if entries.filter({ $0.pathExtension == "json" }).count < 256 || FileManager.default.fileExists(atPath: stored.path) {
            try Task.checkCancellation()
            try JSONEncoder().encode(report).write(to: stored, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        return report
    }
}
