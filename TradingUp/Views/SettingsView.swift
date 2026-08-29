import SwiftUI

/// The settings screen: audio and haptic feedback, plus the "start over" resets
/// for each mode. As of the home-screen refresh this is reached from a gear on
/// the main menu (not a Classic tab), so it governs the whole app — it can reset
/// the Classic run *and* discard a saved Gauntlet run.
struct SettingsView: View {
    @Environment(GameState.self) var game: GameState
    @Bindable private var sound = SoundManager.shared
    @Bindable private var haptics = HapticsManager.shared
    @State private var confirmNew = false
    @State private var confirmResetGauntlet = false
    /// Whether there's a resumable Gauntlet run to offer resetting. Read once when
    /// the sheet opens so the control only appears when it does something.
    @State private var hasGauntletRun = GauntletRunStore().hasSavedRun

    /// Dismisses the settings sheet. Left `nil` anywhere Settings is shown without
    /// its own dismissal affordance, which hides the Done button.
    var onExitToMenu: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 14) {
                            header("Feedback")
                            Toggle(isOn: $sound.isEnabled) {
                                Label("Sound Effects",
                                      systemImage: sound.isEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Palette.text)
                            }
                            .tint(Palette.money)
                            .onChange(of: sound.isEnabled) { _, on in
                                Haptics.play(.light)
                                if on { Sound.play(.coin) }   // brief confirmation you can hear
                            }

                            Toggle(isOn: $haptics.isEnabled) {
                                Label("Haptics",
                                      systemImage: haptics.isEnabled ? "iphone.radiowaves.left.and.right" : "iphone.slash")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Palette.text)
                            }
                            .tint(Palette.money)
                            .onChange(of: haptics.isEnabled) { _, on in
                                if on { Haptics.play(.medium) }   // a buzz you can feel, once it's back on
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .panel()

                        Button {
                            confirmNew = true
                        } label: {
                            Label("New Game", systemImage: "arrow.counterclockwise")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color(hex: "e0663b"))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(hex: "e0663b").opacity(0.5), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("newGame")
                        .alert("Start a new game?", isPresented: $confirmNew) {
                            Button("Cancel", role: .cancel) {}
                            Button("Reset", role: .destructive) { game.newGame() }
                        } message: {
                            Text("This erases your current Classic collection and cash, and starts over with \(Economy.startingCash.money). Your all-time record is kept.")
                        }

                        if hasGauntletRun {
                            Button {
                                confirmResetGauntlet = true
                            } label: {
                                Label("Reset Gauntlet Run", systemImage: "bolt.slash.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(Color(hex: "b98cff"))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(hex: "b98cff").opacity(0.5), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("resetGauntletRun")
                            .alert("Reset your Gauntlet run?", isPresented: $confirmResetGauntlet) {
                                Button("Cancel", role: .cancel) {}
                                Button("Reset", role: .destructive) {
                                    GauntletRunStore().clear()
                                    hasGauntletRun = false
                                    Haptics.play(.warning)
                                }
                            } message: {
                                Text("This discards your in-progress Gauntlet run so it won't resume. Your unlocked trainers and difficulties are kept.")
                            }
                        }
                    }
                    .padding(16)
                    .readableWidth()
                }
            }
            .background(Palette.screen.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var topBar: some View {
        HStack {
            Text("Settings")
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(Palette.text)
            Spacer()
            if let onExitToMenu {
                Button {
                    Haptics.play(.light)
                    onExitToMenu()
                } label: {
                    Text("Done")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Palette.tapCue)
                }
                .accessibilityIdentifier("exitToMenu")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .readableWidth()
        .frame(maxWidth: .infinity)
        .background(Palette.bg1.opacity(0.96))
        .overlay(alignment: .bottom) {
            Rectangle().fill(.white.opacity(0.07)).frame(height: 1)
        }
    }

    private func header(_ t: String) -> some View {
        Text(t.uppercased()).font(.system(size: 12, weight: .black)).foregroundStyle(Palette.subtle)
    }
}
