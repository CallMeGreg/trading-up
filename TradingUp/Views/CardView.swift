import SwiftUI

/// A single trading card. Scales all internals from `width` (height = 1.4×width).
/// Pass an `instance` to reflect that specific copy's foil/grade/value; omit for catalogue art.
struct CardView: View {
    let card: Card
    var instance: CardInstance? = nil
    var width: CGFloat = 230

    private var s: CGFloat { width / 230 }
    private var height: CGFloat { width * 1.4 }
    private var foil: Bool { instance?.foil ?? false }
    private var grade: Int? { instance?.grade }
    private var value: Double { instance?.currentValue ?? card.baseValue }
    private var corner: CGFloat { 16 * s }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner)
                .fill(
                    LinearGradient(
                        colors: [Palette.panelHi, Palette.panel],
                        startPoint: .top, endPoint: .bottom
                    )
                )

            VStack(spacing: 6 * s) {
                header
                artWindow
                metaRow
                flavorText
                Spacer(minLength: 0)
                valueBar
            }
            .padding(10 * s)

            if foil {
                FoilOverlay(cornerRadius: corner)
                    .clipShape(RoundedRectangle(cornerRadius: corner))
            }

            RoundedRectangle(cornerRadius: corner)
                .strokeBorder(card.rarity.gemGradient, lineWidth: card.rarity == .ultra ? 3 * s : 2 * s)

            if let g = grade {
                gradeBadge(g)
            }
            if foil {
                foilTag
            }
        }
        .frame(width: width, height: height)
        .shadow(color: .black.opacity(0.45), radius: 8 * s, x: 0, y: 4 * s)
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: 4 * s) {
            Text(card.name)
                .font(.system(size: 16 * s, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 2 * s)
            HStack(spacing: 2 * s) {
                Text(card.element.emoji).font(.system(size: 10 * s))
                Text(card.element.display)
                    .font(.system(size: 9 * s, weight: .bold))
                    .foregroundStyle(card.element.badgeTint)
            }
            .padding(.horizontal, 6 * s).padding(.vertical, 3 * s)
            .background(Capsule().fill(card.element.badgeTint.opacity(0.14)))
        }
    }

    private var artWindow: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10 * s).fill(card.element.artGradient)
            if let art = UIImage(named: card.id) {
                Image(uiImage: art)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                SigilView(seed: card.name + card.element.rawValue, element: card.element)
                    .padding(6 * s)
            }
            RoundedRectangle(cornerRadius: 10 * s)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        }
        .frame(height: 150 * s)
        .clipShape(RoundedRectangle(cornerRadius: 10 * s))
    }

    private var metaRow: some View {
        HStack {
            HStack(spacing: 4 * s) {
                Circle().fill(card.rarity.gemGradient).frame(width: 9 * s, height: 9 * s)
                Text(CardDatabase.setName(card.set))
                    .font(.system(size: 10 * s, weight: .semibold))
                    .foregroundStyle(Palette.subtle)
            }
            Spacer()
            Text("\(pad3(card.number)) / 050")
                .font(.system(size: 10 * s, weight: .semibold, design: .monospaced))
                .foregroundStyle(Palette.subtle)
        }
    }

    private var flavorText: some View {
        Text(card.flavor)
            .font(.system(size: 10.5 * s, weight: .regular, design: .serif))
            .italic()
            .foregroundStyle(Palette.text.opacity(0.72))
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var valueBar: some View {
        HStack {
            Text(card.rarity.display.uppercased())
                .font(.system(size: 9.5 * s, weight: .heavy))
                .foregroundStyle(card.rarity.accent)
                .padding(.horizontal, 7 * s).padding(.vertical, 3 * s)
                .background(Capsule().fill(card.rarity.accent.opacity(0.16)))
            Spacer()
            Text(value.money)
                .font(.system(size: 15 * s, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.money)
        }
    }

    private var foilTag: some View {
        Text("★ FOIL ★")
            .font(.system(size: 9 * s, weight: .black))
            .foregroundStyle(.white)
            .padding(.horizontal, 6 * s).padding(.vertical, 2 * s)
            .background(Capsule().fill(LinearGradient(colors: [Color(hex: "ff8ad6"), Color(hex: "7ad9ff")], startPoint: .leading, endPoint: .trailing)))
            .rotationEffect(.degrees(-8))
            .offset(x: -width * 0.28, y: -height * 0.40)
    }

    private func gradeBadge(_ g: Int) -> some View {
        let color: Color = g >= 9 ? Color(hex: "ffd54a") : (g >= 8 ? Color(hex: "8a94a6") : (g == 1 ? Color(hex: "ff5cf0") : Color(hex: "e0663b")))
        return VStack(spacing: 0) {
            Text("PSA").font(.system(size: 8 * s, weight: .black)).foregroundStyle(.black.opacity(0.7))
            Text("\(g)").font(.system(size: 16 * s, weight: .black, design: .rounded)).foregroundStyle(.black)
        }
        .frame(width: 34 * s, height: 34 * s)
        .background(Circle().fill(color))
        .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 2 * s))
        .offset(x: width * 0.34, y: -height * 0.40)
    }
}

/// Animated holographic sheen for foil cards.
struct FoilOverlay: View {
    var cornerRadius: CGFloat = 16
    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let angle = Angle.degrees((t * 45).truncatingRemainder(dividingBy: 360))
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            Color(hex: "ff4d4d"), Color(hex: "ffd24d"), Color(hex: "4dff88"),
                            Color(hex: "4dd2ff"), Color(hex: "b06cf7"), Color(hex: "ff4d4d"),
                        ]),
                        center: .center, angle: angle
                    )
                )
                .blendMode(.plusLighter)
                .opacity(0.20)
                .allowsHitTesting(false)
        }
    }
}

/// Placeholder shown for an un-collected card slot.
struct LockedCardView: View {
    let card: Card
    var width: CGFloat = 108

    private var s: CGFloat { width / 230 }
    private var height: CGFloat { width * 1.4 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16 * s).fill(Palette.bg0.opacity(0.55))
            RoundedRectangle(cornerRadius: 16 * s)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5 * s, dash: [5 * s, 4 * s]))
                .foregroundStyle(Palette.stroke)
            VStack(spacing: 6 * s) {
                Image(systemName: "questionmark")
                    .font(.system(size: 34 * s, weight: .black))
                    .foregroundStyle(Palette.stroke)
                Text("\(pad3(card.number)) / 050")
                    .font(.system(size: 11 * s, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Palette.subtle.opacity(0.7))
            }
        }
        .frame(width: width, height: height)
    }
}
