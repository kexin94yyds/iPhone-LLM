import Foundation
#if os(macOS)
import SwiftData
#endif

#if os(iOS)
extension Notification.Name {
    static let cloudMirrorContentsDidChange = Notification.Name("cloudMirrorContentsDidChange")
}
#endif

struct LibrarySnapshotEntry: Codable, Identifiable {
    let id: UUID
    let title: String
    let categoryRawValue: String
    let bodyMarkdown: String
    let importedAt: Date
}

struct LibrarySnapshot: Codable {
    let updatedAt: Date
    let items: [LibrarySnapshotEntry]
}

struct CloudMirrorEntry: Identifiable, Hashable {
    let relativePath: String
    let isDirectory: Bool

    var id: String { relativePath }

    var name: String {
        URL(filePath: relativePath).lastPathComponent.removingPercentEncoding
        ?? URL(filePath: relativePath).lastPathComponent
    }
}

enum CloudSyncService {
    private static let containerIdentifier = "iCloud.com.cunzhi.LMReader"
    private static let snapshotFileName = "library-snapshot.json"
    private static let mirrorDirectoryName = "LibraryMirror"

    static func loadSnapshot() throws -> LibrarySnapshot {
        let fileURL = try snapshotFileURL()
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder.snapshotDecoder.decode(LibrarySnapshot.self, from: data)
    }

#if os(macOS)
    static func exportSnapshot(from items: [LibraryItem]) throws {
        let snapshot = LibrarySnapshot(
            updatedAt: .now,
            items: items.map {
                LibrarySnapshotEntry(
                    id: $0.id,
                    title: $0.title,
                    categoryRawValue: $0.categoryRawValue,
                    bodyMarkdown: $0.bodyMarkdown,
                    importedAt: $0.importedAt
                )
            }
        )

        let directoryURL = try snapshotDirectoryURL()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try JSONEncoder.prettyPrinted.encode(snapshot)
        try data.write(to: directoryURL.appendingPathComponent(snapshotFileName), options: .atomic)
    }
#endif

    static func snapshotExists() -> Bool {
        guard let fileURL = try? snapshotFileURL() else { return false }
        return FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false))
    }

#if os(macOS)
    static func syncFolderMirror(from sourceFolderURL: URL) throws {
        let mirrorRootURL = try mirrorRootURL()
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: mirrorRootURL.path(percentEncoded: false)) {
            try fileManager.removeItem(at: mirrorRootURL)
        }
        try fileManager.createDirectory(at: mirrorRootURL, withIntermediateDirectories: true)

        let sourcePath = sourceFolderURL.path(percentEncoded: false)
        let enumerator = fileManager.enumerator(atPath: sourcePath)

        while let relativePath = enumerator?.nextObject() as? String {
            let itemURL = sourceFolderURL.appendingPathComponent(relativePath)
            let destinationURL = mirrorRootURL.appendingPathComponent(relativePath)
            let resourceValues = try itemURL.resourceValues(forKeys: [.isDirectoryKey])

            if resourceValues.isDirectory == true {
                try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
            } else {
                try fileManager.createDirectory(
                    at: destinationURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if fileManager.fileExists(atPath: destinationURL.path(percentEncoded: false)) {
                    try fileManager.removeItem(at: destinationURL)
                }
                try fileManager.copyItem(at: itemURL, to: destinationURL)
            }
        }
    }
