import SwiftUI

@main
struct TradingUpApp: App {
    // The Chase (v2) root. One shared observable engine, loaded from disk (or
    // seeded once from a v1/v2 collection on first 2.0 launch). Runs on the main
    // actor; App.init is on the main thread.
    @State private var chase = ChaseState()

    init() {
        // Decode the SFX and warm the audio session so the first pack-open is instant.
        SoundManager.shared.preloadAll()
    }

    var body: some Scene {
        WindowGroup {
            ChaseRootView()
                .environment(chase)
                .preferredColorScheme(.dark)
        }
    }
}
