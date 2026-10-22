import XCTest
#if canImport(PhotoPCompositionCore)
@testable import PhotoPCompositionCore
#else
@testable import PhotoP
#endif

final class IntelligentCoachTests: XCTestCase {
    private func raster(_ value: (Int, Int) -> UInt8, side: Int = 32) -> ScenePhotometry {
        var bytes: [UInt8] = []
        for y in 0..<side { for x in 0..<side { let v = value(x, y); bytes += [v, v, v, 255] } }
        return ScenePhotometry.measure(rgba: bytes, side: side)!
    }
    private func snapshot(_ time: Double = 1, people: [DetectedPerson] = [], evidence: SceneEvidence? = nil) -> CompositionSnapshot {
        CompositionSnapshot(generatedAt: time, width: 480, height: 640, bodies: [], polygons: [], advice: "fixture",
                            epoch: 1, people: people, evidence: evidence ?? SceneEvidence(generatedAt: time))
    }
    private func person(_ x: CGFloat = 0.2, height: CGFloat = 0.5) -> DetectedPerson {
        DetectedPerson(bounds: CGRect(x: x, y: 0.2, width: 0.2, height: height), faceCenter: nil, confidence: 0.9)
    }
    private func guide(evidence: SceneEvidence, people: [DetectedPerson] = []) -> LiveCompositionGuide {
        var engine = CompositionGuideEngine()
        return engine.update(snapshot(people: people, evidence: evidence), target: .automatic, now: 1)!.0
    }
    func testInvalidRasterIsRejected() {
        XCTAssertNil(ScenePhotometry.measure(rgba: [], side: 8))
        XCTAssertNil(ScenePhotometry.measure(rgba: [UInt8](repeating: 0, count: 4 * 129 * 129), side: 129))
    }
    func testUniformBlackAndWhiteHaveMeasuredRangesButNoInventedLines() {
        let black = raster { _, _ in 0 }, white = raster { _, _ in 255 }
        XCTAssertEqual(black.mean, 0); XCTAssertEqual(black.shadows, 1)
        XCTAssertEqual(white.mean, 1, accuracy: 0.00001); XCTAssertEqual(white.highlights, 1)
        XCTAssertEqual(white.edgeContrast, 0); XCTAssertTrue(white.lines().isEmpty)
    }
    func testTopLeftRasterRegionsAndBalanceAreNotVerticallyFlipped() throws {
        let photo = raster { x, y in x < 16 && y < 16 ? 255 : 0 }
        XCTAssertEqual(try XCTUnwrap(photo.brightness(in: CGRect(x: 0, y: 0, width: 0.5, height: 0.5))), 1, accuracy: 0.00001)
        XCTAssertEqual(photo.brightness(in: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)), 0)
        XCTAssertGreaterThan(photo.leftRightDifference, 0)
        XCTAssertGreaterThan(photo.topBottomDifference, 0)
        XCTAssertNil(photo.brightness(in: CGRect(x: 2, y: 2, width: 1, height: 1)))
    }
    func testHoughLinesAreBoundedMeasuredSegments() {
        let photo = raster { x, _ in x < 16 ? 0 : 255 }
        let lines = photo.lines()
        XCTAssertFalse(lines.isEmpty); XCTAssertLessThanOrEqual(lines.count, 6)
        for line in lines {
            XCTAssertTrue((0...1).contains(line.start.x)); XCTAssertTrue((0...1).contains(line.end.y))
        }
    }
    func testCatalogIsCompleteUniqueAndExplainsItsLimits() {
        XCTAssertEqual(CompositionRule.allCases.count, 29)
        XCTAssertEqual(Set(CompositionRule.allCases.map(\.id)).count, 29)
        for rule in CompositionRule.allCases { XCTAssertFalse(rule.title.isEmpty); XCTAssertFalse(rule.detail.isEmpty); XCTAssertGreaterThan(rule.tolerance, 0) }
        XCTAssertEqual(ShootingIntent.allCases.count, 7)
    }
    func testNoEvidenceFallsBackWithoutSemanticClaimsOrManualOnlyCandidates() {
        let candidates = SceneCompositionEngine.recommend(snapshot: snapshot(), intent: .balanced, mode: .photo, selected: nil)
        XCTAssertEqual(candidates.map(\.rule), [.center])
        XCTAssertTrue(candidates[0].reason.contains("근거 부족"))
        for intent in ShootingIntent.allCases {
            XCTAssertFalse(SceneCompositionEngine.recommend(snapshot: snapshot(), intent: intent, mode: .photo, selected: nil).contains { $0.rule.manualOnly })
        }
    }
    func testPeopleCountAndIntentChangeRecommendations() {
        let frame = snapshot(people: [person(), person(0.65)])
        XCTAssertEqual(SceneCompositionEngine.recommend(snapshot: frame, intent: .balanced, mode: .photo, selected: nil).first?.rule, .group)
        XCTAssertEqual(SceneCompositionEngine.recommend(snapshot: frame, intent: .background, mode: .photo, selected: nil).first?.rule, .portraitEnvironment)
        XCTAssertEqual(SceneCompositionEngine.recommend(snapshot: frame, intent: .person, mode: .photo, selected: nil).first?.rule, .portraitClose)
    }
    func testStaleGeometryCannotRecommendArchitectureOrLandscape() {
        let evidence = SceneEvidence(generatedAt: 1, horizonDegrees: 12, rectangles: [[.zero, CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]])
        let candidates = SceneCompositionEngine.recommend(snapshot: snapshot(3, evidence: evidence), intent: .balanced, mode: .photo, selected: nil)
        XCTAssertEqual(candidates.map(\.rule), [.center])
    }
    func testActualCaptureModesSelectLongAndVideoNotFictionalModes() {
        XCTAssertEqual(SceneCompositionEngine.recommend(snapshot: snapshot(), intent: .balanced, mode: .longExposure, selected: nil).first?.rule, .nightLong)
        XCTAssertEqual(SceneCompositionEngine.recommend(snapshot: snapshot(), intent: .cinematic, mode: .video, selected: nil).first?.rule, .video)
    }
    func testCinematicStillRecommendationUsesActualImageAspect() {
        let portrait = snapshot(people: [person()])
        let landscape = CompositionSnapshot(generatedAt: 1, width: 640, height: 480, bodies: [], polygons: [], advice: "fixture", people: [person()])
        XCTAssertFalse(SceneCompositionEngine.recommend(snapshot: portrait, intent: .cinematic, mode: .photo, selected: nil).contains { $0.rule == .golden })
        XCTAssertEqual(SceneCompositionEngine.recommend(snapshot: landscape, intent: .cinematic, mode: .photo, selected: nil).first?.rule, .golden)
    }
    func testParallelMeasurementsPermitRepetitionWithoutObjectClassification() {
        let lines = [0.2, 0.5, 0.8].map { x in SceneLine(start: CGPoint(x: x, y: 0), end: CGPoint(x: x, y: 1)) }
        let evidence = SceneEvidence(generatedAt: 1, lines: lines)
        XCTAssertTrue(SceneCompositionEngine.recommend(snapshot: snapshot(evidence: evidence), intent: .dynamic, mode: .photo, selected: nil).contains { $0.rule == .repetition })
    }
    func testLineIntersectionAndVerticalConvergenceAreGeometryOnly() throws {
        let evidence = SceneEvidence(generatedAt: 1, rectangles: [[CGPoint(x: 0.3, y: 0.1), CGPoint(x: 0.7, y: 0.1), CGPoint(x: 0.9, y: 0.9), CGPoint(x: 0.1, y: 0.9)]], lines: [SceneLine(start: .zero, end: CGPoint(x: 1, y: 1)), SceneLine(start: CGPoint(x: 1, y: 0), end: CGPoint(x: 0, y: 1))])
        XCTAssertEqual(try XCTUnwrap(evidence.intersection).x, 0.5, accuracy: 0.001)
        XCTAssertGreaterThan(try XCTUnwrap(evidence.verticalConvergence), 8)
    }
    func testManualRuleAppliesImmediatelyWithoutDetectionsOrFalseAlignment() throws {
        var engine = CompositionGuideEngine()
        let result = try XCTUnwrap(engine.update(snapshot(), target: .automatic, now: 1, rule: .spiral)).0
        XCTAssertEqual(result.rule, .spiral); XCTAssertFalse(result.aligned)
        XCTAssertNil(result.measuredPoint); XCTAssertNil(result.targetPoint)
    }
    func testAutomaticRuleNeedsPersistentEvidenceBeforeSwitching() throws {
        var engine = CompositionGuideEngine()
        XCTAssertEqual(engine.update(snapshot(), target: .automatic, now: 1, rule: .automatic)?.0.rule, .center)
        for time in [1.2, 1.4, 1.6, 1.8] {
            let frame = snapshot(time, people: [person(), person(0.65)])
            XCTAssertEqual(engine.update(frame, target: .automatic, now: time, rule: .automatic)?.0.rule, .center)
        }
        let result = engine.update(snapshot(2.01, people: [person(), person(0.65)]), target: .automatic, now: 2.01, rule: .automatic)
        XCTAssertEqual(try XCTUnwrap(result).0.rule, .group)
    }
    func testHorizonRequiresStableAlignmentAndDoesNotInventHeight() throws {
        var engine = CompositionGuideEngine()
        var aligned = false
        for time in [1.0, 1.2, 1.4, 1.6, 1.8] {
            let frame = snapshot(time, evidence: SceneEvidence(generatedAt: time, horizonDegrees: 0.5))
            let result = try XCTUnwrap(engine.update(frame, target: .automatic, now: time, rule: .landscape)).0
            XCTAssertNil(result.targetPoint); XCTAssertNil(result.targetBounds)
            aligned = result.aligned
        }
        XCTAssertTrue(aligned)
        let tilted = try XCTUnwrap(engine.update(snapshot(2, evidence: SceneEvidence(generatedAt: 2, horizonDegrees: 6)), target: .automatic, now: 2, rule: .landscape)).0
        XCTAssertFalse(tilted.aligned); XCTAssertTrue(tilted.advice.contains("높이는 미검출"))
    }
    func testChangedCropResetsCompletedAlignmentAndRejectsInvalidRegion() throws {
        var engine = CompositionGuideEngine()
        let p = DetectedPerson(bounds: CGRect(x: 0.23, y: 0.23, width: 0.2, height: 0.2), faceCenter: CGPoint(x: 1.0 / 3, y: 1.0 / 3), confidence: 0.9)
        var complete = false
        for t in [1.0, 1.2, 1.4, 1.6, 1.8] {
            complete = try XCTUnwrap(engine.update(snapshot(t, people: [p]), target: .left, now: t)).0.aligned
        }
        XCTAssertTrue(complete)
        let next = try XCTUnwrap(engine.update(snapshot(2, people: [p]), target: .left, now: 2, region: CGRect(x: 0.1, y: 0, width: 0.8, height: 1))).0
        XCTAssertFalse(next.aligned)
        XCTAssertNil(engine.update(snapshot(2.2, people: [p]), target: .left, now: 2.2, region: .zero))
    }
    func testStaleImageGeometryCannotProducePerspectiveAdvice() {
        let stale = SceneEvidence(generatedAt: -2, rectangles: [[CGPoint(x: 0.3, y: 0.1), CGPoint(x: 0.7, y: 0.1), CGPoint(x: 0.9, y: 0.9), CGPoint(x: 0.1, y: 0.9)]])
        var frame = guide(evidence: SceneEvidence(generatedAt: 1))
        frame.evidence = stale
        XCTAssertFalse(CameraCoachEngine.evaluate(guide: frame, intent: .balanced, camera: CoachCameraContext(), tilt: nil, now: 1).contains { $0.kind == .perspective })
    }
    func testSaliencyUsesMeasuredRegionWithoutNamingObject() throws {
        let evidence = SceneEvidence(generatedAt: 1, saliency: [CGRect(x: 0.1, y: 0.1, width: 0.1, height: 0.2)])
        let result = guide(evidence: evidence)
        XCTAssertEqual(try XCTUnwrap(result.measuredPoint).x, 0.15, accuracy: 0.0001)
        XCTAssertTrue(result.subjectLabel.contains("미분류")); XCTAssertTrue(result.subjects.isEmpty)
    }
    func testGroupUsesUnionButExplicitSelectionUsesSelectedPerson() throws {
        var engine = CompositionGuideEngine()
        let first = try XCTUnwrap(engine.update(snapshot(people: [person(), person(0.65)]), target: .automatic, now: 1, rule: .group)).0
        XCTAssertEqual(try XCTUnwrap(first.measuredBounds).width, 0.65, accuracy: 0.001)
        engine.select(first.subjects[0].id)
        let next = try XCTUnwrap(engine.update(snapshot(1.2, people: [person(), person(0.65)]), target: .automatic, now: 1.2, rule: .group)).0
        XCTAssertEqual(next.measuredBounds?.width, 0.2)
    }
    func testVisibleCropAndRuleAnchorStayInsideActualViewport() {
        let region = GuideGeometry.visibleRegion(image: CGSize(width: 4, height: 3), viewport: CGSize(width: 9, height: 16), fill: true)
        XCTAssertGreaterThan(region.minX, 0); XCTAssertLessThan(region.width, 1)
        for rule in CompositionRule.allCases {
            let point = SceneCompositionEngine.anchor(rule: rule, point: CGPoint(x: 0.5, y: 0.5), side: .left, region: region)
            XCTAssertTrue(region.contains(point))
        }
    }
    func testZoomIsBoundedAndRawNeverOffersAction() throws {
        var context = CoachCameraContext(lensID: "wide", maximumZoom: 1.5)
        let zoom = try XCTUnwrap(CameraCoachEngine.zoom(subjectHeight: 0.1, intent: .person, camera: context))
        XCTAssertEqual(zoom.factor, 1.5); XCTAssertNil(zoom.lensID)
        context.mode = .raw
        XCTAssertNil(CameraCoachEngine.zoom(subjectHeight: 0.1, intent: .person, camera: context))
        context.mode = .photo; context.maximumZoom = 0.5
        XCTAssertNil(CameraCoachEngine.zoom(subjectHeight: 0.1, intent: .person, camera: context))
    }
    func testOnlyAdvertisedOpticalLensIsOfferedAndVideoStaysDigital() throws {
        var context = CoachCameraContext(lensID: "wide", maximumZoom: 5, opticalLenses: [CoachLens(id: "tele", equivalent: 2)])
        XCTAssertEqual(CameraCoachEngine.zoom(subjectHeight: 0.35, intent: .person, camera: context)?.lensID, "tele")
        context.mode = .video
        let proposal = try XCTUnwrap(CameraCoachEngine.zoom(subjectHeight: 0.35, intent: .person, camera: context))
        XCTAssertNil(proposal.lensID); XCTAssertLessThanOrEqual(proposal.factor, 5)
    }
    func testExposureAdviceRespectsManualAndLockAndSensorClippingLimits() throws {
        let evidence = SceneEvidence(generatedAt: 1, photometry: raster { _, _ in 255 })
        let frame = guide(evidence: evidence)
        let automatic = CameraCoachEngine.evaluate(guide: frame, intent: .balanced, camera: CoachCameraContext(), tilt: nil, now: 1)
        XCTAssertEqual(automatic.first?.kind, .clipping); XCTAssertEqual(automatic.first?.exposureDirection, -0.3)
        for context in [CoachCameraContext(exposureManual: true), CoachCameraContext(exposureLocked: true)] {
            let advice = try XCTUnwrap(CameraCoachEngine.evaluate(guide: frame, intent: .balanced, camera: context, tilt: nil, now: 1).first)
            XCTAssertNil(advice.exposureDirection); XCTAssertTrue(advice.message.contains("자동 변경 안 함"))
        }
    }
    func testDarkAndBacklitAdviceComeFromActualSamples() {
        let black = guide(evidence: SceneEvidence(generatedAt: 1, photometry: raster { _, _ in 0 }))
        XCTAssertEqual(CameraCoachEngine.evaluate(guide: black, intent: .balanced, camera: CoachCameraContext(), tilt: nil, now: 1).first?.kind, .dark)
        let photo = raster { x, _ in x < 16 ? 25 : 210 }
        let backlit = guide(evidence: SceneEvidence(generatedAt: 1, photometry: photo), people: [person()])
        XCTAssertEqual(CameraCoachEngine.evaluate(guide: backlit, intent: .balanced, camera: CoachCameraContext(), tilt: nil, now: 1).first?.kind, .backlight)
    }
    func testManualZoomSnoozeAndStaleGuideSuppressProposals() {
        let frame = guide(evidence: SceneEvidence(generatedAt: 1), people: [person(height: 0.2)])
        let advice = CameraCoachEngine.evaluate(guide: frame, intent: .person, camera: CoachCameraContext(maximumZoom: 5, zoomSuppressed: true), tilt: nil, now: 1)
        XCTAssertFalse(advice.contains { $0.kind == .zoom })
        XCTAssertTrue(CameraCoachEngine.evaluate(guide: frame, intent: .person, camera: CoachCameraContext(maximumZoom: 5), tilt: nil, now: 2).isEmpty)
    }
    func testAdviceDwellImmediateRemovalAndCurrentActionPayload() {
        var stable = CoachAdviceStabilizer()
        let advice = CameraCoachAdvice(kind: .zoom, message: "first", priority: 1, zoom: CoachZoomProposal(factor: 2, lensID: nil, label: "digital"))
        XCTAssertTrue(stable.update([advice], at: 1).isEmpty)
        XCTAssertTrue(stable.update([advice], at: 1.4).isEmpty)
        let current = CameraCoachAdvice(kind: .zoom, message: "current", priority: 1, zoom: CoachZoomProposal(factor: 3, lensID: nil, label: "digital"))
        XCTAssertEqual(stable.update([current], at: 1.61).first?.zoom?.factor, 3)
        XCTAssertTrue(stable.update([], at: 1.8).isEmpty)
        XCTAssertTrue(stable.update([advice], at: 2).isEmpty)
        XCTAssertTrue(stable.update([advice], at: 3).isEmpty, "A stale gap must restart the dwell")
    }
    func testMotionOrientationFlatDeviceAndFreshness() throws {
        for (x, y, orientation) in [(0.0, -1.0, "portrait"), (-1.0, 0.0, "landscapeLeft"), (1.0, 0.0, "landscapeRight")] {
            let tilt = try XCTUnwrap(CameraTilt.measure(x: x, y: y, z: 0, orientation: orientation, time: 1))
            XCTAssertEqual(try XCTUnwrap(tilt.rollDegrees), 0, accuracy: 0.001)
            XCTAssertTrue(tilt.isFresh(at: 1.5)); XCTAssertFalse(tilt.isFresh(at: 0.9)); XCTAssertFalse(tilt.isFresh(at: 3))
        }
        XCTAssertNil(CameraTilt.measure(x: 0, y: 0, z: -1, orientation: "portrait", time: 1)?.rollDegrees)
        XCTAssertNil(CameraTilt.measure(x: .nan, y: 0, z: 0, orientation: "portrait", time: 1))
    }
    func testLocalPreferenceCountersAreBoundedAndNeverRecordAutomatic() throws {
        var learning = CompositionLearning()
        learning.record(intent: .person, rule: .automatic)
        XCTAssertTrue(learning.selections.isEmpty)
        for _ in 0..<1100 { learning.record(intent: .person, rule: .thirds) }
        XCTAssertEqual(learning.selections["person:thirds"], 1000)
        XCTAssertEqual(learning.bonus(intent: .person, rule: .thirds), 5)
        XCTAssertTrue(learning.valid)
        XCTAssertEqual(try JSONDecoder().decode(CompositionLearning.self, from: JSONEncoder().encode(learning)), learning)
        let invalid = try JSONDecoder().decode(CompositionLearning.self, from: Data("{\"version\":1,\"selections\":{\"face:name\":3}}".utf8))
        XCTAssertFalse(invalid.valid)
    }
}
