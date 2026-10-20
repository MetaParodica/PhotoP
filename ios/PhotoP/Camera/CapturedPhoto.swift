import AVFoundation
import ImageIO
import UniformTypeIdentifiers

// Container type is verified before assigning a filename or exporting to Photos.
enum PhotoFileFormat: String, CaseIterable, Identifiable, Sendable {
    case jpeg, heif
    var id: String { rawValue }
    var title: String { self == .jpeg ? "JPEG" : "HEIF" }
    var fileExtension: String { self == .jpeg ? "jpg" : "heic" }
    var codec: AVVideoCodecType { self == .jpeg ? .jpeg : .hevc }

    static func supported(by codecs: [AVVideoCodecType]) -> [Self] {
        allCases.filter { codecs.contains($0.codec) }
    }
}

struct CapturedPhoto: Sendable {
    let data: Data
    let format: PhotoFileFormat

    init(data: Data, expectedFormat: PhotoFileFormat) throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let identifier = CGImageSourceGetType(source),
              let type = UTType(identifier as String) else { throw CameraError.invalidPhotoData }
        let actual: PhotoFileFormat
        if type.conforms(to: .jpeg) { actual = .jpeg }
        else if type.conforms(to: .heic) { actual = .heif }
        else { throw CameraError.invalidPhotoData }
        guard actual == expectedFormat else { throw CameraError.invalidPhotoData }
        self.data = data
        self.format = actual
    }
}
