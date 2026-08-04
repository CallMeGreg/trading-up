import SwiftUI

/// A self-contained, fixed-width snapshot of a win, designed to be rasterized by
/// `ImageRenderer` and shared as an image. It leads with the player's
/// one-of-a-kind `CollectorCardView` — the whole point of the win screen — then
/// adds the headline feat, proof of the full set, and app branding so the shared
/// image stands on its own.
struct WinShareCard: View {
    let signature: RunSignature
    let totalCards: Int
    /// Owned count for each set, indexed 0-based for sets 1...setCount.
    let ownedBySet: [Int]

    private var completeSets: Int { ownedBySet.filter { $0 >= 50 }.count }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 3) {
                Text("MASTER COLLECTOR")
                    .font(.system(size: 13, weight: .black)).tracking(3)
                    .foregroundStyle(Color(hex: "ffd54a"))
                Text("Collected all \(totalCards)!")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }

            CollectorCardView(signature: signature, width: 300)

            Text(signature.accolade)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.text)
                .multilineTextAlignment(.center)

            Text("★ \(totalCards) / \(totalCards)  ·  \(completeSets) SETS COMPLETE")
                .font(.system(size: 11, weight: .black)).tracking(1.5)
                .foregroundStyle(Palette.money)

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
                RadialGradient(gradient: Gradient(colors: [signature.element.palette[1].opacity(0.4), .clear]),
                               center: .top, startRadius: 20, endRadius: 480)
            }
        )
    }
}
