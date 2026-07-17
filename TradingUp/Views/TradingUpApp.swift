import SwiftUI

@main
struct TradingUpApp: App {
    @StateObject private var game = GameState()

    init() {
        // Decode the SFX and warm the audio session so the first pack-open is instant.
        SoundManager.shared.preloadAll()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(game)
                .preferredColorScheme(.dark)
        }
    }
}
