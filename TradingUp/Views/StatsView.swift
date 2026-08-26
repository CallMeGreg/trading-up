import SwiftUI

struct StatsView: View {
    @Environment(GameState.self) var game: GameState
    @State private var scope: Scope = .run

    private enum Scope: String, CaseIterable, Identifiable {
        case run = "This Run"
        case allTime = "All Time"
        var id: String { rawValue }
    }

    private var s: Stats { game.stats }
    private var lifetime: LifetimeStats { game.lifetimeStats }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack(spacing: 12) {
                        StatTile(label: "Cash", value: game.cash.moneyShort, tint: Palette.money)
                        StatTile(label: "Collection Value", value: game.collectionValue.moneyShort)
                        StatTile(label: "Net Worth", value: game.netWorth.moneyShort, tint: Color(hex: "b06cf7"))
                    }

                    Picker("Scope", selection: $scope) {
                        ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if scope == .run {
                        VStack(alignment: .leading, spacing: 12) {
                            header("Collection")
                            HStack {
                                Text("Unique cards").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.subtle)
                                Spacer()
                                Text("\(game.uniqueCount) / \(game.totalCards)")
                                    .font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(Palette.text)
                            }
                            ProgressBar(value: Double(game.uniqueCount), total: Double(game.totalCards), tint: .white)
                            SetBreakdown()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .panel()
                    }

                    if scope == .allTime {
                        VStack(alignment: .leading, spacing: 12) {
                            header("Runs")
                            grid([
                                ("Runs Played", "\(lifetime.runsStarted)"),
                                ("Runs Won", "\(lifetime.runsWon)"),
                                ("Best Run", lifetime.bestRunPacks.map { "\($0) packs" } ?? "—"),
                            ])
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .panel()
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        header("Haul")
                        grid(scope == .run
                             ? Self.haulTiles(packs: s.packsOpened, boxes: s.boxesOpened,
                                              bestGrade: s.bestGrade, cards: s.cardsPulled,
                                              ultras: s.ultrasPulled, foils: s.foilsPulled)
                             : Self.haulTiles(packs: lifetime.packsOpened, boxes: lifetime.boxesOpened,
                                              bestGrade: lifetime.bestGrade, cards: lifetime.cardsPulled,
                                              ultras: lifetime.ultrasPulled, foils: lifetime.foilsPulled))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panel()

                    VStack(alignment: .leading, spacing: 12) {
                        header("Economy")
                        grid(scope == .run ? [
                            ("Spent", s.moneySpent.moneyShort),
                            ("Earned", s.moneyEarned.moneyShort),
                            ("Cards Sold", "\(s.cardsSold)"),
                            ("Peak Cash", s.peakCash.moneyShort),
                            ("Peak Card", s.peakCardValue == 0 ? "—" : s.peakCardValue.moneyShort),
                            ("Peak Sale", s.peakSale == 0 ? "—" : s.peakSale.moneyShort),
                        ] : [
                            ("Spent", lifetime.moneySpent.moneyShort),
                            ("Earned", lifetime.moneyEarned.moneyShort),
                            ("Cards Sold", "\(lifetime.cardsSold)"),
                            ("Peak Cash", lifetime.peakCash.moneyShort),
                            ("Peak Card", lifetime.peakCardValue == 0 ? "—" : lifetime.peakCardValue.moneyShort),
                            ("Peak Sale", lifetime.peakSale == 0 ? "—" : lifetime.peakSale.moneyShort),
                        ])
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panel()
                }
                .padding(16)
                .readableWidth()
            }
            .background(Palette.screen.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func header(_ t: String) -> some View {
        Text(t.uppercased()).font(.system(size: 12, weight: .black)).foregroundStyle(Palette.subtle)
    }

    /// The "Haul" tiles, shared by the run and all-time scopes so the two can't
    /// drift apart. `Boxes Opened` is omitted entirely while booster boxes are
    /// off the shelf — a permanent zero is worse than no tile at all.
    static func haulTiles(packs: Int, boxes: Int, bestGrade: Int,
                          cards: Int, ultras: Int, foils: Int) -> [(String, String)] {
        var tiles = [("Packs Opened", "\(packs)")]
        if FeatureFlags.boosterBoxesAvailable {
            tiles.append(("Boxes Opened", "\(boxes)"))
        }
        tiles.append(("Best Grade", bestGrade == 0 ? "—" : "PSA \(bestGrade)"))
        tiles.append(("Cards Pulled", "\(cards)"))
        tiles.append(("Ultras Pulled", "\(ultras)"))
        tiles.append(("Foils Pulled", "\(foils)"))
        return tiles
    }

    private func grid(_ items: [(String, String)]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(items, id: \.0) { item in
                StatTile(label: item.0, value: item.1)
            }
        }
    }
}

/// Per-set owned/50 progress rows. Shared by Stats / Win / Lose.
struct SetBreakdown: View {
    @Environment(GameState.self) var game: GameState

    var body: some View {
        VStack(spacing: 9) {
            ForEach(1...CardDatabase.setCount, id: \.self) { set in
                let owned = game.ownedCount(inSet: set)
                HStack(spacing: 10) {
                    Text(CardDatabase.setName(set))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.text)
                        .frame(width: 96, alignment: .leading)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    ProgressBar(value: Double(owned), total: 50, tint: Element.theme(forSet: set).palette[1], height: 7)
                    Text("\(owned)/50")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(owned == 50 ? Palette.money : Palette.subtle)
                        .frame(width: 46, alignment: .trailing)
                }
            }
        }
    }
}
