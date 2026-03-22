import SwiftUI
import AVKit
import QuickLook
import UniformTypeIdentifiers

#if os(iOS)

struct IOSReaderView: View {
    var body: some View {
        NavigationStack {
            IOSMirrorDirectoryView(relativePath: "", title: "LM Reader", autoExpandSingleDirectoryChain: true)
                .toolbar(.hidden, for: .navigationBar)
        }
    }
}

private struct IOSMirrorDirectoryView: View {
    let relativePath: String
    let title: String
    let autoExpandSingleDirectoryChain: Bool

    @Environment(\.scenePhase) private var scenePhase
    @State private var entries: [CloudMirrorEntry] = []
    @State private var statusMessage = "正在读取 Mac 文件夹"
    @State private var searchText = ""
    @State private var effectiveRelativePath: String
    @State private var effectiveTitle: String

    init(relativePath: String, title: String, autoExpandSingleDirectoryChain: Bool = false) {
        self.relativePath = relativePath
        self.title = title
        self.autoExpandSingleDirectoryChain = autoExpandSingleDirectoryChain
        _effectiveRelativePath = State(initialValue: relativePath)
        _effectiveTitle = State(initialValue: title)
    }

    var body: some View {
        Group {
            if filteredEntries.isEmpty {
                ContentUnavailableView(
                    "等待 Mac 文件夹同步",
                    systemImage: "folder.badge.questionmark",
                    description: Text(statusMessage)
                )
            } else {
                List(filteredEntries) { entry in
                    if entry.isDirectory {
                        NavigationLink {
                            IOSMirrorDirectoryView(relativePath: entry.relativePath, title: entry.name)
                        } label: {
                            Label(entry.name, systemImage: "folder")
                        }
                    } else {
                        NavigationLink {
                            IOSMirrorFileView(relativePath: entry.relativePath, title: entry.name)
                        } label: {
                            Label(entry.name, systemImage: "doc.text")
                        }
                        .onDrag {
                            dragItemProvider(for: entry)
                        }
                        .contextMenu {
                            if let fileURL = try? CloudSyncService.mirroredFileURL(relativePath: entry.relativePath) {
                                ShareLink(item: fileURL) {
                                    Label("发送到其他 App", systemImage: "square.and.arrow.up")
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(effectiveTitle)
        .searchable(text: $searchText, prompt: "搜索当前文件夹")
        .task {
            CloudSyncService.startMonitoringUbiquitousMirror()
            await loadDirectory()
        }
        .refreshable {
            await loadDirectory(forceReloadRootPath: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .cloudMirrorContentsDidChange)) { _ in
            Task {
                await loadDirectory(forceReloadRootPath: false)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await loadDirectory(forceReloadRootPath: false)
            }
        }
    }

    private var filteredEntries: [CloudMirrorEntry] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return entries }
        return entries.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    private func dragItemProvider(for entry: CloudMirrorEntry) -> NSItemProvider {
        guard let fileURL = try? CloudSyncService.mirroredFileURL(relativePath: entry.relativePath),
              let provider = NSItemProvider(contentsOf: fileURL)
        else {
            let provider = NSItemProvider(object: entry.name as NSString)
            provider.suggestedName = entry.name
            return provider
        }

        provider.suggestedName = entry.name
        return provider
    }

    @MainActor
    private func loadDirectory(forceReloadRootPath: Bool = true) async {
        guard CloudSyncService.mirroredContentExists() else {
            statusMessage = "Mac 镜像还没完成，或上一次同步失败后留下了空目录"
            return
        }

        do {
            if autoExpandSingleDirectoryChain && relativePath.isEmpty && (forceReloadRootPath || effectiveRelativePath.isEmpty) {
                let preferredPath = try CloudSyncService.preferredMirrorRelativePath()
                effectiveRelativePath = preferredPath
                if let lastComponent = preferredPath.split(separator: "/").last, !lastComponent.isEmpty {
                    effectiveTitle = String(lastComponent).removingPercentEncoding ?? String(lastComponent)
                }
            }

            entries = try CloudSyncService.listMirroredDirectory(relativePath: effectiveRelativePath)
            statusMessage = entries.isEmpty ? "这个文件夹目前是空的" : "已读取 \(entries.count) 项"
        } catch {
            statusMessage = "读取文件夹失败：\(error.localizedDescription)"
        }
    }
}

private struct IOSMirrorFileView: View {
    let relativePath: String
    let title: String

    @Environment(\.scenePhase) private var scenePhase
    @State private var bodyMarkdown = "正在读取文件"
    @State private var loadFailed = false
    @State private var previewURL: URL?
    @State private var shareURL: URL?
    @State private var isPreparingBackgroundPlayback = false
    @State private var playbackErrorMessage: String?
    @StateObject private var playbackController = VideoPlaybackController.shared

    var body: some View {
        GeometryReader { geometry in
            let isFullscreenMedia = !loadFailed
                && geometry.size.width > geometry.size.height
                && previewURL != nil
            let isLandscapePreview = previewURL != nil && !loadFailed && geometry.size.width > geometry.size.height

            Group {
                if let previewURL, !loadFailed {
                    if isLandscapePreview {
                        QuickLookPreview(url: previewURL)
                            .id(previewURL.absoluteString + "-landscape")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(.systemBackground))
                            .ignoresSafeArea(edges: .all)
                    } else {
                        QuickLookPreview(url: previewURL)
                            .id(previewURL.absoluteString + "-portrait")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(.systemBackground))
                    }
                } else {
                    ScrollView {
                        if loadFailed {
                            ContentUnavailableView(
                                "文件读取失败",
                                systemImage: "exclamationmark.triangle",
                                description: Text(bodyMarkdown)
                            )
                            .padding(.top, 40)
                        } else {
                            Text(.init(bodyMarkdown))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(isFullscreenMedia ? .hidden : .visible, for: .navigationBar)
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if shouldOfferBackgroundPlayback {
                    Button {
                        Task {
                            await startBackgroundPlayback()
                        }
                    } label: {
                        if isPreparingBackgroundPlayback {
                            ProgressView()
                        } else {
                            Image(systemName: "video.fill")
                        }
                    }
                    .disabled(isPreparingBackgroundPlayback)
                }

                if let shareURL {
                    ShareLink(item: shareURL) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $playbackController.isPresented) {
            NativeVideoPlayer(player: playbackController.player)
                .ignoresSafeArea()
                .background(Color.black)
        }
        .alert("暂时不能进入后台播放", isPresented: playbackErrorIsPresented) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(playbackErrorMessage ?? "请稍后再试")
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                playbackController.handleDidEnterBackground()
            }
        }
        .task {
            await loadFile()
        }
    }

    @MainActor
    private func loadFile() async {
        do {
            let fileURL = try CloudSyncService.mirroredFileURL(relativePath: relativePath)
            shareURL = fileURL
            if Self.shouldPreviewInQuickLook(fileURL: fileURL) {
                previewURL = fileURL
                bodyMarkdown = ""
            } else {
                previewURL = nil
                bodyMarkdown = try CloudSyncService.readMirroredFile(relativePath: relativePath)
            }
            loadFailed = false
        } catch {
            bodyMarkdown = error.localizedDescription
            loadFailed = true
            shareURL = nil
        }
    }

    private var shouldOfferBackgroundPlayback: Bool {
        guard let shareURL else { return false }
        return Self.isVideoFile(fileURL: shareURL)
    }

    private var playbackErrorIsPresented: Binding<Bool> {
        Binding(
            get: { playbackErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    playbackErrorMessage = nil
                }
            }
        )
    }

    @MainActor
    private func startBackgroundPlayback() async {
        guard !isPreparingBackgroundPlayback else { return }
        isPreparingBackgroundPlayback = true
        defer { isPreparingBackgroundPlayback = false }

        do {
            let preparedURL = try await CloudSyncService.prepareMirroredFileForPlayback(relativePath: relativePath)
            playbackController.startPlayback(url: preparedURL, title: title)
        } catch {
            playbackErrorMessage = error.localizedDescription
        }
    }

    private static func shouldPreviewInQuickLook(fileURL: URL) -> Bool {
        let textExtensions = Set(["md", "markdown", "txt", "text"])
        if textExtensions.contains(fileURL.pathExtension.lowercased()) {
            return false
        }
        guard let type = UTType(filenameExtension: fileURL.pathExtension) else {
            return true
        }
        if type.conforms(to: .plainText) || type.conforms(to: .utf8PlainText) {
            return false
        }
        return true
    }

    private static func isVideoFile(fileURL: URL) -> Bool {
        guard let type = UTType(filenameExtension: fileURL.pathExtension) else {
            return false
        }
        return type.conforms(to: .movie) || type.conforms(to: .video)
    }
}

@MainActor
private final class VideoPlaybackController: ObservableObject {
    static let shared = VideoPlaybackController()

    @Published var isPresented = false
    let player = AVPlayer()
    private var currentURL: URL?

    private init() {
        player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        player.allowsExternalPlayback = true
    }

    func startPlayback(url: URL, title: String) {
        configureAudioSession()
        if currentURL != url {
            currentURL = url
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
        }
        player.play()
        isPresented = true
    }

    func handleDidEnterBackground() {
        guard isPresented, player.currentItem != nil else { return }
        configureAudioSession()
        if player.rate == 0 {
            player.play()
        }
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
            try session.setActive(true)
        } catch {
            print("Failed to reconfigure audio session: \(error.localizedDescription)")
        }
    }
}

private struct NativeVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.updatesNowPlayingInfoCenter = true
        controller.entersFullScreenWhenPlaybackBegins = true
        controller.exitsFullScreenWhenPlaybackEnds = false
        player.play()
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
        if player.rate == 0 {
            player.play()
        }
    }
}

private struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        context.coordinator.url = url
        controller.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

#endif
