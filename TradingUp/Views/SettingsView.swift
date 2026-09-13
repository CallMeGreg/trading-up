import SwiftUI

/// Audio, haptic feedback, and pack-opening settings, reached from the main
/// menu's gear (not a Classic tab). Fresh runs start from the mode buttons,
/// which offer Continue / New Run when a run is already in progress.
struct SettingsView: View {
    @Bindable private var sound = SoundManager.shared
    @Bindable private var haptics = HapticsManager.shared
    @Bindable private var packOpening = PackOpeningPreferences.shared

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
                            header("Audio")
                            AudioVolumeRow(channel: sound.preferences.music, title: "Music",
                                           identifier: "music") {}
                            Divider().overlay(Palette.stroke)
                            AudioVolumeRow(channel: sound.preferences.sfx, title: "SFX",
                                           identifier: "sfx") { Sound.play(.toggleOn) }
                            Text("Tap a speaker to mute. Tap again to restore your previous volume. Music stays quiet while another app's audio needs priority.")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Palette.subtle)
                            if let message = sound.errorMessage {
                                Text(message)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color(hex: "e0663b"))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .panel()
                        VStack(alignment: .leading, spacing: 14) {
                            header("Pack opening")
                            packOpeningToggle(
                                "Tap to open packs",
                                isOn: $packOpening.tapToOpenPacks,
                                identifier: "tapToOpenPacks",
                                description: "Tap anywhere on the pack to open it. Swiping the top seam still works."
                            )
                            Divider().overlay(Palette.stroke)
                            packOpeningToggle(
                                "Auto open packs",
                                isOn: $packOpening.autoOpenPacks,
                                identifier: "autoOpenPacks",
                                description: "After opening, skip the card-by-card reveal and go straight to the pack summary. You still decide what to keep or sell."
                            )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .panel()
                        VStack(alignment: .leading, spacing: 14) {
                            header("Feedback")
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
                    Sound.play(.uiBack)
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

    private func packOpeningToggle(_ title: String, isOn: Binding<Bool>,
                                   identifier: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: isOn) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.text)
            }
            .tint(Palette.money)
            .accessibilityIdentifier(identifier)
            .accessibilityHint(description)
            .onChange(of: isOn.wrappedValue) { _, on in
                Haptics.play(.light)
                Sound.play(on ? .toggleOn : .uiTap)
            }
            Text(description)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.subtle)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
