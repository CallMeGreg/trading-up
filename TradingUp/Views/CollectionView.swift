import SwiftUI

struct CollectionView: View {
    @Environment(GameState.self) var game: GameState
    @State private var set = 1
    @State private var selected: Card?
    @State private var activeFilters: Set<CardFilter> = []

    private var cards: [Card] { CardDatabase.cards(inSet: set) }
    private var owned: Int { game.ownedCount(inSet: set) }
    private var filteredCards: [Card] { cards.filter(matches) }

    /// A card is shown only if it satisfies *every* active filter (AND).
    private func matches(_ card: Card) -> Bool {
        for f in activeFilters {
            switch f {
            case .dupes: if game.count(of: card.id) <= 1 { return false }
            case .foils: if !game.instances(of: card.id).contains(where: { $0.foil }) { return false }
            case .rare:  if card.rarity != .rare && card.rarity != .ultra { return false }
            }
        }
        return true
    }

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

                filterBar

                ScrollView {
                    if filteredCards.isEmpty {
                        emptyState
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12)], spacing: 14) {
                            ForEach(filteredCards) { card in
                                slot(for: card)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .padding(.top, 8)
            .readableWidth(900)
            .background(Palette.screen.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $selected) { card in
                CardDetailView(card: card)
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach(CardFilter.allCases) { f in
                FilterChip(title: f.rawValue, systemImage: f.icon, isOn: activeFilters.contains(f)) {
                    toggle(f)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 34))
                .foregroundStyle(Palette.subtle)
            Text("No cards match these filters")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.subtle)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 64)
    }

    private func toggle(_ f: CardFilter) {
        Haptics.play(.light)
        if activeFilters.contains(f) { activeFilters.remove(f) } else { activeFilters.insert(f) }
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

/// Collection grid filters. Multiple active filters combine with AND.
enum CardFilter: String, CaseIterable, Identifiable {
    case dupes = "Dupes"
    case foils = "Foils"
    case rare  = "Rare+"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .dupes: return "rectangle.stack.fill"
        case .foils: return "sparkles"
        case .rare:  return "diamond.fill"
        }
    }
}

private struct FilterChip: View {
    let title: String
    let systemImage: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage).font(.system(size: 11, weight: .bold))
                Text(title).font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(isOn ? .white : Palette.subtle)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 11)
                    .fill(isOn
                          ? LinearGradient(colors: [Color(hex: "3b82f6"), Color(hex: "6d5cf7")],
                                           startPoint: .leading, endPoint: .trailing)
                          : LinearGradient(colors: [Palette.bg0.opacity(0.5), Palette.bg0.opacity(0.5)],
                                           startPoint: .leading, endPoint: .trailing))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(isOn ? Color.clear : Palette.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
