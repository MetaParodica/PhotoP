import XCTest
import Metal
@testable import PhotoP

final class PreviewBudgetTests: XCTestCase {
    func testDepthBudgetDoesNotReduceLUTOnlyOrTrackingBudget() {
        let lut = PreviewBudget(thermal: .nominal, lowPower: false)
        let depth = PreviewBudget(thermal: .nominal, lowPower: false, depthEnabled: true)
        XCTAssertEqual(lut.maximumDimension, 1024); XCTAssertEqual(lut.framesPerSecond, 60)
        XCTAssertEqual(depth.maximumDimension, 720); XCTAssertEqual(depth.framesPerSecond, 30)
        XCTAssertEqual(depth.compositionInterval, lut.compositionInterval)
        XCTAssertEqual(depth.analysisInterval, 0.5)
        let serious = PreviewBudget(thermal: .serious, lowPower: false, depthEnabled: true)
        XCTAssertEqual(serious.maximumDimension, 480); XCTAssertEqual(serious.framesPerSecond, 15)
        let critical = PreviewBudget(thermal: .critical, lowPower: false, depthEnabled: true)
        XCTAssertFalse(critical.allowsDepthEffects)
        XCTAssertFalse(critical.analysisInterval.isFinite)
    }

    func testThermalAndLowPowerBudgetsBoundPixelsAndAnalysis() {
        let nominal = PreviewBudget(thermal: .nominal, lowPower: false)
        let low = PreviewBudget(thermal: .nominal, lowPower: true)
        let serious = PreviewBudget(thermal: .serious, lowPower: false)
        let critical = PreviewBudget(thermal: .critical, lowPower: false)
        XCTAssertEqual(nominal.maximumDimension, 1024); XCTAssertEqual(nominal.framesPerSecond, 60)
        XCTAssertEqual(low.maximumDimension, 720); XCTAssertEqual(low.framesPerSecond, 30)
        XCTAssertEqual(serious.framesPerSecond, 20); XCTAssertEqual(serious.analysisInterval, 1)
        XCTAssertEqual(critical.maximumDimension, 480); XCTAssertEqual(critical.framesPerSecond, 10)
        XCTAssertFalse(critical.analysisInterval.isFinite)
        XCTAssertLessThan(Double(serious.maximumDimension * serious.maximumDimension) * serious.framesPerSecond,
                          Double(nominal.maximumDimension * nominal.maximumDimension) * nominal.framesPerSecond / 5)
    }
    func testBudgetRejectsEarlyInvalidAndBackwardsTimes() {
        let budget = PreviewBudget(thermal: .critical, lowPower: false)
        XCTAssertTrue(budget.admits(time: 1, after: -.infinity))
        XCTAssertFalse(budget.admits(time: 1.05, after: 1))
        XCTAssertTrue(budget.admits(time: 1.11, after: 1))
        XCTAssertFalse(budget.admits(time: 0.9, after: 1))
        XCTAssertFalse(budget.admits(time: .nan, after: 1))
    }
    func testComputeStatesAreSharedAcrossRendererConstruction() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("Metal unavailable") }
        let cache = MetalPipelineCache()
        let a = try cache.compute("photoPLUT", device: device)
        let b = try cache.compute("photoPLUT", device: device)
        let c = try cache.compute("photoPLUTTexture", device: device)
        XCTAssertTrue(a === b); XCTAssertFalse(a === c)
        XCTAssertThrowsError(try cache.compute("missing_shader", device: device))
    }
}
