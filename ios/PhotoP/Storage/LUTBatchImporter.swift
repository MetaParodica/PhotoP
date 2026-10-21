import Foundation

struct LUTBatchImportReport: Sendable {
    let imported: Int
    let failures: [String]
}
enum LUTBatchImporter {
    static func run(_ urls: [URL], confirmedSRGB: Bool, library: FilterPresetLibrary = .shared) async throws -> LUTBatchImportReport {
        guard confirmedSRGB, !urls.isEmpty, urls.count <= 32 else { throw ImageEditingError.invalid("sRGB 입출력을 확인하고 한 번에 1~32개 LUT를 선택하세요.") }
        var imported = 0, failures: [String] = []
        for url in urls {
            try Task.checkCancellation()
            do {
                let lut = try await Task.detached(priority: .userInitiated) { try ImportedLUT.read(url) }.value
                try Task.checkCancellation()
                let title = lut.displayName.isEmpty ? url.deletingPathExtension().lastPathComponent : lut.displayName
                try await library.save(lut, settings: .init(), name: String(title.prefix(80)))
                imported += 1
            } catch is CancellationError { throw CancellationError() }
            catch { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
        }
        return .init(imported: imported, failures: failures)
    }
}
