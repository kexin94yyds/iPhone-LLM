import SwiftData
import SwiftUI

struct ReaderDetailView: View {
    let item: LibraryItem

    @Environment(\.modelContext) private var modelContext
    @Query private var states: [ReadingState]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                Divider()
                Text(.init(item.bodyMarkdown))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
        .navigationTitle(item.title)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .onAppear {
            touchState()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    toggleFavorite()
                } label: {
                    Label("Favorite", systemImage: readingState?.isFavorite == true ? "star.fill" : "star")
                }
            }
        }
    }

    private var readingState: ReadingState? {
        states.first(where: { $0.itemID == item.id })
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.category.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(item.title)
                .font(.largeTitle.bold())

            Text(item.importedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let state = readingState {
                HStack(spacing: 12) {
                    Label(state.isFavorite ? "Favorited" : "Not Favorited", systemImage: state.isFavorite ? "star.fill" : "star")
                    if let lastOpenedAt = state.lastOpenedAt {
                        Label(lastOpenedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func touchState() {
        let state = readingState ?? ReadingState(itemID: item.id)
        state.lastOpenedAt = .now

        if readingState == nil {
            modelContext.insert(state)
        }

        try? modelContext.save()
    }

    private func toggleFavorite() {
        let state = readingState ?? ReadingState(itemID: item.id)
        state.isFavorite.toggle()
        state.lastOpenedAt = .now

        if readingState == nil {
            modelContext.insert(state)
        }

        try? modelContext.save()
    }
}
