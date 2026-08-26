import SwiftUI

/// The Binder: a permanent trophy case showing the single best copy of every
/// Spryte the player has ever owned, across every Classic run and (eventually)
/// Gauntlet Mode. Unlike the Collection tab — which reflects the *current* run and
/// empties on a reset — the Binder only ever grows, so it's the natural home for
/// "look what I've pulled." Reads straight from `GameState.binder`; slots are
/// display-only for now.
struct BinderView: View {
    @Environment(GameState.self) private var game: GameState
    @Environment(\.dismiss) private var dismiss

    @State private var set = 1

    private var binder: Binder { game.binder }
    private var cards: [Card] { CardDatabase.cards(inSet: set) }
    private var filledInSet: Int { binder.filledCount(inSet: set) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                summary

                Picker("Set", selection: $set) {
                    ForEach(1...CardDatabase.setCount, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                setHeader

                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12)], spacing: 14) {
                        ForEach(cards) { card in
                            slot(for: card)
                        }
                    }
                    .padding(16)
                }
            }
            .padding(.top, 8)
            .readableWidth(900)
            .background(Palette.screen.ignoresSafeArea())
            .navigationTitle("Binder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Haptics.play(.light)
                        dismiss()
                    } label: {
                        Label("Menu", systemImage: "chevron.left")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .tint(Palette.text)
                }
            }
        }
    }

    // MARK: Overall header

    /// The headline: how much of the all-time showcase is filled, and what it's
    /// worth. This is the number a collector comes to the Binder to watch climb.
    private var summary: some View {
        HStack(spacing: 12) {
            StatTile(label: "Sprytes", value: "\(binder.filledCount) / \(binder.totalSlots)",
                     tint: binder.isComplete ? Palette.money : Palette.text)
            StatTile(label: "Binder Value", value: binder.totalValue.moneyShort, tint: Palette.money)
            StatTile(label: "Crown Jewel", value: crownJewelValue, tint: Rarity.ultra.accent)
        }
        .padding(.horizontal, 16)
    }

    private var crownJewelValue: String {
        binder.mostValuable.map { $0.currentValue.moneyShort } ?? "—"
    }

    // MARK: Per-set header

    private var setHeader: some View {
        VStack(spacing: 6) {
            HStack {
                Text(CardDatabase.setName(set))
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.text)
                Spacer()
                Text("\(filledInSet) / \(cards.count)")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(filledInSet == cards.count && cards.count > 0 ? Palette.money : Palette.subtle)
            }
            ProgressBar(value: Double(filledInSet), total: Double(max(cards.count, 1)),
                        tint: Element.theme(forSet: set).palette[1])
        }
        .padding(.horizontal, 16)
    }

    // MARK: Slot

    /// A filled slot shows off the best copy on record (foil/grade and all); an
    /// empty one shows the locked placeholder, same as the Collection grid.
    @ViewBuilder
    private func slot(for card: Card) -> some View {
        if let best = binder.best(for: card.id) {
            CardView(card: card, instance: best, width: 104)
        } else {
            LockedCardView(card: card, width: 104)
        }
    }
}
