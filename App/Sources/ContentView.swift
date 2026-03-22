import SwiftData
import SwiftUI
#if os(macOS)
import AppKit
#endif

struct ContentView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\LibraryItem.importedAt, order: .reverse)]) private var items: [LibraryItem]
    @Query private var readingStates: [ReadingState]
    @State private var selectedItemID: UUID?
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .searchable(text: $searchText, prompt: "Search Markdown")
#if os(macOS)
        .task {
            await performAutomaticImportIfNeeded()
        }
#endif
    }

    private var filteredItems: [LibraryItem] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }
        return items.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
            || $0.bodyMarkdown.localizedCaseInsensitiveContains(trimmed)
            || $0.categoryRawValue.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var sidebar: some View {
        List(selection: $selectedItemID) {
            ForEach(LibraryCategory.allCases) { category in
                let categoryItems = filteredItems.filter { $0.category == category }
                if !categoryItems.isEmpty {
                    Section(category.rawValue) {
                        ForEach(categoryItems) { item in
                            LibraryItemRow(
                                item: item,
                                state: readingStates.first(where: { $0.itemID == item.id })
                            )
                            .tag(item.id)
                        }
                    }
                }
            }
        }
        .navigationTitle("LM Reader")
        .toolbar {
#if os(macOS)
            ToolbarItem(placement: .automatic) {
                Text(appModel.importStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ToolbarItem(placement: .primaryAction) {
                ImportToolbarButton()
            }
#endif
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let selectedItem = selectedItem {
            ReaderDetailView(item: selectedItem)
        } else {
            ContentUnavailableView(
                "No Document Selected",
                systemImage: "doc.text.magnifyingglass",
                description: Text("Import Markdown on Mac, then open the same library on iPhone.")
            )
        }
    }

    private var selectedItem: LibraryItem? {
        let selected = filteredItems.first(where: { $0.id == selectedItemID })
        return selected ?? filteredItems.first
    }

#if os(macOS)
    @MainActor
    private func performAutomaticImportIfNeeded() async {
        guard !appModel.hasAttemptedAutomaticImport else { return }
        appModel.hasAttemptedAutomaticImport = true

        guard items.isEmpty else {
            do {
                try syncMirroredFolderToICloud()
                appModel.importStatusMessage = "Library ready, mirrored folder to iPhone"
            } catch {
                appModel.importStatusMessage = "Library ready, folder mirror failed: \(error.localizedDescription)"
            }
            return
        }

        if let bookmarkedURL = FolderBookmarkStore.restoreURL() {
            importFromAuthorizedFolder(bookmarkedURL)
            return
        }

        guard FileManager.default.fileExists(atPath: ImportService.defaultRoot.path(percentEncoded: false)) else {
            appModel.importStatusMessage = "Default folder not found"
            return
        }

        appModel.importStatusMessage = "Choose NotebookLM output folder"
        chooseFolder(suggested: ImportService.defaultRoot)
    }

    private func chooseFolder(suggested: URL? = nil) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"
        panel.message = "Choose the NotebookLM output folder to sync with iPhone."
        panel.directoryURL = suggested
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            importFromAuthorizedFolder(url)
        }
    }

    @MainActor
    private func importFromAuthorizedFolder(_ url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            try FolderBookmarkStore.saveBookmark(for: url)
            let summary = try ImportService.importMarkdownFiles(from: url, into: modelContext)
            try syncFolderToICloud(sourceFolderURL: url)
            let failures = summary.failedFiles.count
            appModel.importStatusMessage = "Imported \(summary.importedCount), skipped \(summary.skippedCount), failed \(failures), mirrored folder to iPhone"
        } catch {
            appModel.importStatusMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    private func syncMirroredFolderToICloud() throws {
        if let bookmarkedURL = FolderBookmarkStore.restoreURL() {
            try syncFolderToICloud(sourceFolderURL: bookmarkedURL)
            return
        }

        guard FileManager.default.fileExists(atPath: ImportService.defaultRoot.path(percentEncoded: false)) else {
            throw CocoaError(.fileNoSuchFile)
        }
        try syncFolderToICloud(sourceFolderURL: ImportService.defaultRoot)
    }

    private func syncFolderToICloud(sourceFolderURL: URL) throws {
        NSLog("LMReader: syncFolderToICloud source path = %@", sourceFolderURL.path(percentEncoded: false))
        let didAccess = sourceFolderURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceFolderURL.stopAccessingSecurityScopedResource()
            }
        }
        try CloudSyncService.syncFolderMirror(from: sourceFolderURL)
    }
#endif
}

private struct LibraryItemRow: View {
    let item: LibraryItem
    let state: ReadingState?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if state?.isFavorite == true {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                }
            }

            Text(item.category.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

#if os(macOS)
private struct ImportToolbarButton: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var modelContext
    @State private var isImporting = false

    var body: some View {
        Menu {
            Button("Import Default Folder") {
                runImport(from: ImportService.defaultRoot)
            }
            Button("Sync iPhone Now") {
                syncExistingLibrary()
            }
            Button("Choose Folder…") {
                chooseFolder()
            }
        } label: {
            Label("Import", systemImage: isImporting ? "arrow.triangle.2.circlepath.circle.fill" : "square.and.arrow.down")
        }
        .disabled(isImporting)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"
        panel.message = "Choose the NotebookLM output folder to sync with iPhone."
        panel.directoryURL = ImportService.defaultRoot
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            runImport(from: url)
        }
    }

    private func runImport(from url: URL) {
        isImporting = true
        Task { @MainActor in
            defer { isImporting = false }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                try FolderBookmarkStore.saveBookmark(for: url)
                let summary = try ImportService.importMarkdownFiles(from: url, into: modelContext)
                try syncFolderToICloud(sourceFolderURL: url)
                let failures = summary.failedFiles.count
                appModel.importStatusMessage = "Imported \(summary.importedCount), skipped \(summary.skippedCount), failed \(failures), synced iPhone"
            } catch {
                appModel.importStatusMessage = "Import failed: \(error.localizedDescription)"
            }
        }
    }

    private func syncExistingLibrary() {
        isImporting = true
        Task { @MainActor in
            defer { isImporting = false }
            do {
                if let bookmarkedURL = FolderBookmarkStore.restoreURL() {
                    try syncFolderToICloud(sourceFolderURL: bookmarkedURL)
                    appModel.importStatusMessage = "Mirrored bookmarked folder to iPhone"
                    return
                }

                if FileManager.default.fileExists(atPath: ImportService.defaultRoot.path(percentEncoded: false)) {
                    try syncFolderToICloud(sourceFolderURL: ImportService.defaultRoot)
                    appModel.importStatusMessage = "Mirrored default folder to iPhone"
                    return
                }

                appModel.importStatusMessage = "No source folder yet. Import on Mac first."
            } catch {
                appModel.importStatusMessage = "Folder mirror failed: \(error.localizedDescription)"
            }
        }
    }

    private func syncFolderToICloud(sourceFolderURL: URL) throws {
        NSLog("LMReader: toolbar syncFolderToICloud source path = %@", sourceFolderURL.path(percentEncoded: false))
        let didAccess = sourceFolderURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceFolderURL.stopAccessingSecurityScopedResource()
            }
        }
        try CloudSyncService.syncFolderMirror(from: sourceFolderURL)
    }
}
#endif
