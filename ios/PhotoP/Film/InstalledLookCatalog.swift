import Foundation

struct InstalledLook: Identifiable, Sendable {
    enum Source: Sendable { case bundled(BundledFilmStyle), company(CompanyFilmStyle) }
    let source: Source
    var id: String { switch source { case .bundled(let item): return item.id; case .company(let item): return item.id } }
    var name: String { switch source { case .bundled(let item): return item.name; case .company(let item): return item.name } }
    var canApply: Bool { if case .company(let item) = source { return item.canApply }; return true }
    func load() async throws -> ImportedLUT {
        switch source {
        case .bundled(let item):
            // The app uses an explicit SDR interpretation for its preinstalled pack.
            // Preserve the source's assumed profile and credit in provenance.
            return try BundledFilmLibrary.load(item, in: BundledFilmLibrary.root(), confirmedSRGB: true)
        case .company(let item): return try await CompanyLookCompiler.shared.load(item, in: CompanyFilmLibrary.root())
        }
    }
}

actor InstalledLookCatalog {
    static let shared = InstalledLookCatalog()
    private var installed: [InstalledLook]?
    func install() async throws -> [InstalledLook] {
        if let installed { return installed }
        let items = try BundledFilmLibrary.entries(in: BundledFilmLibrary.root()).map { InstalledLook(source: .bundled($0)) }
            + CompanyFilmLibrary.entries(in: CompanyFilmLibrary.root()).map { InstalledLook(source: .company($0)) }
        // Compile V-Log adapters to the existing hash/version-verified disk cache,
        // one at a time, without retaining all 65³ tables in phone memory.
        for item in items where item.canApply {
            try Task.checkCancellation()
            _ = try await item.load()
        }
        installed = items
        return items
    }
}
