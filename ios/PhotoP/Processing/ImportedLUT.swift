import Foundation

struct ImportedLUT: Sendable {
    let data: Data
    let lut: CubeLUT
    let displayName: String
    var preset: ProcessingLookSettings? = nil
    var provenance: LUTProvenance? = nil

    static func read(_ url: URL) throws -> ImportedLUT {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while data.count <= CubeLUT.maximumFileBytes {
            let remaining = CubeLUT.maximumFileBytes + 1 - data.count
            guard let chunk = try handle.read(upToCount: min(64 * 1024, remaining)), !chunk.isEmpty else { break }
            data.append(chunk)
        }
        if url.pathExtension.lowercased() == "png" { data = try HaldLUT.convert(data) }
        guard data.count <= CubeLUT.maximumFileBytes, let text = String(data: data, encoding: .utf8)
        else { throw ImageEditingError.invalid("UTF-8 .cube 파일은 32MiB 이하여야 합니다.") }
        let lut = try CubeLUT.parse(text)
        return ImportedLUT(data: data, lut: lut, displayName: lut.title ?? url.deletingPathExtension().lastPathComponent)
    }
}
