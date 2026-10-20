import Foundation
import Photos

enum PhotoStore {
    static func preserveOriginal(_ data: Data) async throws -> URL {
        try await Task.detached(priority: .utility) {
            let folder = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true)
                .appendingPathComponent("Originals", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
            // Write the exact AVCapturePhoto bytes; do not re-encode through UIImage.
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return url
        }.value
    }

    static func addToPhotos(_ url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized else {
            throw NSError(domain: "PhotoP", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "원본은 앱에 보관했습니다. 사진 접근을 허용하거나 파일 공유를 이용해 주세요."])
        }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.originalFilename = url.lastPathComponent
            request.addResource(with: .photo, fileURL: url, options: options)
        }
    }
}
