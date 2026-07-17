import SwiftUI

struct CollectionView: View {
    @EnvironmentObject var game: GameState
    @State private var set = 1
    @State private var selected: Card?

    private var cards: [Card] { CardDatabase.cards(inSet: set) }
    private var owned: Int { game.ownedCount(inSet: set) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Picker("Set", selection: $set) {
                    ForEach(1...CardDatabase.setCount, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                VStack(spacing: 6) {
                    HStack {
                        Text(CardDatabase.setName(set))
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .foregroundStyle(Palette.text)
                        Spacer()
                        Text("\(owned) / 50")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(owned == 50 ? Palette.money : Palette.subtle)
                    }
                    ProgressBar(value: Double(owned), total: 50, tint: Element.theme(forSet: set).palette[1])
                }
                .padding(.horizontal, 16)

                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12)], spacing: 14) {
                        ForEach(cards) { card in
                            slot(for: card)
                        }
                    }
                    .padding(16)
                }
            }
            .background(Palette.screen.ignoresSafeArea())
            .navigationTitle("Collection")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selected) { card in
                CardDetailView(card: card)
            }
        }
    }

    @ViewBuilder
    private func slot(for card: Card) -> some View {
        if game.owns(card.id) {
            let best = bestInstance(card)
            Button {
                Haptics.play(.light)
                selected = card
            } label: {
                ZStack(alignment: .topTrailing) {
                    CardView(card: card, instance: best, width: 104)
                    let n = game.count(of: card.id)
                    if n > 1 {
                        Text("×\(n)")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Palette.bg0.opacity(0.85)))
                            .overlay(Capsule().strokeBorder(Palette.stroke, lineWidth: 1))
                            .offset(x: -6, y: 6)
                    }
                }
            }
            .buttonStyle(.plain)
        } else {
            LockedCardView(card: card, width: 104)
        }
    }

    /// The most valuable owned copy (so graded/foil copies show off in the grid).
    private func bestInstance(_ card: Card) -> CardInstance? {
        game.instances(of: card.id).max { $0.currentValue < $1.currentValue }
    }
}
