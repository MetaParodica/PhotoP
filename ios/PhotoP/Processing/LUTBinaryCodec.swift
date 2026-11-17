import Foundation

// Runtime cache, never a replacement for original .cube/provenance bytes.
// Packed little-endian Float64 keeps the CPU reference table bit-exact.
enum LUTBinaryCodec {
    private struct Header: Codable {
        let version: Int
        let title: String?
        let dimension: Int
        let oneDimensional: Bool
        let minimum: [Double]
        let maximum: [Double]
    }
    static func encode(_ lut: CubeLUT) throws -> Data {
        let h = Header(version: 1, title: lut.title, dimension: lut.dimension, oneDimensional: lut.isOneDimensional,
            minimum: [lut.domainMin.x, lut.domainMin.y, lut.domainMin.z], maximum: [lut.domainMax.x, lut.domainMax.y, lut.domainMax.z])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let metadata = try encoder.encode(h)
        guard metadata.count <= 16384 else { throw CubeLUTError.invalid("LUT 캐시 헤더가 너무 큽니다.") }
        var length = UInt32(metadata.count).littleEndian
        var output = withUnsafeBytes(of: &length) { Data($0) }; output.append(metadata)
        var words: [UInt64] = []; words.reserveCapacity(lut.values.count * 3)
        for v in lut.values { words.append(v.x.bitPattern.littleEndian); words.append(v.y.bitPattern.littleEndian); words.append(v.z.bitPattern.littleEndian) }
        words.withUnsafeBytes { output.append(contentsOf: $0) }
        return output
    }
    static func decode(_ data: Data) throws -> CubeLUT {
        guard data.count >= 4, data.count <= CubeLUT.maximumFileBytes else { throw CubeLUTError.invalid("LUT 캐시 크기가 유효하지 않습니다.") }
        let length = data.withUnsafeBytes { Int(UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))) }
        guard (1...16384).contains(length), length <= data.count - 4 else { throw CubeLUTError.invalid("LUT 캐시 헤더가 유효하지 않습니다.") }
        let h = try JSONDecoder().decode(Header.self, from: data.subdata(in: 4..<(4 + length)))
        guard h.version == 1, (2...(h.oneDimensional ? 65536 : 65)).contains(h.dimension),
              h.minimum.count == 3, h.maximum.count == 3 else { throw CubeLUTError.invalid("지원하지 않는 LUT 캐시입니다.") }
        let count = h.oneDimensional ? h.dimension : h.dimension * h.dimension * h.dimension
        let offset = 4 + length
        guard data.count - offset == count * 24 else { throw CubeLUTError.invalid("LUT 캐시 테이블 크기가 다릅니다.") }
        let values: [SIMD3<Double>] = data.withUnsafeBytes { raw in
            var result: [SIMD3<Double>] = []; result.reserveCapacity(count)
            for i in 0..<count {
                func scalar(_ c: Int) -> Double { Double(bitPattern: UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: offset + i * 24 + c * 8, as: UInt64.self))) }
                result.append(SIMD3(scalar(0), scalar(1), scalar(2)))
            }
            return result
        }
        return try CubeLUT(title: h.title, dimension: h.dimension, domainMin: SIMD3(h.minimum[0], h.minimum[1], h.minimum[2]),
            domainMax: SIMD3(h.maximum[0], h.maximum[1], h.maximum[2]), values: values, isOneDimensional: h.oneDimensional)
    }
}
