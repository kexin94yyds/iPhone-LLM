import SwiftData
import SwiftUI
#if os(iOS)
import AVFoundation
#endif

@main
struct LMReaderApp: App {
    @State private var appModel = AppModel()

    init() {
#if os(iOS)
        configureAudioSession()
#endif
    }

    var body: some Scene {
        WindowGroup {
#if os(iOS)
            IOSReaderView()
                .environment(appModel)
#else
            ContentView()
                .environment(appModel)
#endif
        }
#if os(macOS)
        .modelContainer(AppContainer.shared.container)
#endif
    }

#if os(iOS)
    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
            try session.setActive(true)
        } catch {
            print("Failed to configure audio session: \(error.localizedDescription)")
        }
    }
#endif
}
