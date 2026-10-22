import XCTest
#if canImport(PhotoPCompositionCore)
@testable import PhotoPCompositionCore
#else
@testable import PhotoP
#endif

final class PhotoReviewCoreTests: XCTestCase {
    private let bounds = CGRect(x: 0.2, y: 0.2, width: 0.2, height: 0.5)
    private func person(face: CGPoint? = nil) -> DetectedPerson {
        DetectedPerson(bounds: bounds, faceCenter: face, confidence: 0.9)
    }
    private func snapshot(people: [DetectedPerson] = [], available: Bool = true, width: Int = 480) -> CompositionSnapshot {
        CompositionSnapshot(generatedAt: 1, width: width, height: 640, bodies: [], polygons: [], advice: "fixture",
                            people: people, evidence: SceneEvidence(generatedAt: 1), detectionAvailable: available)
    }
    private func reference(face: Bool = false, aspect: Double = 0.75, count: Int = 1) -> CaptureGuideReference {
        CaptureGuideReference(intent: .balanced, rule: .thirds, mode: .photo, subjectBounds: bounds,
            subjectAnchor: CGPoint(x: 0.3, y: 0.45), target: CGPoint(x: 1.0 / 3, y: 1.0 / 3), isFaceAnchor: face,
            personCount: count, imageAspect: aspect, brightness: 0.5, roll: 0, capturedAt: Date())
    }
    func testNoDetectionIsNotTreatedAsFailedDetection() {
        let findings = PhotoReviewEngine.findings(snapshot: snapshot(), reference: nil)
        XCTAssertTrue(findings.contains { $0.id == "people" && $0.basis == .measured })
        XCTAssertFalse(findings.contains { $0.id == "visionFailure" })
    }
    func testFailedDetectionExplicitlyReportsLimitNotZeroPeopleFact() {
        let findings = PhotoReviewEngine.findings(snapshot: snapshot(available: false), reference: nil)
        XCTAssertTrue(findings.contains { $0.id == "visionFailure" && $0.basis == .limitation })
        XCTAssertFalse(findings.contains { $0.id == "people" })
    }
    func testReviewSeparatesMeasurementsSuggestionsAndLimitationsWithoutScore() throws {
        var frame = snapshot(people: [person()])
        frame.evidence.photometry = try XCTUnwrap(ScenePhotometry.measure(rgba: Array(repeating: [UInt8](arrayLiteral: 255, 255, 255, 255), count: 64).flatMap { $0 }, side: 8))
        let findings = PhotoReviewEngine.findings(snapshot: frame, reference: nil)
        XCTAssertTrue(findings.contains { $0.id == "exposure" && $0.basis == .measured })
        XCTAssertTrue(findings.contains { $0.id == "highlightTip" && $0.basis == .suggestion })
        XCTAssertTrue(findings.contains { $0.id == "sharpness" && $0.message.contains("확정하지") })
        XCTAssertTrue(findings.contains { $0.id == "color" && $0.basis == .measured })
        XCTAssertTrue(findings.contains { $0.id == "aesthetic" && $0.basis == .limitation })
        XCTAssertFalse(findings.contains { $0.id.lowercased().contains("score") })
    }
    func testBeforeAfterComparisonOnlyUsesSpatialCorrespondence() {
        let findings = PhotoReviewEngine.findings(snapshot: snapshot(people: [person()]), reference: reference())
        XCTAssertTrue(findings.contains { $0.id == "comparison" && $0.message.contains("동일 인물 확인/사진 품질 점수가 아닙니다") })
        XCTAssertFalse(findings.contains { $0.id == "comparisonUnavailable" })
    }
    func testComparisonRejectsChangedCountAspectOrUnavailableFaceLandmark() {
        for ref in [reference(aspect: 1), reference(count: 2), reference(face: true)] {
            let findings = PhotoReviewEngine.findings(snapshot: snapshot(people: [person()]), reference: ref)
            XCTAssertFalse(findings.contains { $0.id == "comparison" })
            XCTAssertTrue(findings.contains { $0.id == "comparisonUnavailable" })
        }
    }
    func testComparisonRejectsUnrelatedSubjectEvenWithMatchingCount() {
        let other = DetectedPerson(bounds: CGRect(x: 0.7, y: 0.2, width: 0.2, height: 0.5), faceCenter: nil, confidence: 0.9)
        let findings = PhotoReviewEngine.findings(snapshot: snapshot(people: [other]), reference: reference())
        XCTAssertFalse(findings.contains { $0.id == "comparison" })
    }
    func testMirroredPreCaptureReferenceIsConvertedBackToOriginalCoordinates() throws {
        var engine = CompositionGuideEngine()
        let guide = try XCTUnwrap(engine.update(snapshot(people: [person()]), target: .left, now: 1)).0
        let ref = try XCTUnwrap(CaptureGuideReference.make(guide: guide, intent: .balanced, mode: .pro, mirrored: true, tilt: nil, now: 1))
        XCTAssertEqual(try XCTUnwrap(ref.subjectBounds).minX, 0.6, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(ref.subjectAnchor).x, 0.7, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(ref.target).x, 2.0 / 3, accuracy: 0.001)
        XCTAssertTrue(ref.valid)
        XCTAssertNil(CaptureGuideReference.make(guide: guide, intent: .balanced, mode: .photo, mirrored: false, tilt: nil, now: 2))
    }
    func testReviewReportRoundTripsAndRejectsUnsafePathsVersionsAndHashes() throws {
        let report = PhotoReviewReport(originalFilename: "photo.jpg", originalSHA256: String(repeating: "a", count: 64), analyzedAt: Date(),
                                       sourceDescription: "SDR fixture", findings: PhotoReviewEngine.findings(snapshot: snapshot(), reference: nil), reference: reference())
        XCTAssertTrue(report.valid)
        XCTAssertTrue(try JSONDecoder().decode(PhotoReviewReport.self, from: JSONEncoder().encode(report)).valid)
        var old = report; old.version = 2; XCTAssertFalse(old.valid)
        let unsafe = PhotoReviewReport(originalFilename: "../photo.jpg", originalSHA256: report.originalSHA256, analyzedAt: Date(), sourceDescription: "fixture", findings: [], reference: nil)
        XCTAssertFalse(unsafe.valid)
        let hash = PhotoReviewReport(originalFilename: "photo.jpg", originalSHA256: String(repeating: "z", count: 64), analyzedAt: Date(), sourceDescription: "fixture", findings: [], reference: nil)
        XCTAssertFalse(hash.valid)
    }
    func testCorruptReferenceAndDuplicateFindingsAreRejected() {
        XCTAssertFalse(reference(aspect: 0).valid)
        XCTAssertFalse(reference(count: 200).valid)
        let finding = PhotoReviewFinding(id: "same", title: "fixture", message: "fixture", basis: .measured)
        let report = PhotoReviewReport(originalFilename: "photo.jpg", originalSHA256: String(repeating: "0", count: 64), analyzedAt: Date(),
                                       sourceDescription: "fixture", findings: [finding, finding], reference: nil)
        XCTAssertFalse(report.valid)
    }
}
