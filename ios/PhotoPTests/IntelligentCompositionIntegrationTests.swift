import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import PhotoP

// These tests require Apple's SDK/runtime. Portable Swift tests do NOT run them.
final class IntelligentCompositionIntegrationTests: XCTestCase {
    private func fixture() throws -> (root: URL, photo: URL, image: CGImage) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let side = 96
        var rgba: [UInt8] = []
        for y in 0..<side { for x in 0..<side {
            let v: UInt8 = x < side / 2 && y < side / 2 ? 255 : 0
            rgba += [v, v, v, 255]
        } }
        let image = try SDRImage(rgba: Data(rgba), width: side, height: side).cgImage()
        let data = NSMutableData()
        let output = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(output, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(output))
        let photo = root.appendingPathComponent("fixture.png")
        try (data as Data).write(to: photo)
        return (root, photo, image)
    }
    func testCGImageRasterMatchesTopLeftVisionCoordinates() throws {
        let fixture = try fixture()
        let metrics = try XCTUnwrap(SceneImageRaster.photometry(fixture.image))
        XCTAssertEqual(try XCTUnwrap(metrics.brightness(in: CGRect(x: 0, y: 0, width: 0.5, height: 0.5))), 1, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(metrics.brightness(in: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5))), 0, accuracy: 0.01)
    }
    func testRealVisionOnSyntheticQuadrantDoesNotInventPeople() throws {
        let fixture = try fixture()
        let frame = CompositionAnalyzer.analyzeImage(fixture.image, width: 96, height: 96, scene: .general, time: 1)
        XCTAssertTrue(frame.people.isEmpty)
        XCTAssertNotNil(frame.evidence.photometry)
        // A runtime failure is permitted only with an explicit unavailable flag.
        if !frame.detectionAvailable { XCTAssertTrue(frame.peopleAnalysisMessage.contains("수행하지 못")) }
    }
    func testReviewPersistsValidatedHashBoundReportAndKeepsOriginalBytes() async throws {
        let fixture = try fixture(), bytes = try Data(contentsOf: fixture.photo)
        let service = PhotoReviewService()
        let report = try await service.review(fixture.photo, reference: nil, documents: fixture.root)
        XCTAssertTrue(report.valid)
        XCTAssertEqual(report.originalSHA256, LUTPhotoEditor.hash(bytes))
        XCTAssertTrue(report.sourceDescription.contains("SDR"))
        let reportURL = fixture.root.appendingPathComponent("CoachReviews").appendingPathComponent(report.originalSHA256 + ".json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: reportURL.path))
        let cached = try await service.review(fixture.photo, reference: nil, documents: fixture.root)
        XCTAssertEqual(cached.analyzedAt, report.analyzedAt)
        XCTAssertEqual(try Data(contentsOf: fixture.photo), bytes)
    }
    func testCancelledReviewDoesNotCreateReport() async throws {
        let fixture = try fixture()
        let task = Task { () -> PhotoReviewReport in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await PhotoReviewService().review(fixture.photo, reference: nil, documents: fixture.root)
        }
        do { _ = try await task.value; XCTFail("Cancelled review must not publish a report") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("CoachReviews").path))
    }
    @MainActor func testIntentAndRuleSelectionNeverWritesManualCameraControls() {
        let model = CameraModel()
        model.settings.exposure.manual = true; model.settings.exposure.iso = 321
        model.settings.exposure.locked = true; model.settings.focus.manual = true; model.settings.focus.lensPosition = 0.7
        let previous = model.settings
        for intent in ShootingIntent.allCases {
            model.shootingIntent = intent; model.intelligentOptionsChanged()
            for rule in CompositionRule.allCases { model.selectIntelligentRule(rule) }
        }
        model.applyCoachZoom() // No fresh supported camera -> no mutation.
        XCTAssertEqual(model.settings, previous)
        XCTAssertNil(model.livePreview); XCTAssertNil(model.cameraCoach)
    }
}
