import Foundation
import CryptoKit

struct CaptureSeriesManifest: Codable {
    struct Frame: Codable {
        let filename: String
        let sha256: String
        let requestedEV: Double
    }
    let version: Int
    let frames: [Frame]
}

enum CaptureSeriesStore {
    static func preserve(_ series: CapturedSeries) async throws -> [URL] {
        try await Task.detached(priority: .utility) {
            let root = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            return try write(series, documents: root)
        }.value
    }
    static func write(_ series: CapturedSeries, documents: URL) throws -> [URL] {
        guard series.photos.count == (series.requestedBiases?.count ?? 1),
              series.photos.count == 1 || series.photos.count == 3,
              series.requestedBiases?.allSatisfy(\.isFinite) ?? true else { throw CameraError.invalidSettings }
        var urls: [URL] = []
        do {
            for photo in series.photos { urls.append(try PhotoStore.writeOriginal(photo, in: documents.appendingPathComponent("Originals"))) }
            if let biases = series.requestedBiases {
                let manifest = CaptureSeriesManifest(version: 1, frames: zip(urls.indices, biases).map { index, bias in
                    CaptureSeriesManifest.Frame(filename: urls[index].lastPathComponent, sha256: SHA256.hash(data: series.photos[index].data).map { String(format: "%02x", $0) }.joined(), requestedEV: bias)
                })
                let folder = documents.appendingPathComponent("BracketGroups")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let json = try JSONEncoder().encode(manifest)
                try json.write(to: folder.appendingPathComponent(UUID().uuidString).appendingPathExtension("json"),
                               options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
            return urls
        } catch {
            for url in urls { try? FileManager.default.removeItem(at: url) }
            throw error
        }
    }
}
