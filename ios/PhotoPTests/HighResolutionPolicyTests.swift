import XCTest
#if canImport(PhotoPImagePolicies)
@testable import PhotoPImagePolicies
#else
@testable import PhotoP
#endif

final class HighResolutionPolicyTests: XCTestCase {
    func test24And48MegapixelDimensionsRemainUnscaled() throws {
        for (w, h) in [(5712, 4284), (8064, 6048), (6048, 8064), (8000, 8000)] {
            let plan = try XCTUnwrap(HighResolutionPlan(width: w, height: h))
            XCTAssertEqual(plan.width, w); XCTAssertEqual(plan.height, h)
            XCTAssertEqual(plan.byteCount, w * h * 4)
            XCTAssertGreaterThan(plan.minimumFreeBytes, Int64(plan.byteCount))
        }
    }
    func testOverflowOversizeAndInvalidHaloRejectedBeforeAllocation() {
        for (w, h) in [(0, 1), (-1, 1), (Int.max, 2), (1, Int.max), (8001, 8000), (16385, 1)] {
            XCTAssertNil(HighResolutionPlan(width: w, height: h))
        }
        XCTAssertNil(HighResolutionPlan(width: 2, height: 2, halo: -1))
        XCTAssertNil(HighResolutionPlan(width: 2, height: 2, halo: 513))
    }
    func testOutputTilesCoverEveryPixelExactlyOnceIncludingOddEdges() throws {
        let plan = try XCTUnwrap(HighResolutionPlan(width: 2053, height: 1031, halo: 37))
        var pixels = [UInt8](repeating: 0, count: plan.width * plan.height)
        for tile in plan.tiles {
            XCTAssertLessThanOrEqual(tile.output.width, 1024); XCTAssertLessThanOrEqual(tile.output.height, 1024)
            XCTAssertLessThanOrEqual(tile.input.x, tile.output.x); XCTAssertGreaterThanOrEqual(tile.input.maxX, tile.output.maxX)
            XCTAssertLessThanOrEqual(tile.input.y, tile.output.y); XCTAssertGreaterThanOrEqual(tile.input.maxY, tile.output.maxY)
            XCTAssertGreaterThanOrEqual(tile.input.x, 0); XCTAssertLessThanOrEqual(tile.input.maxY, plan.height)
            for y in tile.output.y..<tile.output.maxY { for x in tile.output.x..<tile.output.maxX { pixels[y * plan.width + x] += 1 } }
        }
        XCTAssertTrue(pixels.allSatisfy { $0 == 1 })
    }
    func testTileWorkMemoryStaysBoundedAt48MP() throws {
        let halo = try XCTUnwrap(HighResolutionPlan.halo(longEdge: 8064, neighbours: true, chromaticAberration: 1, streak: true))
        XCTAssertEqual(halo, 128)
        let plan = try XCTUnwrap(HighResolutionPlan(width: 8064, height: 6048, halo: halo))
        XCTAssertEqual(plan.tiles.count, 48)
        for tile in plan.tiles { XCTAssertLessThanOrEqual(tile.input.width * tile.input.height * 4, 1280 * 1280 * 4) }
    }
    func testHaloCoversGlobalSpatialSampleOffsets() throws {
        for edge in [1, 1024, 4032, 8064, 16384] {
            let halo = try XCTUnwrap(HighResolutionPlan.halo(longEdge: edge, neighbours: true, chromaticAberration: 1, streak: true))
            let radius = max(1, Int((Double(edge) * 2 / 1024).rounded()))
            XCTAssertGreaterThanOrEqual(halo, radius * 8)
            XCTAssertGreaterThanOrEqual(halo, Int(ceil(Double(edge) * 0.006)))
            XCTAssertLessThanOrEqual(halo, 512)
        }
        XCTAssertEqual(HighResolutionPlan.halo(longEdge: 8064, neighbours: false, chromaticAberration: 0, streak: false), 0)
        XCTAssertNil(HighResolutionPlan.halo(longEdge: 8064, neighbours: true, chromaticAberration: .nan, streak: true))
    }
    func testHaloInputCopiesUseGlobalTopLeftCoordinatesAtImageEdges() throws {
        let plan = try XCTUnwrap(HighResolutionPlan(width: 1200, height: 1100, halo: 16))
        let last = try XCTUnwrap(plan.tiles.last)
        XCTAssertEqual(last.output, ImagePixelRegion(x: 1024, y: 1024, width: 176, height: 76))
        XCTAssertEqual(last.input, ImagePixelRegion(x: 1008, y: 1008, width: 192, height: 92))
        XCTAssertEqual(plan.height - last.input.maxY, 0, "CI crop bottom edge; output memory still starts at top")
    }
}
