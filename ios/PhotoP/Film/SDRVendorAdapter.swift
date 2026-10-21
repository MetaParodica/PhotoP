import Foundation

// Display-referred approximation: does not recover scene HDR or a camera sensor.
enum SDRVendorAdapter {
    static let version = "sdr-vlog-bt1886-v1"
    static func decodeSRGB(_ x: Double) -> Double { x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
    static func encodeSRGB(_ x: Double) -> Double { x <= 0.0031308 ? x * 12.92 : 1.055 * pow(x, 1 / 2.4) - 0.055 }
    static func encodeVLog(_ x: Double) -> Double { x < 0.01 ? 5.6 * x + 0.125 : 0.241514 * log10(x + 0.00873) + 0.598206 }
    static func input(_ encoded: SIMD3<Double>) -> SIMD3<Double> {
        let v = SIMD3(decodeSRGB(encoded.x), decodeSRGB(encoded.y), decodeSRGB(encoded.z))
        // XYZ D65 sRGB -> Panasonic V-Gamut; rounded vendor inverse matrix.
        let r = v.x * 0.5851963399193534 + v.y * 0.322642032102744 + v.z * 0.09216216566787247
        let g = v.x * 0.07858844472927166 + v.y * 0.8196268119624732 + v.z * 0.10178458312588415
        let b = v.x * 0.02279401865537123 + v.y * 0.11421672901128323 + v.z * 0.8629883094762028
        return .init(encodeVLog(r), encodeVLog(g), encodeVLog(b))
    }
    static func sample(_ encoded: SIMD3<Double>, source: CubeLUT) throws -> SIMD3<Double> {
        let native = try source.sample(input(encoded))
        var output = SIMD3<Double>()
        for c in 0..<3 { output[c] = min(max(encodeSRGB(pow(min(max(native[c], 0), 1), 2.4)), 0), 1) }
        return output
    }
    static func bake(_ source: CubeLUT, dimension: Int = 65, sourceSHA256: String) throws -> Data {
        guard [17, 33, 65].contains(dimension), !source.isOneDimensional else { throw CameraError.invalidPhotoData }
        var lines = ["TITLE \"PhotoP SDR vendor adaptation v1\"", "# Source SHA256: \(sourceSHA256)", "# \(version); display-referred approximation; Rec.709 gamma2.4 assumed", "LUT_3D_SIZE \(dimension)"]
        lines.reserveCapacity(dimension * dimension * dimension + 4)
        for b in 0..<dimension {
            try Task.checkCancellation()
            for g in 0..<dimension { for r in 0..<dimension {
                let value = try sample(SIMD3(Double(r), Double(g), Double(b)) / Double(dimension - 1), source: source)
                lines.append(String(format: "%.8f %.8f %.8f", locale: Locale(identifier: "en_US_POSIX"), value.x, value.y, value.z))
            } }
        }
        return Data(lines.joined(separator: "\n").utf8)
    }
}
