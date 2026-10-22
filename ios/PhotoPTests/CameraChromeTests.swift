import XCTest
@testable import PhotoP

final class CameraChromeTests: XCTestCase {
    func testLogarithmicControlMatchesGeometricStopsAndRoundTrips() {
        XCTAssertEqual(CameraControlScale.value(0.5, range: 100...1600, logarithmic: true), 400, accuracy: 0.00001)
        for t in stride(from: 0.0, through: 1, by: 0.05) {
            let seconds = CameraControlScale.value(t, range: (1.0 / 8000)...30, logarithmic: true)
            XCTAssertEqual(CameraControlScale.unit(seconds, range: (1.0 / 8000)...30, logarithmic: true), t, accuracy: 0.00001)
        }
    }
    func testLinearEVAndDegenerateHardwareRange() {
        XCTAssertEqual(CameraControlScale.value(0.5, range: -3...3, logarithmic: false), 0)
        XCTAssertEqual(CameraControlScale.unit(50, range: 50...50, logarithmic: true), 0)
        XCTAssertEqual(CameraControlScale.value(1, range: 50...50, logarithmic: true), 50)
        XCTAssertEqual(CameraControlScale.value(-1, range: 50...1600, logarithmic: true), 50)
        XCTAssertEqual(CameraControlScale.value(2, range: 50...1600, logarithmic: true), 1600)
    }
    func testShutterDisplayAndToolIdentity() {
        XCTAssertEqual(CameraControlScale.shutter(1.0 / 125), "1/125")
        XCTAssertEqual(CameraControlScale.shutter(2), "2.0 s")
        XCTAssertEqual(CameraControlScale.shutter(0), "—")
        XCTAssertEqual(Set(CameraTool.allCases.map(\.id)).count, 12)
    }
}
