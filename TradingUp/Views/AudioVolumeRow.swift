import SwiftUI

struct AudioVolumeRow: View {
    @Bindable var channel: AudioChannelSettings
    let title: String
    let identifier: String
    let onPreview: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    channel.toggleMute()
                    Haptics.play(.light)
                    if channel.isEnabled { onPreview() }
                } label: {
                    Image(systemName: channel.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(channel.isMuted ? Palette.subtle : Palette.money)
                        .frame(width: 44, height: 44)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.panelHi))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(channel.isMuted ? "Unmute" : "Mute") \(title)")
                .accessibilityIdentifier("\(identifier)Mute")
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.text)
                Spacer()
                Text(channel.isMuted ? "Muted" : "\(Int((channel.volume * 100).rounded()))%")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Palette.subtle)
                    .accessibilityIdentifier("\(identifier)VolumeLabel")
            }
            Slider(value: Binding(get: { channel.volume }, set: { level in
                // The first value update can precede the editing-start callback.
                channel.beginVolumeAdjustment()
                channel.volume = level
            }), in: 0...1, step: 0.01) { editing in
                if editing {
                    channel.beginVolumeAdjustment()
                } else {
                    channel.endVolumeAdjustment()
                    Haptics.play(.light)
                    if channel.isEnabled { onPreview() }
                }
            }
            .tint(Palette.money)
            .accessibilityLabel("\(title) volume")
            .accessibilityValue("\(Int((channel.volume * 100).rounded())) percent")
            .accessibilityIdentifier("\(identifier)Volume")
        }
        .onDisappear { channel.endVolumeAdjustment() }
    }
}
