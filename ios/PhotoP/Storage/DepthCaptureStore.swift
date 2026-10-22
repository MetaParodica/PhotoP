import Foundation
import CryptoKit

struct DepthCaptureMetadata: Codable, Sendable {
    var version = 1
    let timestamp: Double
    let rgbWidth: Int
    let rgbHeight: Int
    let depthWidth: Int
    let depthHeight: Int
    let cameraIntrinsics: [Float]
    let cameraTransform: [Float]
    var coordinateSystem = "ARKit native camera image; column-major calibration; no image rotation"
    var depthEncoding = "float32-little-endian, row-major, metres; finite positive values are valid"
    var confidenceEncoding = "uint8, row-major: 0 low, 1 medium, 2 high"
    let depthBytes: Int
    let confidenceBytes: Int
    let jpegBytes: Int
    let depthSHA256: String
    let confidenceSHA256: String
    let jpegSHA256: String

    func validate() throws {
        guard version == 1, timestamp.isFinite, rgbWidth > 0, rgbHeight > 0,
              rgbWidth <= 8192, rgbHeight <= 8192, depthWidth > 0, depthHeight > 0,
              depthWidth <= 1024, depthHeight <= 1024,
              depthBytes == depthWidth * depthHeight * 4, confidenceBytes == depthWidth * depthHeight,
              jpegBytes > 0, jpegBytes <= 32 * 1024 * 1024,
              cameraIntrinsics.count == 9, cameraTransform.count == 16,
              cameraIntrinsics.allSatisfy(\.isFinite), cameraTransform.allSatisfy(\.isFinite),
              [depthSHA256, confidenceSHA256, jpegSHA256].allSatisfy({ $0.count == 64 && $0.allSatisfy { "0123456789abcdef".contains($0) } })
        else { throw CameraError.invalidPhotoData }
    }
}

struct DepthCapturePayload: Sendable {
    let metadata: DepthCaptureMetadata
    let depth: Data
    let confidence: Data
    let jpeg: Data
    func validate() throws {
        try metadata.validate()
        guard depth.count == metadata.depthBytes, confidence.count == metadata.confidenceBytes, jpeg.count == metadata.jpegBytes,
              LUTPhotoEditor.hash(depth) == metadata.depthSHA256,
              LUTPhotoEditor.hash(confidence) == metadata.confidenceSHA256,
              LUTPhotoEditor.hash(jpeg) == metadata.jpegSHA256 else { throw CameraError.invalidPhotoData }
    }
}

struct StoredDepthCapture: Sendable {
    let package: URL
    let photo: URL
}

enum DepthCaptureStore {
    static let magic = Data("PHOTOPDEPTH1\n".utf8)
    // Header + UInt32 little-endian JSON length + JSON + depth + confidence + JPEG.
    static func encode(_ payload: DepthCapturePayload) throws -> Data {
        try payload.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let json = try encoder.encode(payload.metadata)
        guard json.count <= 64 * 1024 else { throw CameraError.invalidPhotoData }
        var length = UInt32(json.count).littleEndian
        var data = magic
        withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        data.append(json); data.append(payload.depth); data.append(payload.confidence); data.append(payload.jpeg)
        return data
    }

    static func decode(_ data: Data) throws -> DepthCapturePayload {
        let offset = magic.count
        guard data.count >= offset + 4, data.count <= 40 * 1024 * 1024, data.prefix(offset) == magic else { throw CameraError.invalidPhotoData }
        let length = (0..<4).reduce(0) { $0 | (Int(data[offset + $1]) << ($1 * 8)) }
        guard length > 0, length <= 64 * 1024, data.count >= offset + 4 + length else { throw CameraError.invalidPhotoData }
        var cursor = offset + 4
        let metadata = try JSONDecoder().decode(DepthCaptureMetadata.self, from: data.subdata(in: cursor..<(cursor + length)))
        try metadata.validate(); cursor += length
        guard data.count - cursor == metadata.depthBytes + metadata.confidenceBytes + metadata.jpegBytes else { throw CameraError.invalidPhotoData }
        let depth = data.subdata(in: cursor..<(cursor + metadata.depthBytes)); cursor += metadata.depthBytes
        let confidence = data.subdata(in: cursor..<(cursor + metadata.confidenceBytes)); cursor += metadata.confidenceBytes
        let payload = DepthCapturePayload(metadata: metadata, depth: depth, confidence: confidence, jpeg: data.subdata(in: cursor..<data.count))
        try payload.validate()
        return payload
    }

    static func write(_ payload: DepthCapturePayload, documents: URL) throws -> StoredDepthCapture {
        let data = try encode(payload)
        let root = documents.appendingPathComponent("DepthCaptures", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let id = UUID().uuidString
        let temporary = root.appendingPathComponent(".pending-" + id, isDirectory: true)
        let final = root.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
        do {
            let options: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            try data.write(to: temporary.appendingPathComponent("Capture.photopdepth"), options: options)
            try payload.jpeg.write(to: temporary.appendingPathComponent("Photo.jpg"), options: options)
            try FileManager.default.moveItem(at: temporary, to: final)
            return StoredDepthCapture(package: final.appendingPathComponent("Capture.photopdepth"), photo: final.appendingPathComponent("Photo.jpg"))
        } catch { try? FileManager.default.removeItem(at: temporary); throw error }
    }
}
