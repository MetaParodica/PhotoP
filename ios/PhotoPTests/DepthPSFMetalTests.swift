import XCTest
import CoreImage
@testable import PhotoP

final class DepthPSFMetalTests: XCTestCase {
    func testMetalMatchesSpatialCPUReferenceInLinearLight() throws {
        let width = 31, height = 23
        let values: [SIMD3<Float>] = (0..<(width * height)).map { i in
            SIMD3(Float(i % width) / Float(width), Float(i / width) / Float(height), i % 7 == 0 ? 2 : 0.1)
        }
        var rgba = values.flatMap { [$0.x, $0.y, $0.z, Float(1)] }
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
        let image = CIImage(bitmapData: rgba.withUnsafeBytes { Data($0) }, bytesPerRow: width * 16,
            size: CGSize(width: width, height: height), format: .RGBAf, colorSpace: space)
        let context = CIContext(options: [.workingColorSpace: space, .cacheIntermediates: false])
        for profile in DepthLensProfile.allCases {
            let expected = try XCTUnwrap(DepthLensKernel.reference(values, width: width, height: height, radius: 4, profile: profile, aperture: 8))
            let output = try DepthLensFilter().blur(image, radius: 4, profile: profile, aperture: 8)
            rgba.withUnsafeMutableBytes { context.render(output, toBitmap: $0.baseAddress!, rowBytes: width * 16,
                bounds: image.extent, format: .RGBAf, colorSpace: space) }
            var worst: Float = 0
            for i in expected.indices {
                worst = max(worst, abs(rgba[4*i] - expected[i].x), abs(rgba[4*i+1] - expected[i].y), abs(rgba[4*i+2] - expected[i].z))
                XCTAssertEqual(rgba[4*i+3], 1, accuracy: 0.002)
            }
            XCTAssertLessThan(worst, 0.006, profile.rawValue)
        }
    }
    func testPremultipliedHighlightDoesNotDarkenWhenCoverageNormalizes() throws {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
        let context = CIContext(options: [.workingColorSpace: space])
        let extent = CGRect(x: 0, y: 0, width: 33, height: 33)
        let image = CIImage(color: CIColor(red: 4, green: 2, blue: 1, alpha: 0.25, colorSpace: space)).cropped(to: extent)
        let output = try DepthLensFilter().blur(image, radius: 4, profile: .classic, aperture: 8)
        var pixel = [Float](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { context.render(output, toBitmap: $0.baseAddress!, rowBytes: 16,
            bounds: CGRect(x: 16, y: 16, width: 1, height: 1), format: .RGBAf, colorSpace: space) }
        XCTAssertEqual(pixel[0] / pixel[3], 4, accuracy: 0.02)
        XCTAssertEqual(pixel[1] / pixel[3], 2, accuracy: 0.02)
        XCTAssertEqual(pixel[3], 0.25, accuracy: 0.002)
    }
}
