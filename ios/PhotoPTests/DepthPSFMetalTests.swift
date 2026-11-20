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
            print("PSF MetalCPU maxabs \(profile.rawValue)=\(worst)")
            XCTAssertLessThan(worst, 0.006, profile.rawValue)
        }
    }
    func testPremultipliedHighlightDoesNotDarkenWhenCoverageNormalizes() throws {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
        let context = CIContext(options: [.workingColorSpace: space])
        let extent = CGRect(x: 0, y: 0, width: 33, height: 33)
        let image = CIImage(color: try XCTUnwrap(CIColor(red: 4, green: 2, blue: 1, alpha: 0.25, colorSpace: space))).cropped(to: extent)
        let output = try DepthLensFilter().blur(image, radius: 4, profile: .classic, aperture: 8)
        var pixel = [Float](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { context.render(output, toBitmap: $0.baseAddress!, rowBytes: 16,
            bounds: CGRect(x: 16, y: 16, width: 1, height: 1), format: .RGBAf, colorSpace: space) }
        XCTAssertEqual(pixel[0] / pixel[3], 4, accuracy: 0.02)
        XCTAssertEqual(pixel[1] / pixel[3], 2, accuracy: 0.02)
        XCTAssertEqual(pixel[3], 0.25, accuracy: 0.002)
    }
    func testBoundedBackgroundExtensionRejectsForegroundColorContamination() throws {
        let extent = CGRect(x: 0, y: 0, width: 64, height: 16)
        let blue = CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(to: extent)
        let red = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(x: 32, y: 0, width: 32, height: 16))
        let color = red.composited(over: blue)
        let far = CIImage(color: CIColor(red: 0.2, green: 0.2, blue: 0.2)).cropped(to: extent)
        let near = CIImage(color: CIColor(red: 0.8, green: 0.8, blue: 0.8)).cropped(to: CGRect(x: 32, y: 0, width: 32, height: 16))
        let valid = CIImage(color: .white).cropped(to: extent)
        let output = try DepthBackgroundExtension().image(color: color, coordinates: near.composited(over: far), validity: valid, radius: 8)
        let context = CIContext(), space = CGColorSpace(name: CGColorSpace.sRGB)!
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { context.render(output, toBitmap: $0.baseAddress!, rowBytes: 4,
            bounds: CGRect(x: 34, y: 8, width: 1, height: 1), format: .RGBA8, colorSpace: space) }
        XCTAssertLessThan(pixel[0], 3, "Nearby far samples must exclude red foreground")
        XCTAssertGreaterThan(pixel[2], 250)
        pixel.withUnsafeMutableBytes { context.render(output, toBitmap: $0.baseAddress!, rowBytes: 4,
            bounds: CGRect(x: 60, y: 8, width: 1, height: 1), format: .RGBA8, colorSpace: space) }
        XCTAssertGreaterThan(pixel[0], 250, "Unsupported hidden background retains observed pixels")
    }

}
