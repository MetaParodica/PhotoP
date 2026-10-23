import SwiftUI

@MainActor
struct LUTFavoritesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [LUTFavorite] = []
    @State private var busy = false
    @State private var message: String?
    let onSelect: (ImportedLUT) async throws -> Void

    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty { Text("저장한 LUT 즐겨찾기가 없습니다.").foregroundStyle(.secondary) }
                ForEach(entries) { entry in
                    Button {
                        busy = true
                        Task {
                            defer { busy = false }
                            do {
                                let imported = try await LUTLibrary.shared.load(entry.id)
                                try await onSelect(imported)
                                dismiss()
                            } catch { message = error.localizedDescription }
                        }
                    } label: {
                        VStack(alignment: .leading) {
                            Text(entry.name); Text("sRGB → sRGB").font(.caption).foregroundStyle(.secondary)
                            Text(entry.settings == nil ? "기존 색상표 즐겨찾기" : "LUT·강도·그레인·마감 복원").font(.caption2)
                            if let p = entry.provenance { Text("\(p.creator) · \(p.license)").font(.caption2) }
                        }
                    }
                    .disabled(busy)
                    .swipeActions {
                        Button("삭제", role: .destructive) {
                            Task {
                                do { try await LUTLibrary.shared.remove(entry.id); await reload() }
                                catch { message = error.localizedDescription }
                            }
                        }.disabled(busy)
                    }
                }
                if busy { ProgressView() }
                if let message { Text(message).font(.caption) }
            }
            .navigationTitle("LUT 즐겨찾기")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() }.disabled(busy) } }
            .interactiveDismissDisabled(busy)
            .task { await reload() }
        }.preferredColorScheme(.dark)
    }
    private func reload() async {
        do { entries = try await LUTLibrary.shared.favorites() }
        catch { message = error.localizedDescription }
    }
}
