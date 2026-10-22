import XCTest
import CoreGraphics
@testable import PhotoP

final class CameraRealtimeTests: XCTestCase {
    func testSliderUpdatesKeepTheFinalValueWhileAnOlderRequestIsInFlight() throws {
        var queue = PendingCameraSettings()
        var settings = CameraSettings()
        settings.focus.manual = true
        settings.focus.lensPosition = 0
        queue.offer(settings)
        let inFlight = try XCTUnwrap(queue.take())
        for index in 1...1000 {
            settings.focus.lensPosition = Double(index) / 1000
            queue.offer(settings)
        }
        XCTAssertEqual(inFlight.focus.lensPosition, 0)
        XCTAssertEqual(try XCTUnwrap(queue.take()).focus.lensPosition, 1)
        XCTAssertNil(queue.take(), "Only the newest pending request is needed after the device callback")
    }

    func testChangingFocusDoesNotReapplyExposureOrWhiteBalance() {
        let original = CameraSettings()
        var next = original
        next.focus.manual = true; next.focus.lensPosition = 0.7
        let delta = CameraSettingsDelta(previous: original, next: next)
        XCTAssertTrue(delta.focus); XCTAssertFalse(delta.exposure); XCTAssertFalse(delta.whiteBalance)
        let unchanged = CameraSettingsDelta(previous: next, next: next)
        XCTAssertFalse(unchanged.focus || unchanged.exposure || unchanged.whiteBalance)
        let initial = CameraSettingsDelta(previous: nil, next: next)
        XCTAssertTrue(initial.focus && initial.exposure && initial.whiteBalance)
    }

    func testLandscapeFramingAndCaptureRotationMatch() {
        XCTAssertEqual(CameraOrientation.portrait.rotationAngle, 90)
        XCTAssertEqual(CameraOrientation.landscapeRight.rotationAngle, 0)
        XCTAssertEqual(CameraOrientation.landscapeLeft.rotationAngle, 180)
        let image = CGRect(x: 0, y: 0, width: 400, height: 300)
        XCTAssertEqual(FramingAspect.native.rect(in: image), image)
        XCTAssertEqual(FramingAspect.square.rect(in: image), CGRect(x: 50, y: 0, width: 300, height: 300))
        let wide = FramingAspect.wide.rect(in: image)
        XCTAssertTrue(image.contains(wide))
        XCTAssertEqual(wide.width / wide.height, 16.0 / 9, accuracy: 0.001)
    }

    func testVideoFillAndGuideMappingUseTheSameCrop() {
        let fit = MetalPreviewDisplay.scale(inputAspect: 9.0 / 16, outputAspect: 3.0 / 4, fill: false)
        let fill = MetalPreviewDisplay.scale(inputAspect: 9.0 / 16, outputAspect: 3.0 / 4, fill: true)
        XCTAssertEqual(fit.x, 0.75, accuracy: 0.001); XCTAssertEqual(fit.y, 1)
        XCTAssertEqual(fill.x, 1); XCTAssertEqual(fill.y, 4.0 / 3, accuracy: 0.001)
        let viewport = CGSize(width: 300, height: 400)
        let imageRect = GuideGeometry.imageRect(image: CGSize(width: 900, height: 1600), viewport: viewport, fill: true)
        XCTAssertEqual(imageRect.width, 300)
        XCTAssertEqual(imageRect.height, 400 * CGFloat(fill.y), accuracy: 0.001)
        XCTAssertEqual(imageRect.midX, 150); XCTAssertEqual(imageRect.midY, 200)
    }
}
