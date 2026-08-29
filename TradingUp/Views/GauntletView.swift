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
        .overlay(alignment: .topLeading) { closeButton }
    }

    @ViewBuilder
    private func content(_ state: GauntletState) -> some View {
        switch state.phase {
        case .intro:         IntroScreen(state: state)
        case .trainerSelect: TrainerSelectScreen(state: state)
        case .tierSelect:    TierSelectScreen(state: state)
        case .ripping:       RunScreen(state: state)
        case .shop:          ShopScreen(state: state)
        case .reward:        RewardScreen(state: state)
        case .results:       ResultsScreen(state: state) { dismiss() }
        case .lost:          LostScreen(state: state) { dismiss() }
        }
    }

    private var closeButton: some View {
        Button {
            Haptics.play(.light)
            state?.persistForExit()   // resume this run next time (req 11)
            dismiss()
        } label: {
            Image(systemName: "house.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Palette.text)
                .frame(width: 38, height: 38)
                .background(Circle().fill(.black.opacity(0.30)))
                .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(10)
        .accessibilityLabel("Home")
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
}
