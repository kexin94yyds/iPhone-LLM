import Foundation

enum FolderBookmarkStore {
    private static let bookmarkKey = "LMReader.importFolderBookmark"

    static func saveBookmark(for url: URL) throws {
#if os(macOS)
        let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
#else
        _ = url
#endif
    }

    static func restoreURL() -> URL? {
#if os(macOS)
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else {
            return nil
        }

        var isStale = false
        return try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
#else
        return nil
#endif
    }
}
