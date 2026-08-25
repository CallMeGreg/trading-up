import SwiftUI
import UIKit

/// Shown when all 250 cards are collected. Terminal, celebratory — and made
/// personal: the run is minted into a one-of-a-kind holographic "collector card"
/// (`CollectorCardView`) under live fireworks, so every winner gets a trophy that
/// reflects how *they* won and is worth screenshotting.
struct WinView: View {
    @Environment(GameState.self) var game: GameState

    /// Rendered snapshot of the win, shared as an image. Built on appear.
    @State private var shareImage: Image?
    @State private var confirmNew = false
    /// Drives the card's entrance and the fireworks fade-in.
    @State private var reveal = false

    /// Rasterize `WinShareCard` so the share sheet can attach it as an image.
    @MainActor private func renderShareImage() {
        let card = WinShareCard(
            signature: game.runSignature,
            totalCards: game.totalCards,
            ownedBySet: (1...CardDatabase.setCount).map { game.ownedCount(inSet: $0) }
        )
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        guard let ui = renderer.uiImage else { return }
        shareImage = Image(uiImage: ui)
    }

    var body: some View {
        let sig = game.runSignature
        ZStack {
            background(sig.element)
            FireworksView(palette: fireworkPalette(sig.element))
                .ignoresSafeArea()
                .opacity(reveal ? 1 : 0)

            ScrollView {
                VStack(spacing: 18) {
                    header
                    heroCard(sig)
                    identity(sig)
                    shareButton
                    keepButton
                    playAgainButton
                    GuildPanel()
                    setsPanel
                }
                .padding(16)
                .readableWidth()
            }
        }
        .onAppear {
            Haptics.play(.success)
            renderShareImage()
            withAnimation(.spring(response: 0.72, dampingFraction: 0.6).delay(0.15)) {
                reveal = true
            }
        }
        .alert("Start a new Season?", isPresented: $confirmNew) {
            Button("Cancel", role: .cancel) {}
            Button("New Season", role: .destructive) { Haptics.play(.success); game.startNewSeason() }
        } message: {
            Text("This banks your Championship and starts a fresh Season with a new binder. Your Guild upgrades, Renown and milestones carry over. Choose \"Keep Browsing\" instead to go on admiring this run.")
        }
    }

    // MARK: Pieces

    private func background(_ e: Element) -> some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "1a1030"), Palette.bg0],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(gradient: Gradient(colors: [e.palette[1].opacity(0.4), .clear]),
                           center: .top, startRadius: 20, endRadius: 520)
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("SEASON CHAMPION")
                .font(.system(size: 13, weight: .black)).tracking(3)
                .foregroundStyle(Color(hex: "ffd54a"))
            Text("You cleared all \(game.seasonShows) Shows")
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 24)
    }

    /// The hero: the collector card, sized to the widest that fits, springing in
    /// with a glow behind it.
    private func heroCard(_ sig: RunSignature) -> some View {
        ViewThatFits(in: .horizontal) {
            CollectorCardView(signature: sig, width: 320)
            CollectorCardView(signature: sig, width: 300)
            CollectorCardView(signature: sig, width: 280)
            CollectorCardView(signature: sig, width: 260)
            CollectorCardView(signature: sig, width: 240)
        }
        .background {
            GlowBurst(color: sig.rank.color, diameter: 300 * 1.7)
                .opacity(reveal ? 1 : 0)
        }
        .scaleEffect(reveal ? 1 : 0.72)
        .opacity(reveal ? 1 : 0)
        .rotation3DEffect(.degrees(reveal ? 0 : 34), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        .padding(.vertical, 4)
    }

    /// The earned identity, spelled out below the card for emphasis.
    private func identity(_ sig: RunSignature) -> some View {
        VStack(spacing: 8) {
            (Text("You are ").foregroundStyle(Palette.subtle)
                + Text(sig.title).foregroundStyle(.white))
                .font(.system(size: 20, weight: .black, design: .rounded))
                .multilineTextAlignment(.center)
            Text(sig.accolade)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.subtle)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("COLLECTOR RANK \(sig.rank.letter) · \(sig.rank.word.uppercased())")
                .font(.system(size: 11, weight: .black)).tracking(2)
                .foregroundStyle(sig.rank.color)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(sig.rank.color.opacity(0.14)))
                .overlay(Capsule().strokeBorder(sig.rank.color.opacity(0.35), lineWidth: 1))
        }
        .opacity(reveal ? 1 : 0)
    }

    @ViewBuilder private var shareButton: some View {
        if let shareImage {
            ShareLink(item: shareImage,
                      preview: SharePreview("Trading Up", image: shareImage)) {
                BigButtonLabel(title: "Share your card",
                               subtitle: "Send your one-of-a-kind win",
                               systemImage: "square.and.arrow.up",
                               tint: [Color(hex: "3b82f6"), Color(hex: "6d5cf7")])
            }
            .buttonStyle(.plain)
        } else {
            BigButtonLabel(title: "Share your card",
                           subtitle: "Send your one-of-a-kind win",
                           systemImage: "square.and.arrow.up",
                           tint: [Color(hex: "3b82f6"), Color(hex: "6d5cf7")])
        }
    }

    private var keepButton: some View {
        BigButton(title: "Keep Browsing", systemImage: "square.grid.3x3.fill",
                  tint: [Palette.money, Color(hex: "39b56a")]) {
            Haptics.play(.light)
            game.acknowledgeWin()
        }
    }

    private var playAgainButton: some View {
        BigButton(title: "New Season", subtitle: "Fresh binder — keeps your Guild, Renown & milestones",
                  systemImage: "arrow.counterclockwise",
                  tint: [Color(hex: "b06cf7"), Color(hex: "6d5cf7")]) {
            confirmNew = true
        }
    }

    private var setsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("THIS SEASON'S BINDER")
                .font(.system(size: 12, weight: .black)).foregroundStyle(Palette.subtle)
            SetBreakdown()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    /// Festive sparks plus a splash of the player's dominant element, so even the
    /// fireworks nod to how they won.
    private func fireworkPalette(_ e: Element) -> [Color] {
        FireworksView.festive + [e.palette[0], e.palette[1]]
    }
}
