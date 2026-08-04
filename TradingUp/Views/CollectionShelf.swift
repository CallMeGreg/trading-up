import SwiftUI

/// A scrollable "victory lap" of the cards a run actually produced: one snapping
/// carousel per set, so the player can flip through their haul before starting
/// over. Only sets with at least one owned card get a shelf, keeping the focus on
/// what was collected rather than what's missing. Tapping a card calls `onSelect`,
/// which the host uses to present `CardDetailView`.
struct CollectionReview: View {
    @Environment(GameState.self) private var game
    let onSelect: (Card) -> Void

    /// Sets the player pulled at least one card from, in set order.
    private var setsWithCards: [Int] {
        (1...CardDatabase.setCount).filter { game.ownedCount(inSet: $0) > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("YOUR COLLECTION")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(Palette.subtle)
                Spacer()
                Text("\(game.uniqueCount)/\(game.totalCards)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(Palette.subtle)
            }

            if setsWithCards.isEmpty {
                emptyState
            } else {
                ForEach(setsWithCards, id: \.self) { set in
                    SetShelf(set: set, onSelect: onSelect)
                }
                Label("Tap a card to look closer.", systemImage: "hand.tap.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.subtle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Palette.subtle)
            Text("No cards this run")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Palette.text)
            Text("Every pack is a fresh shot at a rare.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.subtle)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .panel()
    }
}

/// One set's row: a header (element dot, name, owned/50, progress) above a
/// horizontal, view-aligned carousel of the owned cards. The most valuable copy
/// of each card is shown, with a `×N` badge when duplicates were pulled.
struct SetShelf: View {
    @Environment(GameState.self) private var game
    let set: Int
    let onSelect: (Card) -> Void

    private var element: Element { Element.theme(forSet: set) }
    private var ownedCards: [Card] {
        CardDatabase.cards(inSet: set).filter { game.owns($0.id) }
    }

    var body: some View {
        let owned = game.ownedCount(inSet: set)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(element.badgeTint)
                    .frame(width: 9, height: 9)
                Text(CardDatabase.setName(set))
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 8)
                Text("\(owned)/50")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(owned == 50 ? Palette.money : Palette.subtle)
            }
            ProgressBar(value: Double(owned), total: 50, tint: element.palette[1], height: 6)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(ownedCards) { card in
                        shelfCard(card)
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 4)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
        }
    }

    /// The most valuable owned copy, so graded/foil pulls show off in the shelf.
    private func bestInstance(_ card: Card) -> CardInstance? {
        game.instances(of: card.id).max { $0.currentValue < $1.currentValue }
    }

    @ViewBuilder
    private func shelfCard(_ card: Card) -> some View {
        Button {
            Haptics.play(.light)
            onSelect(card)
        } label: {
            ZStack(alignment: .topTrailing) {
                CardView(card: card, instance: bestInstance(card), width: 150)
                let n = game.count(of: card.id)
                if n > 1 {
                    Text("×\(n)")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(Palette.bg0.opacity(0.85)))
                        .overlay(Capsule().strokeBorder(Palette.stroke, lineWidth: 1))
                        .padding(8)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
