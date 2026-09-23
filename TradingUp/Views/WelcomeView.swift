import SwiftUI

/// Classic's intro and replayable help. Explains the core loop plus how you
/// win and lose without changing the current run when opened as a reference.
struct WelcomeView: View {
    @Environment(GameState.self) var game: GameState
    @Environment(\.dismiss) private var dismiss
    var isReference = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "10192e"), Palette.bg0],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            RadialGradient(gradient: Gradient(colors: [Palette.money.opacity(0.28), .clear]),
                           center: .top, startRadius: 20, endRadius: 480)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                // There's not much to read here, so nobody should have to scroll
                // to find the button that starts the game. Try the roomy layout
                // first and step down through tighter spacing until one fits;
                // scrolling is the last resort (small phones, landscape). The
                // greedy frame lets the button settle near the bottom so it stays
                // reachable without scrolling, however tall the screen.
                ViewThatFits(in: .vertical) {
                    explainer(.roomy)
                    explainer(.compact)
                    explainer(.tight)
                    ScrollView { explainer(.tight) }
                }
                .frame(maxHeight: .infinity)

                BigButton(title: isReference ? "Back to Game" : "Start Collecting",
                          systemImage: isReference ? "arrow.left" : "sparkles",
                          tint: [Palette.money, Color(hex: "39b56a")]) {
                    if isReference {
                        Haptics.play(.light)
                        Sound.play(.uiBack)
                        dismiss()
                    } else {
                        Haptics.play(.success)
                        game.markWelcomeSeen()
                    }
                }
            }
            .padding(16)
            .readableWidth()
        }
    }

    private func explainer(_ d: Density) -> some View {
        VStack(spacing: d.stack) {
            VStack(spacing: 6) {
                Text(isReference ? "HOW TO PLAY" : "WELCOME TO")
                    .font(.system(size: 13, weight: .black)).tracking(3)
                    .foregroundStyle(Palette.subtle)
                Text("Trading Up")
                    .font(.system(size: d.wordmark, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text("Classic Mode")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(Palette.money)
            }

            VStack(alignment: .leading, spacing: d.infoRows) {
                infoRow(d, "📦", "Buy & open packs",
                        "Six cards a pack — 3 common, 2 uncommon, and a rare or ultra.")
                infoRow(d, "🤝", "Plan with collectors",
                        "Exchange normal spares for cash or a missing card. Your last and best copies stay safe.")
                infoRow(d, "💰", "Sell or grade extras",
                        "The shop pays \(Int((Economy.sellbackRate * 100).rounded()))% of market value. Grading costs cash and can raise or lower value.")
                infoRow(d, "🎁", "Cash in bonuses",
                        "Complete evolution lines and full sets for payouts. New sets unlock as your collection grows.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel(d.panelPad)

            VStack(alignment: .leading, spacing: d.goalRows) {
                goalRow(d, "🏆", "How you win",
                        "Collect all \(game.totalCards) cards across the five sets.",
                        Palette.money)
                Rectangle().fill(Palette.stroke).frame(height: 1)
                goalRow(d, "💸", "How you lose",
                        "Can't afford the \(game.cheapestPackPrice.money) cheapest pack after selling extras, with no ready collector deals to help.",
                        Color(hex: "e0663b"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel(d.panelPad)
        }
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
        var wordmark: CGFloat
        var stack: CGFloat
        var infoRows: CGFloat
        var goalRows: CGFloat
        var panelPad: CGFloat
        var rowEmoji: CGFloat
        var rowTitle: CGFloat
        var rowBody: CGFloat

        static let roomy = Density(wordmark: 32, stack: 18, infoRows: 16, goalRows: 14,
                                   panelPad: 16, rowEmoji: 26, rowTitle: 15, rowBody: 13)
        static let compact = Density(wordmark: 30, stack: 13, infoRows: 12, goalRows: 11,
                                     panelPad: 14, rowEmoji: 24, rowTitle: 15, rowBody: 13)
        static let tight = Density(wordmark: 26, stack: 9, infoRows: 9, goalRows: 8,
                                   panelPad: 11, rowEmoji: 21, rowTitle: 14, rowBody: 12)
    }
}
