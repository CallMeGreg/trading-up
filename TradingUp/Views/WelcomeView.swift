import SwiftUI

/// Quick intro shown on first launch and after starting a new game. Explains
/// the core loop plus how you win and lose.
struct WelcomeView: View {
    @EnvironmentObject var game: GameState

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "10192e"), Palette.bg0],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            RadialGradient(gradient: Gradient(colors: [Palette.money.opacity(0.28), .clear]),
                           center: .top, startRadius: 20, endRadius: 480)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    Text("🎴").font(.system(size: 72)).padding(.top, 32)

                    VStack(spacing: 6) {
                        Text("WELCOME TO")
                            .font(.system(size: 13, weight: .black)).tracking(3)
                            .foregroundStyle(Palette.subtle)
                        Text("Trading Up")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        infoRow("📦", "Buy & open packs",
                                "Six cards a pack — 3 common, 2 uncommon, and a rare or ultra.")
                        infoRow("💰", "Sell your extras",
                                "Turn duplicate copies into cash. You can never sell the last copy of a card, though.")
                        infoRow("🎁", "Cash in bonuses",
                                "Complete evolution lines and full sets for payouts. New sets unlock as your collection grows.")
                        infoRow("🔍", "Grade rares & ultras",
                                "Pay to grade a rare or ultra and roll a PSA score — it can multiply the card's value or leave it worth far less.")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panel()

                    VStack(alignment: .leading, spacing: 14) {
                        goalRow("🏆", "How you win",
                                "Collect all \(game.totalCards) cards across the five sets.",
                                Palette.money)
                        Rectangle().fill(Palette.stroke).frame(height: 1)
                        goalRow("💸", "How you lose",
                                "Can't afford the \(game.cheapestPackPrice.money) cheapest pack, with no duplicate cards left to sell.",
                                Color(hex: "e0663b"))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panel()

                    BigButton(title: "Start Collecting", systemImage: "sparkles",
                              tint: [Palette.money, Color(hex: "39b56a")]) {
                        Haptics.play(.success)
                        game.markWelcomeSeen()
                    }
                    .padding(.top, 4)
                }
                .padding(16)
            }
        }
    }

    private func infoRow(_ emoji: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(emoji).font(.system(size: 26)).frame(width: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Palette.text)
                Text(body)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.subtle)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func goalRow(_ emoji: String, _ title: String, _ body: String, _ tint: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(emoji).font(.system(size: 26)).frame(width: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(title.uppercased())
                    .font(.system(size: 12, weight: .black)).tracking(1)
                    .foregroundStyle(tint)
                Text(body)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
