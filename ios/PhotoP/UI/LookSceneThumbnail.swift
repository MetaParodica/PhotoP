import SwiftUI

struct LookSceneSample: Sendable, Identifiable {
    let id = UUID()
    let image: SDRImage
}

actor LookThumbnailRenderer {
    static let shared = LookThumbnailRenderer()
    private var renderers: [String: MetalLUTRenderer] = [:]
    private var settings: [String: ProcessingLookSettings] = [:]
    private var order: [String] = []
    private var generation: UInt64 = 0

    func clear() { generation &+= 1; renderers.removeAll(); settings.removeAll(); order.removeAll() }

    func render(id: String, sample: LookSceneSample, load: (@Sendable () async throws -> ImportedLUT)?) async throws -> PhotoThumbnailImage {
        try Task.checkCancellation()
        let currentGeneration = generation
        guard let load else { return try PhotoThumbnailImage(image: sample.image.cgImage()) }
        let renderer: MetalLUTRenderer
        let look: ProcessingLookSettings
        if let cached = renderers[id], let cachedSettings = settings[id] { renderer = cached; look = cachedSettings }
        else {
            let imported = try await load()
            try Task.checkCancellation()
            guard currentGeneration == generation else { throw CancellationError() }
            renderer = try MetalLUTRenderer(lut: imported.lut)
            look = imported.preset ?? ProcessingLookSettings()
            renderers[id] = renderer; settings[id] = look
        }
        order.removeAll { $0 == id }; order.append(id)
        while order.count > 12 {
            let evicted = order.removeFirst(); renderers[evicted] = nil; settings[evicted] = nil
        }
        let input = sample.image
        let data = try await renderer.render(input.rgba, width: input.width, height: input.height,
                                             intensity: look.intensity, grain: look.grain, effects: look.finish)
        try Task.checkCancellation()
        return try PhotoThumbnailImage(image: SDRImage(rgba: data, width: input.width, height: input.height).cgImage())
    }
}

struct LookSceneThumbnail: View {
    let id: String
    let sample: LookSceneSample?
    var load: (@Sendable () async throws -> ImportedLUT)? = nil
    @State private var rendered: PhotoThumbnailImage?
    @State private var failed = false
    var body: some View {
        ZStack {
            Color(white: 0.12)
            if let rendered { Image(decorative: rendered.image, scale: 1).resizable().scaledToFill() }
            else { Image(systemName: failed ? "exclamationmark.triangle" : "camera").foregroundStyle(.secondary) }
        }.clipped()
            .task(id: sample?.id) {
                guard let sample else { rendered = nil; return }
                do {
                    let image = try await LookThumbnailRenderer.shared.render(id: id, sample: sample, load: load)
                    guard !Task.isCancelled else { return }
                    rendered = image; failed = false
                } catch is CancellationError { }
                catch { failed = true }
            }
    }
}
