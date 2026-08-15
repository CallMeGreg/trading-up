import SwiftUI

@main
struct TradingUpApp: App {
    @State private var game: GameState
    @State private var purchases: PurchaseStore

    init() {
        // One shared GameState, with the StoreKit layer built on top of it so it
        // can push the verified entitlement in. Both are @MainActor; App.init
        // runs on the main thread.
        let game = GameState()
        _game = State(initialValue: game)
        _purchases = State(initialValue: PurchaseStore(game: game))
        // Decode the SFX and warm the audio session so the first pack-open is instant.
        SoundManager.shared.preloadAll()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(game)
                .environment(purchases)
                .preferredColorScheme(.dark)
        }
    }
}
