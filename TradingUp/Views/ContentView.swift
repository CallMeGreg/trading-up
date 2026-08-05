import SwiftUI

struct ContentView: View {
    @Environment(GameState.self) var game: GameState

    var body: some View {
        TabView {
            ShopView()
                .tabItem { Label("Shop", systemImage: "bag.fill") }
            CollectionView()
                .tabItem { Label("Collection", systemImage: "square.grid.3x3.fill") }
            StatsView()
                .tabItem { Label("Stats", systemImage: "chart.bar.fill") }
        }
        .tint(Palette.money)
        .fullScreenCover(item: overlayBinding) { overlay in
            switch overlay {
            case .welcome: WelcomeView()
            case .win:     WinView()
            case .lose:    LoseView()
            }
        }
        .alert(game.loadIssue?.title ?? "", isPresented: loadIssueBinding) {
            Button("OK", role: .cancel) { game.dismissLoadIssue() }
        } message: {
            Text(game.loadIssue?.message ?? "")
        }
    }

    /// Which full-screen overlay (if any) the current model state calls for.
    /// A single cover handles all three so transitions like Game Over →
    /// New Game → Welcome swap content in place instead of fighting over
    /// two separate presentations.
    private var activeOverlay: AppOverlay? {
        if game.shouldShowWelcome { return .welcome }
        // A pack/box reveal owns the screen until the player finishes its
        // summary. Win and Game Over both wait for it (`presentsWin` /
        // `presentsGameOver`), so a collection-completing — or wallet-emptying —
        // pull plays out fully instead of being cut off by the overlay sliding
        // in on top of the reveal.
        if game.presentsWin { return .win }
        if game.presentsGameOver { return .lose }
        return nil
    }

    /// Model-driven; dismissal happens when the state clears (markWelcomeSeen /
    /// acknowledgeWin / newGame), so the setter is intentionally a no-op.
    private var overlayBinding: Binding<AppOverlay?> {
        Binding(get: { activeOverlay }, set: { _ in })
    }

    /// Presents the save-load notice until the player dismisses it.
    private var loadIssueBinding: Binding<Bool> {
        Binding(get: { game.loadIssue != nil },
                set: { if !$0 { game.dismissLoadIssue() } })
    }
}

enum AppOverlay: Int, Identifiable {
    case welcome, win, lose
    var id: Int { rawValue }
}
