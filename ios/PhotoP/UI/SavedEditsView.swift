import SwiftUI

@MainActor
struct SavedEditsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var edits: [SavedEditSummary] = []
    @State private var selected: SavedEdit?
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                Text("원본·LUT 해시와 레시피를 확인한 뒤 다시 엽니다. 새로 저장하면 별도 편집본을 만듭니다.")
                    .font(.caption).foregroundStyle(.secondary)
                if busy { ProgressView() }
                if let message { Text(message).font(.caption) }
                if edits.isEmpty && !busy { Text("저장된 편집 기록이 없습니다.") }
                ForEach(edits) { edit in
                    Button {
                        busy = true; message = nil
                        Task {
                            defer { busy = false }
                            do { selected = try await SavedEditStore.shared.open(edit.id) }
                            catch { message = error.localizedDescription }
                        }
                    } label: {
                        VStack(alignment: .leading) {
                            Text(edit.title)
                            Text(edit.modified, format: .dateTime.year().month().day().hour().minute()).font(.caption)
                        }
                    }.disabled(busy)
                }
            }
            .navigationTitle("편집 기록")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() }.disabled(busy) } }
            .task { await refresh() }
            .sheet(item: $selected, onDismiss: { Task { await refresh() } }) { saved in
                LUTEditorView(saved: saved)
            }
        }.preferredColorScheme(.dark)
    }
    private func refresh() async {
        do { edits = try await SavedEditStore.shared.list() }
        catch { message = error.localizedDescription }
    }
}
