import XCTest
#if canImport(PhotoPImagePolicies)
@testable import PhotoPImagePolicies
#else
@testable import PhotoP
#endif

final class LookEffectAssessmentTests: XCTestCase {
    private func cube(swap: Bool = false, offset: Double = 0) throws -> CubeLUT {
        var lines = ["LUT_3D_SIZE 2"]
        for b in 0...1 { for g in 0...1 { for r in 0...1 {
            lines.append("\(Double(swap ? b : r) + offset) \(g) \(swap ? r : b)")
        } } }
        return try CubeLUT.parse(lines.joined(separator: "\n"))
    }
    func testIdentityWarnsWithoutChangingSourceTable() throws {
        let lut = try cube(), before = lut.values
        let result = try LookEffectAssessment.evaluate(lut, intensity: 1, grain: 0, spatial: false)
        XCTAssertEqual(result.meanChannelChange, 0)
        XCTAssertTrue(result.notice?.contains("변화가 작은") == true); XCTAssertEqual(lut.values, before)
    }
    func testVisibleSwapIsNotMisreportedAsIdentity() throws {
        let result = try LookEffectAssessment.evaluate(cube(swap: true), intensity: 1, grain: 0, spatial: false)
        XCTAssertGreaterThan(result.meanChannelChange, 0.1); XCTAssertNil(result.notice)
    }
    func testZeroStrengthAndSpatialCarrierAreDistinguished() throws {
        let lut = try cube(swap: true)
        XCTAssertTrue(try LookEffectAssessment.evaluate(lut, intensity: 0, grain: 0, spatial: false).notice?.contains("강도 0%") == true)
        XCTAssertTrue(try LookEffectAssessment.evaluate(lut, intensity: 0, grain: 0, spatial: true).notice?.contains("입자·공간") == true)
        XCTAssertTrue(try LookEffectAssessment.evaluate(lut, intensity: 0, grain: 0.2, spatial: false).notice?.contains("입자·공간") == true)
    }
    func testSmallColorChangeIsReportedWithoutForcedBoost() throws {
        let result = try LookEffectAssessment.evaluate(cube(offset: 0.001), intensity: 1, grain: 0, spatial: false)
        XCTAssertGreaterThan(result.meanChannelChange, 0); XCTAssertLessThan(result.meanChannelChange, 1.0 / 255)
        XCTAssertNotNil(result.notice)
    }
    func testInvalidSettingsAreRejected() throws {
        let lut = try cube()
        XCTAssertThrowsError(try LookEffectAssessment.evaluate(lut, intensity: .nan, grain: 0, spatial: false))
        XCTAssertThrowsError(try LookEffectAssessment.evaluate(lut, intensity: 1, grain: -1, spatial: false))
    }
}
