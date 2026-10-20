import Foundation

struct CubeLUT: Sendable {
    static let maximumFileBytes = 32 * 1024 * 1024
    let title: String?
    let dimension: Int
    let domainMin: SIMD3<Double>
    let domainMax: SIMD3<Double>
    // Iridas cube ordering: red varies fastest, followed by green, then blue.
    let values: [SIMD3<Double>]

    private init(title: String?, dimension: Int, domainMin: SIMD3<Double>,
                 domainMax: SIMD3<Double>, values: [SIMD3<Double>]) {
        self.title = title
        self.dimension = dimension
        self.domainMin = domainMin
        self.domainMax = domainMax
        self.values = values
    }

    static func parse(_ text: String) throws -> CubeLUT {
        guard text.utf8.count <= maximumFileBytes else { throw CubeLUTError.invalid("LUT 파일은 32MB 이하여야 합니다.") }
        var title: String?
        var size: Int?
        var minimum = SIMD3<Double>(repeating: 0)
        var maximum = SIMD3<Double>(repeating: 1)
        var seen: Set<String> = []
        var values: [SIMD3<Double>] = []

        // CRLF is one Swift Character; normalize before splitting on LF.
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        for (index, raw) in normalized.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            guard raw.utf8.count <= 4096 else { throw CubeLUTError.invalid("\(index + 1)행이 너무 깁니다.") }
            let line = withoutComment(String(raw)).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            let tokens = line.split(whereSeparator: { $0.isWhitespace })
            let key = String(tokens[0])
            func fail(_ reason: String) -> CubeLUTError { .invalid("\(index + 1)행: \(reason)") }
            if ["TITLE", "LUT_3D_SIZE", "DOMAIN_MIN", "DOMAIN_MAX"].contains(key) {
                guard values.isEmpty, seen.insert(key).inserted else { throw fail("중복되거나 데이터 뒤에 놓인 헤더입니다.") }
                switch key {
                case "TITLE":
                    let name = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                    guard name.count >= 2, name.first == "\"", name.last == "\"",
                          !name.dropFirst().dropLast().contains("\"") else { throw fail("TITLE은 따옴표로 감싸야 합니다.") }
                    title = String(name.dropFirst().dropLast())
                case "LUT_3D_SIZE":
                    guard tokens.count == 2, let dimension = Int(tokens[1]), (2...65).contains(dimension)
                    else { throw fail("3D LUT 크기는 2~65여야 합니다.") }
                    size = dimension
                    values.reserveCapacity(dimension * dimension * dimension)
                case "DOMAIN_MIN": minimum = try vector(Array(tokens.dropFirst()), line: index + 1)
                default: maximum = try vector(Array(tokens.dropFirst()), line: index + 1)
                }
            } else {
                guard let size else { throw fail("지원되는 LUT_3D_SIZE 헤더가 필요합니다. 1D/shaper LUT는 아직 지원하지 않습니다.") }
                guard values.count < size * size * size else { throw fail("LUT 데이터가 선언한 크기보다 많습니다.") }
                values.append(try vector(tokens, line: index + 1))
            }
        }
        guard let size, values.count == size * size * size else { throw CubeLUTError.invalid("LUT 데이터 행 수가 선언한 크기와 다릅니다.") }
        for channel in 0..<3 {
            guard maximum[channel] > minimum[channel], Float(maximum[channel]) > Float(minimum[channel])
            else { throw CubeLUTError.invalid("DOMAIN_MAX는 각 채널에서 DOMAIN_MIN보다 커야 합니다.") }
        }
        return CubeLUT(title: title, dimension: size, domainMin: minimum, domainMax: maximum, values: values)
    }

    private static func vector(_ tokens: [Substring], line: Int) throws -> SIMD3<Double> {
        guard tokens.count == 3 else { throw CubeLUTError.invalid("\(line)행에는 RGB 숫자 3개가 필요합니다.") }
        var result = SIMD3<Double>(repeating: 0)
        for channel in 0..<3 {
            guard let value = Double(tokens[channel]), value.isFinite, Float(value).isFinite
            else { throw CubeLUTError.invalid("\(line)행에 유효하지 않은 숫자가 있습니다.") }
            result[channel] = value
        }
        return result
    }

    private static func withoutComment(_ line: String) -> String {
        var quoted = false
        for index in line.indices {
            if line[index] == "\"" { quoted.toggle() }
            if line[index] == "#", !quoted { return String(line[..<index]) }
        }
        return line
    }

    // Reference math only: no implicit color-space conversion or tone mapping.
    // Coordinates outside the declared input domain clamp to its edge.
    func sample(_ input: SIMD3<Double>, intensity: Double = 1) throws -> SIMD3<Double> {
        guard (0..<3).allSatisfy({ input[$0].isFinite }), intensity.isFinite, (0...1).contains(intensity)
        else { throw CubeLUTError.invalid("입력 색과 LUT 강도가 유효하지 않습니다.") }
        if intensity == 0 { return input }
        var coordinate = SIMD3<Double>(repeating: 0)
        for channel in 0..<3 {
            let normalized = (input[channel] - domainMin[channel]) / (domainMax[channel] - domainMin[channel])
            coordinate[channel] = min(max(normalized, 0), 1) * Double(dimension - 1)
        }
        let r0 = Int(floor(coordinate.x)), g0 = Int(floor(coordinate.y)), b0 = Int(floor(coordinate.z))
        let r1 = min(r0 + 1, dimension - 1), g1 = min(g0 + 1, dimension - 1), b1 = min(b0 + 1, dimension - 1)
        let fraction = coordinate - SIMD3(Double(r0), Double(g0), Double(b0))
        func value(_ r: Int, _ g: Int, _ b: Int) -> SIMD3<Double> { values[r + g * dimension + b * dimension * dimension] }
        func mix(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ weight: Double) -> SIMD3<Double> { a * (1 - weight) + b * weight }
        let back = mix(mix(value(r0, g0, b0), value(r1, g0, b0), fraction.x),
                       mix(value(r0, g1, b0), value(r1, g1, b0), fraction.x), fraction.y)
        let front = mix(mix(value(r0, g0, b1), value(r1, g0, b1), fraction.x),
                        mix(value(r0, g1, b1), value(r1, g1, b1), fraction.x), fraction.y)
        let look = mix(back, front, fraction.z)
        return mix(input, look, intensity)
    }
}

enum CubeLUTError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let reason): return reason }
    }
}
