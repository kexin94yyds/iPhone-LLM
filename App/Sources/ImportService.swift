import CryptoKit
import Foundation
import SwiftData

struct ImportSummary {
    let importedCount: Int
    let skippedCount: Int
    let failedFiles: [URL]
}

enum ImportService {
    static let defaultRoot = URL(filePath: "/Users/本地/NotebookLM产物", directoryHint: .isDirectory)

    @MainActor
    static func importMarkdownFiles(from rootURL: URL, into context: ModelContext) throws -> ImportSummary {
        let markdownFiles = try FileScanner.markdownFiles(in: rootURL)
        let existingItems = try context.fetch(FetchDescriptor<LibraryItem>())
        var existingHashes = Set(existingItems.map(\.contentHash))

        var importedCount = 0
        var skippedCount = 0
        var failedFiles: [URL] = []

        for fileURL in markdownFiles {
            do {
                let markdown = try String(contentsOf: fileURL, encoding: .utf8)
                let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    skippedCount += 1
                    continue
                }

                let contentHash = sha256(trimmed)
                if existingHashes.contains(contentHash) {
                    skippedCount += 1
                    continue
                }

                let categoryName = categoryDirectoryName(for: fileURL, rootURL: rootURL)
                let title = fileURL.deletingPathExtension().lastPathComponent
                let item = LibraryItem(
                    title: title,
                    category: LibraryCategory(directoryName: categoryName),
                    bodyMarkdown: trimmed,
                    sourcePath: fileURL.path(percentEncoded: false),
                    contentHash: contentHash
                )

                context.insert(item)
                context.insert(ReadingState(itemID: item.id))
                existingHashes.insert(contentHash)
                importedCount += 1
            } catch {
                failedFiles.append(fileURL)
            }
        }

        try context.save()
        return ImportSummary(importedCount: importedCount, skippedCount: skippedCount, failedFiles: failedFiles)
    }

    private static func categoryDirectoryName(for fileURL: URL, rootURL: URL) -> String? {
        let relativePath = fileURL.path.replacingOccurrences(of: rootURL.path + "/", with: "")
        return relativePath.split(separator: "/").first.map(String.init)
    }

    private static func sha256(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}

private enum FileScanner {
    static func markdownFiles(in rootURL: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: rootURL.path(percentEncoded: false)) else {
            return []
        }

        let keys: [URLResourceKey] = [.isRegularFileKey]
        let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )

        var results: [URL] = []
        while let fileURL = enumerator?.nextObject() as? URL {
            let values = try fileURL.resourceValues(forKeys: Set(keys))
            if values.isRegularFile == true, fileURL.pathExtension.lowercased() == "md" {
                results.append(fileURL)
            }
        }
        return results.sorted { $0.path < $1.path }
    }
}
