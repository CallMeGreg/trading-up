import SwiftUI

/// Shown when all 250 cards are collected. Terminal, celebratory.
struct WinView: View {
    @EnvironmentObject var game: GameState
    private var s: Stats { game.stats }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "1a1030"), Palette.bg0],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            RadialGradient(gradient: Gradient(colors: [Color(hex: "b06cf7").opacity(0.4), .clear]),
                           center: .top, startRadius: 20, endRadius: 500)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    Text("🏆").font(.system(size: 76)).padding(.top, 32)
                    VStack(spacing: 6) {
                        Text("MASTER COLLECTOR")
                            .font(.system(size: 14, weight: .black)).tracking(3)
                            .foregroundStyle(Color(hex: "ffd54a"))
                        Text("You collected all \(game.totalCards)!")
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                        Text("Every Mythling across all five sets is yours.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Palette.subtle)
                            .multilineTextAlignment(.center)
                    }

                    HStack(spacing: 12) {
                        StatTile(label: "Net Worth", value: game.netWorth.moneyShort, tint: Palette.money)
                        StatTile(label: "Packs", value: "\(s.packsOpened)")
                        StatTile(label: "Boxes", value: "\(s.boxesOpened)")
                    }
                    HStack(spacing: 12) {
                        StatTile(label: "Foils", value: "\(s.foilsPulled)", tint: Color(hex: "ff8ad6"))
                        StatTile(label: "Ultras", value: "\(s.ultrasPulled)", tint: Color(hex: "b06cf7"))
                        StatTile(label: "Best Grade", value: s.bestGrade == 0 ? "—" : "PSA \(s.bestGrade)", tint: Color(hex: "ffd54a"))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("COMPLETE SETS").font(.system(size: 12, weight: .black)).foregroundStyle(Palette.subtle)
                        SetBreakdown()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panel()

                    BigButton(title: "Play Again", systemImage: "arrow.counterclockwise",
                              tint: [Color(hex: "b06cf7"), Color(hex: "6d5cf7")]) {
                        Haptics.play(.success)
                        game.newGame()
                    }
                }
                .padding(16)
            }
        }
        .onAppear { Haptics.play(.success); Sound.play(.win) }
    }
}
