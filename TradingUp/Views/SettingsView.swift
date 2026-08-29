import SwiftUI

/// The settings screen: audio and haptic feedback. As of the home-screen refresh
/// this is reached from a gear on the main menu (not a Classic tab). Starting a
/// fresh run for either mode is handled from the main menu's mode buttons, which
/// offer Continue / New Run when a run is already in progress.
struct SettingsView: View {
    @Bindable private var sound = SoundManager.shared
    @Bindable private var haptics = HapticsManager.shared

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
