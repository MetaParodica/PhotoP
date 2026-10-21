import XCTest
@testable import PhotoP

final class CompositionGuideTests: XCTestCase {
    func testVisionOriginMirrorAndLetterboxMapping() {
        let rect = GuideGeometry.imageRect(image: CGSize(width: 160, height: 90), viewport: CGSize(width: 300, height: 400))
        XCTAssertEqual(rect.width, 300); XCTAssertEqual(rect.height, 168.75)
        let topLeft = GuideGeometry.point(CGPoint(x: 0, y: 1), in: rect, vision: true)
        XCTAssertEqual(topLeft.x, 0); XCTAssertEqual(topLeft.y, 115.625)
        let mirrored = GuideGeometry.point(CGPoint(x: 0.2, y: 0.7), in: rect, vision: true, mirror: true)
        XCTAssertEqual(mirrored.x, 240); XCTAssertEqual(mirrored.y, 166.25)
        let portrait = GuideGeometry.imageRect(image: CGSize(width: 90, height: 160), viewport: CGSize(width: 400, height: 300))
        XCTAssertEqual(portrait.height, 300); XCTAssertEqual(portrait.minX, 115.625)
        XCTAssertEqual(GuideGeometry.imageRect(image: .zero, viewport: CGSize(width: 300, height: 400)), .zero)
    }
    func testStaleAndFutureAdviceAreHidden() {
        let s = CompositionSnapshot(generatedAt: 10, width: 10, height: 10, bodies: [], polygons: [], advice: "fixture")
        XCTAssertTrue(s.isFresh(at: 11)); XCTAssertFalse(s.isFresh(at: 12)); XCTAssertFalse(s.isFresh(at: 9))
    }
    func testPoseTargetsStayInImageAndHaveExpectedPersonCounts() {
        XCTAssertTrue(PoseTemplate.off.targets.isEmpty)
        XCTAssertEqual(PoseTemplate.pair.targets.count, 2); XCTAssertEqual(PoseTemplate.group.targets.count, 3)
        for pose in PoseTemplate.allCases { for body in pose.targets { for p in body.values {
            XCTAssertTrue((0...1).contains(p.x)); XCTAssertTrue((0...1).contains(p.y))
        } } }
    }
    func testPortraitAdviceUsesObservedHeadroomFeetAndMultiplePeople() {
        XCTAssertTrue(GuideGeometry.portraitAdvice([]).contains("없습니다"))
        XCTAssertTrue(GuideGeometry.portraitAdvice([["nose": CGPoint(x: 0.5, y: 0.95)]]).contains("머리"))
        XCTAssertTrue(GuideGeometry.portraitAdvice([["la": CGPoint(x: 0.5, y: 0.01)]]).contains("발 아래"))
        XCTAssertTrue(GuideGeometry.portraitAdvice([[:], [:]]).contains("여러 인물"))
    }
    func testLifecycleInvalidationRejectsOldAISnapshot() {
        let analyzer = CompositionAnalyzer { _ in }
        analyzer.configure(enabled: true, scene: .portrait); analyzer.setRunning(true)
        let s = CompositionSnapshot(generatedAt: 1, width: 10, height: 10, bodies: [], polygons: [], advice: "not published")
        XCTAssertFalse(analyzer.isCurrent(s)); analyzer.setRunning(false); XCTAssertFalse(analyzer.isCurrent(s))
    }
}
