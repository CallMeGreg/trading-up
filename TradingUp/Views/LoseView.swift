import SwiftUI

/// Shown when the player can't afford a pack and has no sellable duplicates.
/// Doubles as a "look what you pulled" review: the run's collection is laid out
/// as scrollable, per-set carousels, with the reset kept one clear tap away.
struct LoseView: View {
    @Environment(GameState.self) var game: GameState
    private var s: Stats { game.stats }
    @State private var confirmNew = false
    @State private var selected: Card?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "2a1414"), Palette.bg0],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    header
                    statsRow
                    CollectionReview { selected = $0 }
                }
                .padding(16)
                .readableWidth()
            }
        }
        .safeAreaInset(edge: .bottom) { resetBar }
        .sheet(item: $selected) { card in
            CardDetailView(card: card)
        }
        .onAppear { Haptics.play(.error) }
        .alert("Start a new game?", isPresented: $confirmNew) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { Haptics.play(.medium); game.newGame() }
        } message: {
            Text("This erases your collection and starts over with \(Economy.startingCash.money).")
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("💸").font(.system(size: 64)).padding(.top, 28)
            Text("TAPPED OUT")
                .font(.system(size: 14, weight: .black)).tracking(3)
                .foregroundStyle(Color(hex: "e0663b"))
            Text("Game Over")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Text("You're down to \(game.cash.money) — not enough for the \(game.cheapestPackPrice.money) cheapest pack. But look what you pulled along the way.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Palette.subtle)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            StatTile(label: "Unique Cards", value: "\(game.uniqueCount)/\(game.totalCards)", tint: Color(hex: "b06cf7"))
            StatTile(label: "Packs Opened", value: "\(s.packsOpened)")
            StatTile(label: "Best Grade", value: s.bestGrade == 0 ? "—" : "PSA \(s.bestGrade)", tint: Color(hex: "ffd54a"))
        }
    }

    /// Pinned to the bottom so "start a new run" stays obvious no matter how far
    /// the player has scrolled through their haul. The fade lets cards slide
    /// under it without a hard seam.
    private var resetBar: some View {
        BigButton(title: "New Run",
                  subtitle: "Dust off and start again",
                  systemImage: "arrow.counterclockwise",
                  tint: [Color(hex: "e0663b"), Color(hex: "c0442b")]) {
            confirmNew = true
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .readableWidth()
        .background(
            LinearGradient(colors: [Palette.bg0.opacity(0), Color(hex: "1a0d0d").opacity(0.9), Color(hex: "12070a")],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
        )
    }
}
