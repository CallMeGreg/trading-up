import SwiftUI

/// The meta tab: audio, the way back to the main menu, and the new-game reset.
/// Split out of Stats in v2.0.0 so the numbers screen stays purely informational
/// and every "leave / restart" control lives together in one predictable place.
struct SettingsView: View {
    @Environment(GameState.self) var game: GameState
    @Bindable private var sound = SoundManager.shared
    @State private var confirmNew = false

    /// Provided by `ClassicModeView` so this tab can bow out to the main menu.
    /// Left `nil` anywhere Settings is shown on its own, which hides the button.
    var onExitToMenu: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        header("Sound")
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
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panel()

                    if let onExitToMenu {
                        Button {
                            Haptics.play(.light)
                            onExitToMenu()
                        } label: {
                            Label("Main Menu", systemImage: "house.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Palette.tapCue)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.tapCue.opacity(0.5), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("exitToMenu")
                    }

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
                }
                .padding(16)
                .readableWidth()
            }
            .background(Palette.screen.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .alert("Start a new game?", isPresented: $confirmNew) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) { game.newGame() }
            } message: {
                Text("This erases your current collection and cash, and starts over with \(Economy.startingCash.money). Your all-time record is kept.")
            }
        }
    }

    private func header(_ t: String) -> some View {
        Text(t.uppercased()).font(.system(size: 12, weight: .black)).foregroundStyle(Palette.subtle)
    }
}
