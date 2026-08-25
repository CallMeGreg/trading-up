import SwiftUI

/// The permanent Binder — the spine of the game. One slot per card across all
/// sets; owned slots show their best copy (foil / grade), and the header tracks
/// weighted completion toward an all-foil, Gem-Mint collection.
struct BinderView: View {
    @Environment(ChaseState.self) private var state

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                ForEach(1...CardDatabase.setCount, id: \.self) { set in
                    setSection(set)
                }
            }
            .padding(16)
            .readableWidth()
        }
        .navigationTitle("Binder")
        .navigationBarTitleDisplayMode(.inline)
        .background(Palette.screen.ignoresSafeArea())
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("\(Int(state.binderCompletion * 100))% complete")
                .font(.system(size: 28, weight: .heavy, design: .rounded)).foregroundStyle(Palette.text)
            ProgressBar(value: state.binderCompletion, total: 1, tint: Palette.money, height: 10).frame(maxWidth: 260)
            Text("\(state.binderUnique) of \(state.totalCards) cards · keep chasing foils and higher grades")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.subtle)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).panel(18)
    }

    private func setSection(_ set: Int) -> some View {
        let cards = CardDatabase.cards(inSet: set).sorted { $0.id < $1.id }
        let owned = cards.filter { state.meta.binder[$0.id] != nil }.count
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(CardDatabase.setName(set)).font(.system(size: 14, weight: .heavy)).foregroundStyle(Palette.text)
                Spacer()
                Text("\(owned)/\(cards.count)").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.subtle)
            }
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(cards) { card in
                    BinderTile(card: card, copy: state.meta.binder[card.id])
                }
            }
        }
    }
}

/// One Binder slot: a compact card face when owned, a dim placeholder when not.
struct BinderTile: View {
    let card: Card
    let copy: BinderCopy?

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(copy != nil ? Palette.panelHi : Palette.bg0.opacity(0.5))
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(copy != nil ? AnyShapeStyle(card.rarity.gemGradient) : AnyShapeStyle(Palette.stroke),
                                  lineWidth: copy != nil ? 2 : 1)
                if let copy {
                    VStack(spacing: 3) {
                        if copy.foil { Image(systemName: "sparkles").font(.system(size: 12)).foregroundStyle(Color(hex: "ffd54a")) }
                        if let g = copy.grade {
                            Text("PSA \(g)").font(.system(size: 10, weight: .heavy)).foregroundStyle(Palette.tapCue)
                        }
                    }
                } else {
                    Image(systemName: "questionmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.stroke)
                }
            }
            .frame(height: 56)
            Text(copy != nil ? card.name : "—")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(copy != nil ? Palette.text : Palette.subtle)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }
}
