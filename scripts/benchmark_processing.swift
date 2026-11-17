import Foundation

// Build with the portable production sources (command in docs/30). These CPU
// microbenchmarks are not iPhone frame rate, ANE, thermal or camera measurements.
@main struct ProcessingBenchmark {
    static func timed<T>(_ body: () throws -> T) rethrows -> (T, Double) {
        let start = ProcessInfo.processInfo.systemUptime
        let value = try body()
        return (value, ProcessInfo.processInfo.systemUptime - start)
    }
    static func color(_ c: SIMD3<Double>) -> SIMD3<Double> { SIMD3(c.z * 0.8, c.y * 0.9, c.x * 0.7) }
    static func main() throws {
        let n = Int(CommandLine.arguments.dropFirst().first ?? "33") ?? 33
        guard [17, 33, 65].contains(n) else { throw CocoaError(.coderInvalidValue) }
        let header = ["TITLE \"Benchmark\"", "LUT_3D_SIZE \(n)"]
        let legacy = timed { () -> Data in
            var rows = header
            for b in 0..<n { for g in 0..<n { for r in 0..<n {
                let c = color(SIMD3(Double(r), Double(g), Double(b)) / Double(n - 1))
                rows.append(String(format: "%.7f %.7f %.7f", locale: Locale(identifier: "en_US_POSIX"), c.x, c.y, c.z))
            } } }
            return Data(rows.joined(separator: "\n").utf8)
        }
        let optimized = try timed { try LUTTextEncoder.encode(dimension: n, header: header, decimalPlaces: 7, sample: color) }
        guard optimized.0 == legacy.0 else { throw CocoaError(.coderInvalidValue) }
        let parsed = try timed { try CubeLUT.parse(String(decoding: optimized.0, as: UTF8.self)) }
        let binary = try LUTBinaryCodec.encode(parsed.0)
        let loaded = try timed { try LUTBinaryCodec.decode(binary) }
        guard loaded.0.values == parsed.0.values else { throw CocoaError(.coderInvalidValue) }
        let values: [Float] = (0..<(160 * 120)).map { Float(($0 * 7919) % 65521 + 1) / 1000 }
        let field = SoftwareDepthField(width: 160, height: 120, inverseDepth: values, units: .relativeInverse)!
        let oldRange = timed { () -> Double in
            var checksum = 0.0
            for iteration in 0..<120 {
                let data = values.enumerated().map { ($0.offset + iteration) % 29 == 0 ? Float(0) : $0.element }
                // The former analyzer + renderer each sorted the valid field.
                for _ in 0..<2 {
                    let sorted = data.filter { $0 > 0 }.sorted()
                    checksum += Double(sorted[Int(Double(sorted.count - 1) * 0.98)])
                }
            }
            return checksum
        }
        let newRange = timed { () -> Double in
            var checksum = 0.0
            for iteration in 0..<120 {
                let current = field.invalidating { ($0 + iteration) % 29 == 0 }!
                checksum += Double(current.bounds!.upper) * 2
            }
            return checksum
        }
        let report: [String: Any] = [
            "scope": "CPU microbenchmark; not iPhone/ANE or end-to-end preview measurements",
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "dimension": n, "lutBytesIdentical": true, "runtimeTableIdentical": true,
            "legacyGenerationSeconds": legacy.1, "boundedGenerationSeconds": optimized.1,
            "textParseSeconds": parsed.1, "binaryDecodeSeconds": loaded.1,
            "legacyTwoQuantiles120FramesSeconds": oldRange.1, "cachedRange120FramesSeconds": newRange.1,
            "legacyChecksum": oldRange.0, "cachedChecksum": newRange.0
        ]
        let bytes = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: bytes, as: UTF8.self))
    }
}
