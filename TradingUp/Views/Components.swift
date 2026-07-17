import SwiftUI

/// Thin capsule progress bar.
struct ProgressBar: View {
    var value: Double
    var total: Double
    var tint: Color = Palette.money
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.bg0)
                Capsule().fill(tint)
                    .frame(width: fraction * geo.size.width)
            }
        }
        .frame(height: height)
    }

    private var fraction: CGFloat {
        guard total > 0 else { return 0 }
        return max(0, min(1, CGFloat(value / total)))
    }
}

/// Panel background modifier.
extension View {
    func panel(_ padding: CGFloat = 16, corner: CGFloat = 18) -> some View {
        self
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: corner).fill(Palette.panel))
            .overlay(RoundedRectangle(cornerRadius: corner).strokeBorder(Palette.stroke, lineWidth: 1))
    }
}

/// Full-width gradient action button with optional subtitle.
struct BigButton: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    var tint: [Color] = [Color(hex: "3b82f6"), Color(hex: "6d5cf7")]
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: { Sound.play(.tap); action() }) {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 18, weight: .bold))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 15, weight: .bold))
                    if let subtitle {
                        Text(subtitle).font(.system(size: 11, weight: .medium)).opacity(0.85)
                    }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(.vertical, 12).padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14).fill(
                    LinearGradient(
                        colors: enabled ? tint : [Palette.stroke, Palette.stroke.opacity(0.7)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
            )
            .opacity(enabled ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// Compact labeled statistic.
struct StatTile: View {
    let label: String
    let value: String
    var tint: Color = Palette.text

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Palette.subtle)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Palette.bg0.opacity(0.5)))
    }
}