#endif

    static func mirroredContentExists() -> Bool {
        guard let rootURL = try? mirrorRootURL() else { return false }
        return FileManager.default.fileExists(atPath: rootURL.path(percentEncoded: false))
    }

    static func listMirroredDirectory(relativePath: String = "") throws -> [CloudMirrorEntry] {
        let directoryURL = try directoryURL(for: relativePath)
        let fileManager = FileManager.default
        let childURLs = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        return try childURLs.map { url in
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            let itemRelativePath: String
            if relativePath.isEmpty {
                itemRelativePath = url.lastPathComponent
            } else {
                itemRelativePath = relativePath + "/" + url.lastPathComponent
            }
            return CloudMirrorEntry(
                relativePath: itemRelativePath,
                isDirectory: values.isDirectory == true
            )
        }
        .sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory && !rhs.isDirectory
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    static func preferredMirrorRelativePath() throws -> String {
        var currentRelativePath = ""

        while true {
            let entries = try listMirroredDirectory(relativePath: currentRelativePath)
            guard entries.count == 1, let onlyEntry = entries.first, onlyEntry.isDirectory else {
                return currentRelativePath
            }
            currentRelativePath = onlyEntry.relativePath
        }
    }

    static func readMirroredFile(relativePath: String) throws -> String {
        let fileURL = try directoryURL(for: relativePath)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    static func mirroredFileURL(relativePath: String) throws -> URL {
        try directoryURL(for: relativePath)
    }

#if os(iOS)
    @MainActor
    static func refreshUbiquitousMirrorMetadata() async {
        guard let mirrorRootURL = try? mirrorRootURL() else { return }

        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(
            format: "%K BEGINSWITH %@",
            NSMetadataItemPathKey,
            mirrorRootURL.path(percentEncoded: false)
        )

        await withCheckedContinuation { continuation in
            var didResume = false
            var finishObserver: NSObjectProtocol?
            var updateObserver: NSObjectProtocol?

            let finish = {
                guard didResume == false else { return }
                didResume = true
                query.disableUpdates()
                query.stop()
                if let finishObserver {
                    NotificationCenter.default.removeObserver(finishObserver)
                }
                if let updateObserver {
                    NotificationCenter.default.removeObserver(updateObserver)
                }
                continuation.resume()
            }

            finishObserver = NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryDidFinishGathering,
                object: query,
                queue: .main
            ) { _ in
                finish()
            }

            updateObserver = NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryDidUpdate,
                object: query,
                queue: .main
            ) { _ in
                finish()
            }

            query.start()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                finish()
            }
        }
    }

    @MainActor
    static func startMonitoringUbiquitousMirror() {
        UbiquitousMirrorMonitor.shared.start()
    }

    static func prepareMirroredFileForPlayback(relativePath: String) async throws -> URL {
        let fileURL = try mirroredFileURL(relativePath: relativePath)
        try await ensureFileIsLocallyAvailable(fileURL)
        return fileURL
    }

    static func ensureFileIsLocallyAvailable(_ fileURL: URL) async throws {
        let keys: Set<URLResourceKey> = [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
        ]

        let initialValues = try fileURL.resourceValues(forKeys: keys)
        guard initialValues.isUbiquitousItem == true else { return }

        if initialValues.ubiquitousItemDownloadingStatus == .current {
            return
        }

        try FileManager.default.startDownloadingUbiquitousItem(at: fileURL)
        let deadline = Date().addingTimeInterval(30)

        while Date() < deadline {
            try await Task.sleep(for: .milliseconds(300))
            let values = try fileURL.resourceValues(forKeys: keys)
            if values.ubiquitousItemDownloadingStatus == .current {
                return
            }
        }

        throw NSError(
            domain: "CloudSyncService",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "文件还没有下载完成，请稍后再试"]
        )
    }
#endif

    private static func snapshotFileURL() throws -> URL {
        try snapshotDirectoryURL().appendingPathComponent(snapshotFileName)
    }

    private static func snapshotDirectoryURL() throws -> URL {
        guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: containerIdentifier) else {
            throw CloudSyncError.containerUnavailable
        }
        return containerURL.appendingPathComponent("Documents")
    }

    fileprivate static func mirrorRootURL() throws -> URL {
        try snapshotDirectoryURL().appendingPathComponent(mirrorDirectoryName)
    }

    private static func directoryURL(for relativePath: String) throws -> URL {
        if relativePath.isEmpty {
            return try mirrorRootURL()
        }
        return try mirrorRootURL().appendingPathComponent(relativePath)
    }
}

#if os(iOS)
@MainActor
private final class UbiquitousMirrorMonitor {
    static let shared = UbiquitousMirrorMonitor()

    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private var monitoredRootPath: String?

    private init() {}

    func start() {
        guard let mirrorRootURL = try? CloudSyncService.mirrorRootURL() else { return }
        let rootPath = mirrorRootURL.path(percentEncoded: false)

        if monitoredRootPath == rootPath, query != nil {
            return
        }

        stop()

        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(
            format: "%K BEGINSWITH %@",
            NSMetadataItemPathKey,
            rootPath
        )

        let publishChange = { [weak query] in
            query?.disableUpdates()
            NotificationCenter.default.post(name: .cloudMirrorContentsDidChange, object: nil)
            query?.enableUpdates()
        }

        observers = [
            NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryDidFinishGathering,
                object: query,
                queue: .main
            ) { _ in
                publishChange()
            },
            NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryDidUpdate,
                object: query,
                queue: .main
            ) { _ in
                publishChange()
            }
        ]

        self.query = query
        monitoredRootPath = rootPath
        query.start()
    }

    private func stop() {
        query?.stop()
        query = nil
        monitoredRootPath = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }
}
#endif

enum CloudSyncError: LocalizedError {
    case containerUnavailable

    var errorDescription: String? {
        switch self {
        case .containerUnavailable:
            return "iCloud 容器不可用"
        }
    }
}

private extension JSONEncoder {
    static var prettyPrinted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var snapshotDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
