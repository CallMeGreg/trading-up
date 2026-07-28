import SwiftUI
import UIKit

/// Shown when all 250 cards are collected. Terminal, celebratory.
struct WinView: View {
    @EnvironmentObject var game: GameState
    private var s: Stats { game.stats }

    /// Rendered snapshot of the win, shared as an image. Built on appear.
    @State private var shareImage: Image?
    @State private var confirmNew = false

    /// Rasterize `WinShareCard` so the share sheet can attach it as an image.
    @MainActor private func renderShareImage() {
        let card = WinShareCard(
            totalCards: game.totalCards,
            netWorth: game.netWorth,
            stats: s,
            ownedBySet: (1...CardDatabase.setCount).map { game.ownedCount(inSet: $0) }
        )
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        guard let ui = renderer.uiImage else { return }
        shareImage = Image(uiImage: ui)
    }


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
                        Text("Every Mythling is yours.")
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

                    if let shareImage {
                        ShareLink(item: shareImage,
                                  preview: SharePreview("Trading Up", image: shareImage)) {
                            BigButtonLabel(title: "Share with your friends",
                                           subtitle: "Send a screenshot of your win",
                                           systemImage: "square.and.arrow.up",
                                           tint: [Color(hex: "3b82f6"), Color(hex: "6d5cf7")])
                        }
                        .buttonStyle(.plain)
                    } else {
                        BigButtonLabel(title: "Share with your friends",
                                       subtitle: "Send a screenshot of your win",
                                       systemImage: "square.and.arrow.up",
                                       tint: [Color(hex: "3b82f6"), Color(hex: "6d5cf7")])
                    }

                    BigButton(title: "Keep My Collection", systemImage: "square.grid.3x3.fill",
                              tint: [Palette.money, Color(hex: "39b56a")]) {
                        Haptics.play(.light)
                        game.acknowledgeWin()
                    }

                    BigButton(title: "Play Again", subtitle: "Erases this collection and starts over",
                              systemImage: "arrow.counterclockwise",
                              tint: [Color(hex: "b06cf7"), Color(hex: "6d5cf7")]) {
                        confirmNew = true
                    }
                }
                .padding(16)
            }
        }
        .onAppear {
            Haptics.play(.success)
            renderShareImage()
        }
        .alert("Start a new game?", isPresented: $confirmNew) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { Haptics.play(.success); game.newGame() }
        } message: {
            Text("This erases your completed collection and starts over with \(Economy.startingCash.money). Choose \"Keep My Collection\" instead to go on browsing it.")
        }
    }
}
