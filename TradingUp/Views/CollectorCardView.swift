import SwiftUI

/// Maps a collector rank to its signature color, shared by the card and the
/// win-screen callout so an S-rank is gold in both places.
extension CollectorRank {
    var color: Color {
        switch self {
        case .s: return Color(hex: "ffd54a")
        case .a: return Color(hex: "b06cf7")
        case .b: return Color(hex: "3b82f6")
        case .c: return Color(hex: "5be08a")
        case .d: return Color(hex: "e0a45c")
        }
    }
}

/// A one-of-a-kind "collector card" whose subject is the player's winning run.
/// It's styled like an ultra-rare, holographic, graded card from the game — but
/// the card is *them*: their earned title, their dominant element, a procedural
/// crest unique to how they won, and their run's superlatives as the stat block.
///
/// Everything scales from `width` (height = 1.4×width), so the exact same card
/// renders on the win screen and, larger, inside the rasterized share image.
struct CollectorCardView: View {
    let signature: RunSignature
    var width: CGFloat = 300

    private var s: CGFloat { width / 230 }
    private var corner: CGFloat { 16 * s }
    private var e: Element { signature.element }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner)
                .fill(LinearGradient(colors: [Palette.panelHi, Palette.panel],
                                     startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: corner)
                .fill(RadialGradient(gradient: Gradient(colors: [e.palette[1].opacity(0.22), .clear]),
                                     center: .top, startRadius: 6 * s, endRadius: 220 * s))

            VStack(spacing: 7 * s) {
                header
                goldMeta
                crest
                statBlock
                valueBar
            }
            .padding(11 * s)

            // Always-on holographic sheen — this is the rarest card there is.
            FoilOverlay(cornerRadius: corner)
                .clipShape(RoundedRectangle(cornerRadius: corner))

            RoundedRectangle(cornerRadius: corner)
                .strokeBorder(Rarity.ultra.gemGradient, lineWidth: 3 * s)
        }
        .frame(width: width)
        .shadow(color: .black.opacity(0.5), radius: 10 * s, x: 0, y: 5 * s)
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: 4 * s) {
            Text(signature.title)
                .font(.system(size: 19 * s, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.5)
            Spacer(minLength: 2 * s)
            Text(e.display)
                .font(.system(size: 9 * s, weight: .bold))
                .foregroundStyle(e.badgeTint)
                .padding(.horizontal, 6 * s).padding(.vertical, 3 * s)
                .background(Capsule().fill(e.badgeTint.opacity(0.14)))
        }
    }

    private var goldMeta: some View {
        Text("MASTER COLLECTOR  ·  1 OF 1")
            .font(.system(size: 9.5 * s, weight: .black)).tracking(1.5 * s)
            .foregroundStyle(Color(hex: "ffd54a"))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var crest: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10 * s).fill(e.artGradient)
            SigilView(seed: signature.seed, element: e).padding(14 * s)
            RoundedRectangle(cornerRadius: 10 * s)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        }
        .frame(height: 150 * s)
        .clipShape(RoundedRectangle(cornerRadius: 10 * s))
        .overlay(alignment: .topLeading) { rankGem.padding(6 * s) }
        .overlay(alignment: .topTrailing) { gemMintTag.padding(6 * s) }
        .overlay(alignment: .bottom) {
            Text("COLLECTION #\(signature.runNumber)  ·  COMPLETE")
                .font(.system(size: 8.5 * s, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.78))
                .shadow(color: .black.opacity(0.5), radius: 2 * s)
                .padding(.bottom, 6 * s)
        }
    }

    /// The efficiency grade, rendered as a PSA-style gem in the crest corner.
    private var rankGem: some View {
        Text(signature.rank.letter)
            .font(.system(size: 15 * s, weight: .black, design: .rounded))
            .foregroundStyle(.black.opacity(0.82))
            .frame(width: 27 * s, height: 27 * s)
            .background(Circle().fill(rankColor))
            .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1.5 * s))
            .shadow(color: .black.opacity(0.4), radius: 2 * s, y: 1)
    }

    /// A nod to the grading mechanic: the trophy card is, of course, a flawless 1/1.
    private var gemMintTag: some View {
        Text("GEM MT 10")
            .font(.system(size: 8 * s, weight: .black))
            .foregroundStyle(.black.opacity(0.82))
            .padding(.horizontal, 6 * s).padding(.vertical, 3 * s)
            .background(Capsule().fill(Color(hex: "ffd54a")))
            .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 0.8))
    }

    private var statBlock: some View {
        VStack(spacing: 6 * s) {
            HStack(spacing: 6 * s) {
                chip("PACKS", "\(signature.packsOpened)")
                chip("FOILS", "\(signature.foilsPulled)", tint: Color(hex: "ff8ad6"))
            }
            HStack(spacing: 6 * s) {
                chip("ULTRAS", "\(signature.ultrasPulled)", tint: Color(hex: "b06cf7"))
                chip("BEST", signature.bestGrade == 0 ? "—" : "PSA \(signature.bestGrade)",
                     tint: Color(hex: "ffd54a"))
            }
            crownRow
        }
    }

    private func chip(_ label: String, _ value: String, tint: Color = Palette.text) -> some View {
        VStack(spacing: 2 * s) {
            Text(value)
                .font(.system(size: 15 * s, weight: .heavy, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 8 * s, weight: .bold)).tracking(0.5)
                .foregroundStyle(Palette.subtle)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7 * s)
        .background(RoundedRectangle(cornerRadius: 9 * s).fill(Palette.bg0.opacity(0.5)))
    }

    private var crownRow: some View {
        HStack(spacing: 7 * s) {
            Text("👑").font(.system(size: 13 * s))
            VStack(alignment: .leading, spacing: 0) {
                Text("CROWN JEWEL")
                    .font(.system(size: 7.5 * s, weight: .black)).tracking(1)
                    .foregroundStyle(Palette.subtle)
                Text(signature.crownJewel?.name ?? "—")
                    .font(.system(size: 11 * s, weight: .bold))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            Spacer(minLength: 4 * s)
            Text(signature.crownJewelValue.moneyShort)
                .font(.system(size: 13 * s, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.money)
        }
        .padding(.horizontal, 9 * s)
        .padding(.vertical, 7 * s)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 9 * s).fill(Palette.bg0.opacity(0.5)))
    }

    private var valueBar: some View {
        HStack(spacing: 6 * s) {
            Text("RANK \(signature.rank.letter) · \(signature.rank.word.uppercased())")
                .font(.system(size: 9 * s, weight: .heavy))
                .foregroundStyle(signature.rank.color)
                .padding(.horizontal, 7 * s).padding(.vertical, 3 * s)
                .background(Capsule().fill(signature.rank.color.opacity(0.16)))
            Spacer(minLength: 2 * s)
            VStack(alignment: .trailing, spacing: 0) {
                Text("NET WORTH")
                    .font(.system(size: 7 * s, weight: .bold)).tracking(0.5)
                    .foregroundStyle(Palette.subtle)
                Text(signature.netWorth.moneyShort)
                    .font(.system(size: 16 * s, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.money)
            }
        }
    }

    private var rankColor: Color { signature.rank.color }
}
