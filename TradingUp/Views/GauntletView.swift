import SwiftUI

/// Gauntlet Mode — the roguelite loop. This is the host: it builds the
/// `GauntletState` driver from the shared, Binder-owning `GameState`, paints the
/// signature purple backdrop, and swaps in the screen for the current phase.
/// Every game rule lives behind `GauntletState`; these views just present it.
///
/// Reached only when the Full Game is unlocked (the menu routes locked taps to the
/// paywall instead), so there's no entitlement check to do here. See §14.
struct GauntletView: View {
    @Environment(GameState.self) private var game
    @Environment(\.dismiss) private var dismiss
    @State private var state: GauntletState?

    var body: some View {
        ZStack {
            GauntletBackdrop()
            if let state {
                content(state)
                    .readableWidth()
                    .padding(20)
            }
        }
        .task { if state == nil { state = GauntletState(game: game) } }
        // The run screen carries its own inline Home button in the HUD row, so the
        // floating corner button steps aside during ripping (req 11).
        .overlay(alignment: .topLeading) {
            if let state, state.phase != .ripping {
                GauntletCornerButton(systemImage: "house.fill", label: "Home", action: goHome)
                    .padding(10)
            }
        }
        // The Gauntlet primer lives behind an info button that mirrors the Home
        // button's size and vertical position for a consistent look (req 2).
        .overlay(alignment: .topTrailing) {
            if let state, state.phase == .trainerSelect {
                GauntletCornerButton(systemImage: "info.circle.fill", label: "How Gauntlet works") {
                    Haptics.play(.light)
                    state.showIntro()
                }
                .padding(10)
            }
        }
    }

    @ViewBuilder
    private func content(_ state: GauntletState) -> some View {
        switch state.phase {
        case .intro:         IntroScreen(state: state)
        case .trainerSelect: TrainerSelectScreen(state: state)
        case .tierSelect:    TierSelectScreen(state: state)
        case .ripping:       RunScreen(state: state, onHome: goHome)
        case .shop:          ShopScreen(state: state)
        case .reward:        RewardScreen(state: state)
        case .results:       ResultsScreen(state: state) { dismiss() }
        case .lost:          LostScreen(state: state) { dismiss() }
        }
    }

    private func goHome() {
        Haptics.play(.light)
        state?.persistForExit()   // resume this run next time (req 11)
        dismiss()
    }
}

/// A round corner control shared by the Home and info buttons so they read as a
/// matched pair — same 38pt circle, same styling, mirrored across the top row.
struct GauntletCornerButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Palette.text)
                .frame(width: 38, height: 38)
                .background(Circle().fill(.black.opacity(0.30)))
                .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// The mode's shared backdrop: a deep violet wash with a top glow, distinct from
/// Classic's blue so the two modes read apart at a glance.
struct GauntletBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "1a0d2e"), Palette.bg0],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            RadialGradient(gradient: Gradient(colors: [Color(hex: "b06cf7").opacity(0.24), .clear]),
                           center: .top, startRadius: 20, endRadius: 480)
                .ignoresSafeArea()
        }
    }
}

/// The mode's accent gradient, reused on primary actions and headers.
enum GauntletTheme {
    static let tint = [Color(hex: "6d5cf7"), Color(hex: "b06cf7")]
    static let gold = [Color(hex: "ffd54a"), Color(hex: "ff8ad6")]
    /// Gold treatment for the Hard finale — presented to the player as the
    /// "Collection Championship" so its shop CTA reads as the title round.
    static let championship = [Color(hex: "e2942f"), Color(hex: "d0701f")]
}
