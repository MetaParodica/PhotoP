import XCTest
#if canImport(PhotoPImagePolicies)
@testable import PhotoPImagePolicies
#else
@testable import PhotoP
#endif

final class LiveLookPolicyTests: XCTestCase {
    func testSelectedLookNeedsPreviewWithoutAnyAnalysisTool() {
        XCTAssertTrue(LiveLookPolicy.needsOutput(selected: true, monitoring: false, guide: false, focusAssist: false, samples: false))
        XCTAssertFalse(LiveLookPolicy.needsOutput(selected: false, monitoring: false, guide: false, focusAssist: false, samples: false))
    }
    func testRemovingLookStillPreservesAnalysisOutput() {
        for flags in [[true, false, false, false], [false, true, false, false], [false, false, true, false], [false, false, false, true]] {
            XCTAssertTrue(LiveLookPolicy.needsOutput(selected: false, monitoring: flags[0], guide: flags[1], focusAssist: flags[2], samples: flags[3]))
        }
    }
    func testComparisonChangesDisplayPolicyNotSelection() {
        XCTAssertTrue(LiveLookPolicy.gradesFrame(selected: true, comparingOriginal: false))
        XCTAssertFalse(LiveLookPolicy.gradesFrame(selected: true, comparingOriginal: true))
        XCTAssertFalse(LiveLookPolicy.gradesFrame(selected: false, comparingOriginal: false))
        XCTAssertFalse(LiveLookPolicy.gradesFrame(selected: false, comparingOriginal: true))
    }
    func testOriginalComparisonKeepsOutputAvailableForInstantReturn() {
        XCTAssertFalse(LiveLookPolicy.gradesFrame(selected: true, comparingOriginal: true))
        XCTAssertTrue(LiveLookPolicy.needsOutput(selected: true, monitoring: false, guide: false, focusAssist: false, samples: false))
    }
    func testNewSelectionWaitsForItsOwnProcessor() {
        var generation = PreviewLookGeneration()
        XCTAssertTrue(generation.ready)
        let first = generation.request(); XCTAssertFalse(generation.ready)
        XCTAssertTrue(generation.install(first)); XCTAssertTrue(generation.ready)
        let second = generation.request(); XCTAssertFalse(generation.ready)
        XCTAssertFalse(generation.install(first)); XCTAssertFalse(generation.ready)
        XCTAssertTrue(generation.install(second)); XCTAssertTrue(generation.ready)
    }
    func testRapidRequestsCannotPublishObsoleteLook() {
        var generation = PreviewLookGeneration()
        let requests = (0..<100).map { _ in generation.request() }
        for version in requests.dropLast() { XCTAssertFalse(generation.install(version)); XCTAssertFalse(generation.ready) }
        XCTAssertTrue(generation.install(requests.last!)); XCTAssertTrue(generation.ready)
    }
}
