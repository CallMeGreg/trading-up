import SwiftUI

/// Shown when the player can't afford a pack and has no sellable duplicates.
struct LoseView: View {
    @Environment(GameState.self) var game: GameState
    private var s: Stats { game.stats }
    @State private var confirmNew = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "2a1414"), Palette.bg0],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    Text("💸").font(.system(size: 72)).padding(.top, 36)
                    VStack(spacing: 6) {
                        Text("TAPPED OUT")
                            .font(.system(size: 14, weight: .black)).tracking(3)
                            .foregroundStyle(Color(hex: "e0663b"))
                        Text("Game Over")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text("You're down to \(game.cash.money) — not enough for the \(game.cheapestPackPrice.money) cheapest pack, and no cards left to sell. But look how far you got!")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Palette.subtle)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 12) {
                        StatTile(label: "Unique Cards", value: "\(game.uniqueCount)/\(game.totalCards)", tint: Color(hex: "b06cf7"))
                        StatTile(label: "Packs Opened", value: "\(s.packsOpened)")
                        StatTile(label: "Best Grade", value: s.bestGrade == 0 ? "—" : "PSA \(s.bestGrade)", tint: Color(hex: "ffd54a"))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("CARDS COLLECTED BY SET").font(.system(size: 12, weight: .black)).foregroundStyle(Palette.subtle)
                        SetBreakdown()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panel()

                    BigButton(title: "Try Again", subtitle: "Erases this collection and starts over",
                              systemImage: "arrow.counterclockwise",
                              tint: [Color(hex: "e0663b"), Color(hex: "c0442b")]) {
                        confirmNew = true
                    }
                }
                .padding(16)
                .readableWidth()
            }
        }
        .onAppear { Haptics.play(.error) }
        .alert("Start a new game?", isPresented: $confirmNew) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { Haptics.play(.medium); game.newGame() }
        } message: {
            Text("This erases your collection and starts over with \(Economy.startingCash.money).")
        }
    }
}
