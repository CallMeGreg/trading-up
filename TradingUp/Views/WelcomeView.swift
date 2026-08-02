import SwiftUI

/// Quick intro shown on first launch and after starting a new game. Explains
/// the core loop plus how you win and lose.
struct WelcomeView: View {
    @Environment(GameState.self) var game: GameState

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "10192e"), Palette.bg0],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            RadialGradient(gradient: Gradient(colors: [Palette.money.opacity(0.28), .clear]),
                           center: .top, startRadius: 20, endRadius: 480)
                .ignoresSafeArea()

            // There's not much to read here, so nobody should have to scroll to
            // find the button that starts the game. Try the roomy layout first
            // and step down through tighter spacing until one fits the screen;
            // scrolling is only the last resort, for the cases where even the
            // tightest layout can't fit (small phones, landscape).
            ViewThatFits(in: .vertical) {
                content(.roomy)
                content(.compact)
                content(.tight)
                ScrollView { content(.tight) }
            }
        }
    }

    private func content(_ d: Density) -> some View {
        VStack(spacing: d.stack) {
            Text("🎴").font(.system(size: d.hero))

            VStack(spacing: 6) {
                Text("WELCOME TO")
                    .font(.system(size: 13, weight: .black)).tracking(3)
                    .foregroundStyle(Palette.subtle)
                Text("Trading Up")
                    .font(.system(size: d.wordmark, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: d.infoRows) {
                infoRow(d, "📦", "Buy & open packs",
                        "Six cards a pack — 3 common, 2 uncommon, and a rare or ultra.")
                infoRow(d, "💰", "Sell your extras",
                        "Turn duplicate copies into cash. You can never sell the last copy of a card, though.")
                infoRow(d, "🎁", "Cash in bonuses",
                        "Complete evolution lines and full sets for payouts. New sets unlock as your collection grows.")
                infoRow(d, "🔍", "Grade rares & ultras",
                        "Pay to grade a rare or ultra and roll a PSA score — it can multiply the card's value or leave it worth far less.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel(d.panelPad)

            VStack(alignment: .leading, spacing: d.goalRows) {
                goalRow(d, "🏆", "How you win",
                        "Collect all \(game.totalCards) cards across the five sets.",
                        Palette.money)
                Rectangle().fill(Palette.stroke).frame(height: 1)
                goalRow(d, "💸", "How you lose",
                        "Can't afford the \(game.cheapestPackPrice.money) cheapest pack — even after selling every duplicate you own.",
                        Color(hex: "e0663b"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel(d.panelPad)

            BigButton(title: "Start Collecting", systemImage: "sparkles",
                      tint: [Palette.money, Color(hex: "39b56a")]) {
                Haptics.play(.success)
                game.markWelcomeSeen()
            }
        }
        .padding(d.outerPad)
        .readableWidth()
    }

    private func infoRow(_ d: Density, _ emoji: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(emoji).font(.system(size: d.rowEmoji)).frame(width: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: d.rowTitle, weight: .bold))
                    .foregroundStyle(Palette.text)
                Text(body)
                    .font(.system(size: d.rowBody, weight: .medium))
                    .foregroundStyle(Palette.subtle)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func goalRow(_ d: Density, _ emoji: String, _ title: String, _ body: String, _ tint: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(emoji).font(.system(size: d.rowEmoji)).frame(width: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(title.uppercased())
                    .font(.system(size: 12, weight: .black)).tracking(1)
                    .foregroundStyle(tint)
                Text(body)
                    .font(.system(size: d.rowBody, weight: .medium))
                    .foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// How generously the intro is spaced. `ViewThatFits` walks these from
    /// roomiest to tightest and picks the first one the screen can hold.
    fileprivate struct Density {
        var hero: CGFloat
        var wordmark: CGFloat
        var stack: CGFloat
        var infoRows: CGFloat
        var goalRows: CGFloat
        var panelPad: CGFloat
        var rowEmoji: CGFloat
        var rowTitle: CGFloat
        var rowBody: CGFloat
        var outerPad: CGFloat

        static let roomy = Density(hero: 68, wordmark: 32, stack: 18, infoRows: 16, goalRows: 14,
                                   panelPad: 16, rowEmoji: 26, rowTitle: 15, rowBody: 13, outerPad: 16)
        static let compact = Density(hero: 52, wordmark: 30, stack: 13, infoRows: 12, goalRows: 11,
                                     panelPad: 14, rowEmoji: 24, rowTitle: 15, rowBody: 13, outerPad: 14)
        static let tight = Density(hero: 38, wordmark: 26, stack: 9, infoRows: 9, goalRows: 8,
                                   panelPad: 11, rowEmoji: 21, rowTitle: 14, rowBody: 12, outerPad: 10)
    }
}
