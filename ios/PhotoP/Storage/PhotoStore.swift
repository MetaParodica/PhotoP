import Foundation
import Photos

enum PhotoStore {
    static func preserveOriginal(_ photo: CapturedPhoto) async throws -> URL {
        try await Task.detached(priority: .utility) {
            let folder = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true)
                .appendingPathComponent("Originals", isDirectory: true)
            return try writeOriginal(photo, in: folder)
        }.value
    }

    static func writeOriginal(_ photo: CapturedPhoto, in folder: URL) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(photo.format.fileExtension)
        try photo.data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return url
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
