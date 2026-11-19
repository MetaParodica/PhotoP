import XCTest
#if canImport(PhotoPImagePolicies)
@testable import PhotoPImagePolicies
#else
@testable import PhotoP
#endif

final class SubjectVideoDepthPolicyTests: XCTestCase {
    let box = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
    func testHysteresisFreshnessAndLostTargetRequiresNewSelection() {
        var state = SubjectTrackingState()
        let selection = SubjectTrackingSelection(point: CGPoint(x: 0.5, y: 0.5))
        state.configure(enabled: true, selection: selection, generation: 4)
        XCTAssertTrue(state.observe(bounds: box, confidence: 0.9, time: 1, generation: 4))
        XCTAssertNil(state.snapshot(at: 1).focus(at: 1))
        XCTAssertTrue(state.observe(bounds: box, confidence: 0.9, time: 1.1, generation: 4))
        XCTAssertNotNil(state.snapshot(at: 1.2).focus(at: 1.2))
        XCTAssertNil(state.snapshot(at: 1.6).focus(at: 1.6))
        XCTAssertFalse(state.observe(bounds: box, confidence: 0.1, time: 2, generation: 4))
        XCTAssertEqual(state.snapshot(at: 2).phase, .lost)
        XCTAssertFalse(state.observe(bounds: box, confidence: 1, time: 2.1, generation: 4))
        state.configure(enabled: true, selection: SubjectTrackingSelection(point: selection.point), generation: 4)
        XCTAssertTrue(state.observe(bounds: box, confidence: 1, time: 2.2, generation: 4))
    }
    func testRejectStaleGenerationTimeAndIdentityJump() {
        var state = SubjectTrackingState()
        state.configure(enabled: true, selection: .init(point: CGPoint(x: 0.5, y: 0.5)), generation: 2)
        XCTAssertFalse(state.observe(bounds: box, confidence: 1, time: 1, generation: 1))
        XCTAssertTrue(state.observe(bounds: box, confidence: 1, time: 1, generation: 2))
        XCTAssertFalse(state.observe(bounds: box, confidence: 1, time: 0.9, generation: 2))
        XCTAssertFalse(state.observe(bounds: CGRect(x: 0, y: 0, width: 0.1, height: 0.1), confidence: 1, time: 1.1, generation: 2))
        XCTAssertNil(state.snapshot(at: 1.1).focus(at: 1.1))
        XCTAssertEqual(SubjectAssociation.cost(overlap: 0.8, confidence: 0.5)!, 0.6, accuracy: 0.00001)
        XCTAssertNil(SubjectAssociation.cost(overlap: .nan, confidence: 1))
    }
    func testTrackingRequirementAndAcquisitionTimeoutAreExplicit() {
        var state = SubjectTrackingState()
        state.configure(enabled: true, selection: .init(point: CGPoint(x: 0.5,y: 0.5)), generation: 1)
        _ = state.observe(bounds: nil, confidence: 0, time: 1, generation: 1)
        _ = state.observe(bounds: nil, confidence: 0, time: 2, generation: 1)
        XCTAssertEqual(state.snapshot(at: 2).phase, .lost)
        var intent = VideoDepthIntent(keyframes: [.init(time: 0, focus: CGPoint(x: 0.5,y: 0.5), aperture: 2.8, profile: .natural)])
        XCTAssertTrue(intent.append(.init(time: 1, focus: CGPoint(x: 0.5,y: 0.5), aperture: 2.8, profile: .natural, requiresTracking: true)))
        XCTAssertEqual(intent.keyframes.count, 2)
        XCTAssertEqual(intent.parameters(at: 1)?.requiresTracking, true)
        XCTAssertNil(intent.parameters(at: 1)?.selection)
    }
    func testTimelineDoesNotAnticipateTapsOrCoalesceInitialState() throws {
        let initial = VideoDepthKeyframe(time: 0, focus: CGPoint(x: 0.5, y: 0.5), aperture: 2.8, profile: .natural)
        var intent = VideoDepthIntent(keyframes: [initial])
        var dial = initial; dial = .init(time: 0.02, focus: initial.focus, aperture: 4, profile: .natural)
        XCTAssertTrue(intent.append(dial)); XCTAssertEqual(intent.keyframes.count, 2)
        XCTAssertTrue(intent.append(.init(time: 0.04, focus: initial.focus, aperture: 5.6, profile: .natural)))
        XCTAssertEqual(intent.keyframes.count, 2); XCTAssertEqual(intent.parameters(at: 0)?.aperture, 2.8)
        let selection = SubjectTrackingSelection(point: CGPoint(x: 0.3, y: 0.3))
        XCTAssertTrue(intent.append(.init(time: 0.06, focus: selection.point, aperture: 5.6, profile: .natural, selection: selection)))
        XCTAssertNil(intent.parameters(at: 0.05)?.selection)
        XCTAssertEqual(intent.parameters(at: 0.06)?.selection?.id, selection.id)
        XCTAssertEqual(try JSONDecoder().decode(VideoDepthIntent.self, from: JSONEncoder().encode(intent)), intent)
        intent.keyframes.reverse(); XCTAssertFalse(intent.valid)
    }
    func testFrontPreviewAndOrientationMapIntoUnmirroredRecording() {
        let point = CGPoint(x: 0.2, y: 0.3)
        XCTAssertEqual(VideoDepthPolicy.recordedPoint(point, mirrored: true, previewAngle: 90, recordingAngle: 90), CGPoint(x: 0.8, y: 0.3))
        let rotated = VideoDepthPolicy.recordedPoint(point, mirrored: false, previewAngle: 0, recordingAngle: 90)!
        XCTAssertEqual(rotated.x, 0.7, accuracy: 0.00001); XCTAssertEqual(rotated.y, 0.2, accuracy: 0.00001)
        let back = VideoDepthPolicy.recordedPoint(rotated, mirrored: false, previewAngle: 90, recordingAngle: 0)!
        XCTAssertEqual(back.x, point.x, accuracy: 0.00001); XCTAssertEqual(back.y, point.y, accuracy: 0.00001)
        XCTAssertNil(VideoDepthPolicy.recordedPoint(point, mirrored: false, previewAngle: 12, recordingAngle: 90))
    }
    func testQualityAndOrientationContracts() {
        XCTAssertTrue(VideoDepthPolicy.supports(width: 2160, height: 3840, fps: 60, duration: 600))
        XCTAssertFalse(VideoDepthPolicy.supports(width: 7680, height: 4320, fps: 30, duration: 1))
        XCTAssertFalse(VideoDepthPolicy.supports(width: 1921, height: 1080, fps: .nan, duration: 1))
        XCTAssertEqual(VideoDepthPolicy.bitrate(width: 1920, height: 1080, fps: 30, original: 40_000_000, hevc: true), 40_000_000)
        XCTAssertEqual(VideoDepthPolicy.coreImageTransform(a: 0,b: 1,c: -1,d: 0,tx: 1080,ty: 0,inputHeight: 1080,outputHeight: 1920), [0,-1,1,0,0,1920])
        XCTAssertNil(VideoDepthPolicy.coreImageTransform(a: 2,b: 0,c: 0,d: 1,tx: 0,ty: 0,inputHeight: 100,outputHeight: 100))
    }
}
