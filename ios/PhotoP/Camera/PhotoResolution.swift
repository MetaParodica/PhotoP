import Foundation

struct PhotoResolution: Hashable, Identifiable, Sendable {
    let width: Int32
    let height: Int32
    var id: String { "\(width)x\(height)" }
    var pixels: Int64 { Int64(width) * Int64(height) }
    var title: String { String(format: "%.1fMP · %d×%d", Double(pixels) / 1_000_000, width, height) }
    var valid: Bool { width > 0 && height > 0 }
}
enum PhotoResolutionPolicy {
    static func options(supported: [PhotoResolution], ceiling: PhotoResolution) -> [PhotoResolution] {
        Array(Set(supported.filter { $0.valid && $0.width <= ceiling.width && $0.height <= ceiling.height }))
            .sorted { $0.pixels == $1.pixels ? $0.id < $1.id : $0.pixels < $1.pixels }
    }
    static func resolve(_ requested: PhotoResolution?, supported: [PhotoResolution], ceiling: PhotoResolution,
                        raw: RawCaptureMode, bracket: Bool) throws -> PhotoResolution {
        let available = options(supported: supported, ceiling: ceiling)
        guard let largest = available.last else { throw CameraError.invalidSettings }
        guard let requested else { return largest }
        guard raw == .processed, !bracket, available.contains(requested) else { throw CameraError.invalidSettings }
        return requested
    }
}
