import Foundation

// Checks the TIFF/DNG container, without invoking a camera-specific RAW decoder.
// Sensor pixels and physical capture quality are validated separately on device.
enum DNGContainer {
    static func validate(_ data: Data) throws {
        guard data.count >= 8 else { throw CameraError.invalidPhotoData }
        let little: Bool
        if data[0] == 73 && data[1] == 73 { little = true }
        else if data[0] == 77 && data[1] == 77 { little = false }
        else { throw CameraError.invalidPhotoData }
        func word(_ offset: Int, _ bytes: Int) throws -> UInt32 {
            guard offset >= 0, bytes <= data.count, offset <= data.count - bytes else { throw CameraError.invalidPhotoData }
            var result: UInt32 = 0
            for index in 0..<bytes {
                let shift = little ? index * 8 : (bytes - index - 1) * 8
                result |= UInt32(data[offset + index]) << shift
            }
            return result
        }
        guard try word(2, 2) == 42 else { throw CameraError.invalidPhotoData }
        let offset = Int(try word(4, 4))
        guard offset >= 8 else { throw CameraError.invalidPhotoData }
        let count = Int(try word(offset, 2))
        guard (1...4096).contains(count), offset <= data.count - 2,
              count <= (data.count - offset - 2) / 12,
              offset + 2 + count * 12 <= data.count - 4 else { throw CameraError.invalidPhotoData }
        var version = false, width = false, height = false
        var seen: Set<UInt32> = []
        for index in 0..<count {
            let entry = offset + 2 + index * 12
            let tag = try word(entry, 2), type = try word(entry + 2, 2), size = try word(entry + 4, 4)
            guard seen.insert(tag).inserted else { throw CameraError.invalidPhotoData }
            if tag == 50706 { // DNGVersion: BYTE[4], inline in the first IFD.
                guard type == 1, size == 4, data[entry + 8] == 1 else { throw CameraError.invalidPhotoData }
                version = true
            } else if tag == 256 || tag == 257 {
                guard size == 1, type == 3 || type == 4 else { throw CameraError.invalidPhotoData }
                let value = try word(entry + 8, type == 3 ? 2 : 4)
                guard value > 0, value <= 100_000 else { throw CameraError.invalidPhotoData }
                if tag == 256 { width = true } else { height = true }
            }
        }
        guard version, width, height else { throw CameraError.invalidPhotoData }
    }
}
