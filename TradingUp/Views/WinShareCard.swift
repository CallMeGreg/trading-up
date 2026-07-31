import SwiftUI

/// A self-contained, fixed-width snapshot of a win, designed to be rasterized by
/// `ImageRenderer` and shared as an image. Mirrors `WinView`'s celebration visuals
/// (minus the scroll view and interactive buttons) and adds app branding + link so
/// the shared screenshot stands on its own.
struct WinShareCard: View {
    let totalCards: Int
    let netWorth: Double
    let stats: Stats
    /// Owned count for each set, indexed 0-based for sets 1...setCount.
    let ownedBySet: [Int]

    private var s: Stats { stats }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Text("🏆").font(.system(size: 64))
                Text("MASTER COLLECTOR")
                    .font(.system(size: 13, weight: .black)).tracking(3)
                    .foregroundStyle(Color(hex: "ffd54a"))
                Text("Collected all \(totalCards)!")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("Every Spryte is yours.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.subtle)
            }

            HStack(spacing: 10) {
                StatTile(label: "Net Worth", value: netWorth.moneyShort, tint: Palette.money)
                StatTile(label: "Packs", value: "\(s.packsOpened)")
                StatTile(label: "Boxes", value: "\(s.boxesOpened)")
            }
            HStack(spacing: 10) {
                StatTile(label: "Foils", value: "\(s.foilsPulled)", tint: Color(hex: "ff8ad6"))
                StatTile(label: "Ultras", value: "\(s.ultrasPulled)", tint: Color(hex: "b06cf7"))
                StatTile(label: "Best Grade", value: s.bestGrade == 0 ? "—" : "PSA \(s.bestGrade)", tint: Color(hex: "ffd54a"))
            }

            VStack(alignment: .leading, spacing: 9) {
                Text("COMPLETE SETS").font(.system(size: 12, weight: .black)).foregroundStyle(Palette.subtle)
                ForEach(1...CardDatabase.setCount, id: \.self) { set in
                    let owned = set <= ownedBySet.count ? ownedBySet[set - 1] : 50
                    HStack(spacing: 10) {
                        Text(CardDatabase.setName(set))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.text)
                            .frame(width: 96, alignment: .leading)
                            .lineLimit(1).minimumScaleFactor(0.6)
                        ProgressBar(value: Double(owned), total: 50,
                                    tint: Element.theme(forSet: set).palette[1], height: 7)
                        Text("\(owned)/50")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(owned == 50 ? Palette.money : Palette.subtle)
                            .frame(width: 46, alignment: .trailing)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel()

            Text("TRADING UP")
                .font(.system(size: 15, weight: .black, design: .rounded)).tracking(2)
                .foregroundStyle(.white)
        }
        .padding(24)
        .frame(width: 360)
        .background(
            ZStack {
                LinearGradient(colors: [Color(hex: "1a1030"), Palette.bg0],
                               startPoint: .top, endPoint: .bottom)
                RadialGradient(gradient: Gradient(colors: [Color(hex: "b06cf7").opacity(0.4), .clear]),
                               center: .top, startRadius: 20, endRadius: 480)
            }
        )
    }
}
