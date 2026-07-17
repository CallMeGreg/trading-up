import SwiftUI

struct ContentView: View {
    @EnvironmentObject var game: GameState

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
        .fullScreenCover(isPresented: endBinding) {
            if game.hasWon {
                WinView()
            } else {
                LoseView()
            }
        }
    }

    /// Terminal states are driven by the model; dismissal happens when `newGame()`
    /// clears the condition, so the setter is intentionally a no-op.
    private var endBinding: Binding<Bool> {
        Binding(get: { game.hasWon || game.isGameOver }, set: { _ in })
    }
}
