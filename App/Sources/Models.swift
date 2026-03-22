import Foundation
import SwiftData

enum LibraryCategory: String, CaseIterable, Codable, Identifiable {
    case podcast = "播客"
    case books = "书籍"
    case videos = "视频"
    case presentations = "PPT"
    case notes = "笔记库"
    case uncategorized = "未分类"

    var id: String { rawValue }

    init(directoryName: String?) {
        switch directoryName {
        case "播客":
            self = .podcast
        case "书籍":
            self = .books
        case "视频":
            self = .videos
        case "PPT":
            self = .presentations
        case "笔记库":
            self = .notes
        default:
            self = .uncategorized
        }
    }
}

@Model
final class LibraryItem {
    var id: UUID = UUID()
    var title: String = ""
    var categoryRawValue: String = LibraryCategory.uncategorized.rawValue
    var bodyMarkdown: String = ""
    var importedAt: Date = Date()
    var sourcePath: String = ""
    var contentHash: String = ""

    init(
        id: UUID = UUID(),
        title: String,
        category: LibraryCategory,
        bodyMarkdown: String,
        importedAt: Date = .now,
        sourcePath: String,
        contentHash: String
    ) {
        self.id = id
        self.title = title
        self.categoryRawValue = category.rawValue
        self.bodyMarkdown = bodyMarkdown
        self.importedAt = importedAt
        self.sourcePath = sourcePath
        self.contentHash = contentHash
    }

    var category: LibraryCategory {
        get { LibraryCategory(rawValue: categoryRawValue) ?? .uncategorized }
        set { categoryRawValue = newValue.rawValue }
    }
}

@Model
final class ReadingState {
    var id: UUID = UUID()
    var itemID: UUID = UUID()
    var isFavorite: Bool = false
    var lastOpenedAt: Date?
    var readingProgress: Double = 0

    init(
        id: UUID = UUID(),
        itemID: UUID,
        isFavorite: Bool = false,
        lastOpenedAt: Date? = nil,
        readingProgress: Double = 0
    ) {
        self.id = id
        self.itemID = itemID
        self.isFavorite = isFavorite
        self.lastOpenedAt = lastOpenedAt
        self.readingProgress = readingProgress
    }
}
