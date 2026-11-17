import Foundation

// Preserve the existing decimal .cube representation and its hashes while
// bounding Objective-C temporaries to one blue plane instead of an entire LUT.
enum LUTTextEncoder {
    static func encode(dimension: Int, header: [String], decimalPlaces: Int,
                       sample: (SIMD3<Double>) throws -> SIMD3<Double>) throws -> Data {
        guard (2...65).contains(dimension), (1...12).contains(decimalPlaces),
              !header.isEmpty, header.count <= 32 else { throw CubeLUTError.invalid("LUT 생성 설정이 유효하지 않습니다.") }
        let text = header.joined(separator: "\n")
        guard text.utf8.count <= 65536 else { throw CubeLUTError.invalid("LUT 헤더가 너무 큽니다.") }
        let locale = Locale(identifier: "en_US_POSIX")
        let format = "%.\(decimalPlaces)f"
        let rowFormat = "\(format) \(format) \(format)"
        let denominator = Double(dimension - 1)
        var output = Data(text.utf8)
        output.reserveCapacity(min(CubeLUT.maximumFileBytes, dimension * dimension * dimension * 40 + output.count))
        for b in 0..<dimension {
            try Task.checkCancellation()
            let plane = try temporaryPool {
                var rows: [String] = []; rows.reserveCapacity(dimension * dimension)
                for g in 0..<dimension { for r in 0..<dimension {
                    let value = try sample(SIMD3(Double(r), Double(g), Double(b)) / denominator)
                    guard value.x.isFinite, value.y.isFinite, value.z.isFinite,
                          Float(value.x).isFinite, Float(value.y).isFinite, Float(value.z).isFinite else {
                        throw CubeLUTError.invalid("LUT 생성 결과가 유효하지 않습니다.")
                    }
                    rows.append(String(format: rowFormat, locale: locale, value.x, value.y, value.z))
                } }
                return Data(rows.joined(separator: "\n").utf8)
            }
            guard plane.count < CubeLUT.maximumFileBytes - output.count else { throw CubeLUTError.invalid("생성 LUT가 파일 크기 제한을 초과했습니다.") }
            output.append(10); output.append(plane)
        }
        return output
    }
    static func temporaryPool<T>(_ body: () throws -> T) rethrows -> T {
        #if canImport(ObjectiveC)
        return try autoreleasepool(invoking: body)
        #else
        return try body()
        #endif
    }
}
