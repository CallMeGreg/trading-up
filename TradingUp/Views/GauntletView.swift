import SwiftUI

/// Gauntlet Mode — a placeholder for now. The full mode design lands later; this
/// screen just holds its place in the menu so the navigation, the Full Game gate,
/// and the theming are all wired up and ready for the real thing to drop in.
///
/// Reached only when the Full Game is unlocked (the menu routes locked taps to the
/// paywall instead), so there's no entitlement check to do here.
struct GauntletView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "1a0d2e"), Palette.bg0],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            RadialGradient(gradient: Gradient(colors: [Color(hex: "b06cf7").opacity(0.28), .clear]),
                           center: .top, startRadius: 20, endRadius: 480)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer()

                Image(systemName: "bolt.fill")
                    .font(.system(size: 66, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(colors: [Color(hex: "ffd54a"), Color(hex: "b06cf7")],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .shadow(color: Color(hex: "b06cf7").opacity(0.6), radius: 18)

                VStack(spacing: 8) {
                    Text("GAUNTLET MODE")
                        .font(.system(size: 14, weight: .black)).tracking(3)
                        .foregroundStyle(Palette.subtle)
                    Text("Coming Soon")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }

                Text("A relentless new way to play Trading Up is on its way. The design is still being forged — check back in a future update.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.subtle)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)

                comingSoonBadge

                Spacer()

                BigButton(title: "Back to Menu", systemImage: "chevron.left",
                          tint: [Color(hex: "6d5cf7"), Color(hex: "b06cf7")]) {
                    Haptics.play(.light)
                    dismiss()
                }
            }
            .padding(20)
            .readableWidth()
        }
        .overlay(alignment: .topLeading) { backButton }
    }

    private var comingSoonBadge: some View {
        Label("In development", systemImage: "hammer.fill")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Color(hex: "ffd54a"))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Capsule().fill(Color(hex: "ffd54a").opacity(0.12)))
            .overlay(Capsule().strokeBorder(Color(hex: "ffd54a").opacity(0.35), lineWidth: 1))
    }

    private var backButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 26))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Palette.subtle)
        }
        .buttonStyle(.plain)
        .padding(12)
        .accessibilityLabel("Close")
    }
}
