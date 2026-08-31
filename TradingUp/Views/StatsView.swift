import SwiftUI

/// Classic Mode stats, laid out as a dashboard ledger: a hero card with a
/// completion ring and net worth on top, then compact label→value rows grouped
/// into themed sections. This packs far more of the model's numbers onto one
/// screen than a few tile blocks could, while staying scannable.
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

    private var completion: Double {
        game.totalCards > 0 ? Double(game.uniqueCount) / Double(game.totalCards) : 0
    }
    private var completionPercent: Int { Int((completion * 100).rounded()) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    hero

                    Picker("Scope", selection: $scope) {
                        ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    collectionSection
                    haulSection
                    economySection
                    if scope == .allTime { runsSection }
                }
                .padding(16)
                .readableWidth()
            }
            .background(Palette.screen.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: Hero

    private var hero: some View {
        HStack(spacing: 16) {
            CompletionRing(fraction: completion, percent: completionPercent)
                .frame(width: 92, height: 92)
            VStack(alignment: .leading, spacing: 2) {
                Text("NET WORTH")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(Palette.subtle)
                Text(game.netWorth.moneyShort)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1).minimumScaleFactor(0.5)
                HStack(spacing: 14) {
                    heroFigure(game.cash.moneyShort, "Cash", Palette.money)
                    heroFigure(game.collectionValue.moneyShort, "Collection", Palette.text)
                    heroFigure("\(game.uniqueCount)/\(game.totalCards)", "Cards", Palette.text)
                }
                .padding(.top, 5)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(LinearGradient(colors: [Palette.panelHi, Palette.panel],
                                     startPoint: .top, endPoint: .bottom))
        )
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Palette.stroke, lineWidth: 1))
    }

    private func heroFigure(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label.uppercased())
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(Palette.subtle)
        }
    }

    // MARK: Sections

    /// Collection is the live binder, so the summary rows read the same in both
    /// scopes. The per-set progress breakdown is a run-focused detail, so it's
    /// shown only in the This Run scope and dropped from All Time.
    private var collectionSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Collection")
            ledger(collectionItems)
            if scope == .run {
                Rectangle().fill(Palette.stroke.opacity(0.55)).frame(height: 1).padding(.top, 4)
                Text("BY SET")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(Palette.subtle)
                    .tracking(0.5)
                    .padding(.top, 12).padding(.bottom, 9)
                SetBreakdown()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private var collectionItems: [LedgerItem] {
        [
            LedgerItem("Completion", "\(completionPercent)%"),
            LedgerItem("Sets Completed", "\(game.setsCompleted) / \(game.setsTotal)"),
            LedgerItem("Evolution Lines", "\(game.evolutionLinesCompleted) / \(game.evolutionLinesTotal)"),
            LedgerItem("Foils Owned", "\(game.foilsOwned)"),
            LedgerItem("Graded Cards", "\(game.gradedOwned)"),
            LedgerItem("Duplicates", "\(game.duplicateCount)"),
            LedgerItem("Top Card", game.topCardValue == 0 ? "—" : game.topCardValue.moneyShort),
        ]
    }

    private var haulSection: some View {
        let run = scope == .run
        let packs = run ? s.packsOpened : lifetime.packsOpened
        let boxes = run ? s.boxesOpened : lifetime.boxesOpened
        let cards = run ? s.cardsPulled : lifetime.cardsPulled
        let ultras = run ? s.ultrasPulled : lifetime.ultrasPulled
        let foils = run ? s.foilsPulled : lifetime.foilsPulled
        let best = run ? s.bestGrade : lifetime.bestGrade

        var items = Self.haulTiles(packs: packs, boxes: boxes, bestGrade: best,
                                   cards: cards, ultras: ultras, foils: foils)
            .map { LedgerItem($0.0, $0.1) }
        if packs > 0 {
            items.append(LedgerItem("Cards / Pack", String(format: "%.1f", Double(cards) / Double(packs))))
        }
        if cards > 0 {
            items.append(LedgerItem("Ultra Rate", String(format: "%.1f%%", Double(ultras) / Double(cards) * 100)))
            items.append(LedgerItem("Foil Rate", String(format: "%.1f%%", Double(foils) / Double(cards) * 100)))
        }
        return section("Haul", items)
    }

    private var economySection: some View {
        let run = scope == .run
        let spent = run ? s.moneySpent : lifetime.moneySpent
        let earned = run ? s.moneyEarned : lifetime.moneyEarned
        let sold = run ? s.cardsSold : lifetime.cardsSold
        let peakNet = run ? s.peakNetWorth : lifetime.peakNetWorth
        let peakCash = run ? s.peakCash : lifetime.peakCash
        let peakCard = run ? s.peakCardValue : lifetime.peakCardValue
        let peakSale = run ? s.peakSale : lifetime.peakSale
        let net = earned - spent
        return section("Economy", [
            LedgerItem("Spent", spent.moneyShort),
            LedgerItem("Earned", earned.moneyShort),
            LedgerItem("Net Profit", net.signedMoneyShort, tint: net >= 0 ? Palette.money : Palette.loss),
            LedgerItem("Cards Sold", "\(sold)"),
            LedgerItem("Peak Net Worth", peakNet.moneyShort),
            LedgerItem("Peak Cash", peakCash.moneyShort),
            LedgerItem("Peak Card Value", peakCard == 0 ? "—" : peakCard.moneyShort),
            LedgerItem("Peak Sale", peakSale == 0 ? "—" : peakSale.moneyShort),
        ])
    }

    private var runsSection: some View {
        let winRate = lifetime.runsStarted > 0
            ? "\(Int((Double(lifetime.runsWon) / Double(lifetime.runsStarted) * 100).rounded()))%"
            : "—"
        return section("Runs", [
            LedgerItem("Runs Played", "\(lifetime.runsStarted)"),
            LedgerItem("Runs Won", "\(lifetime.runsWon)"),
            LedgerItem("Win Rate", winRate),
            LedgerItem("Best Run", lifetime.bestRunPacks.map { "\($0) packs" } ?? "—"),
        ])
    }

    // MARK: Building blocks

    private struct LedgerItem {
        let label: String
        let value: String
        var tint: Color
        init(_ label: String, _ value: String, tint: Color = Palette.text) {
            self.label = label
            self.value = value
            self.tint = tint
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 12, weight: .black))
            .foregroundStyle(Palette.subtle)
            .padding(.bottom, 2)
    }

    private func section(_ title: String, _ items: [LedgerItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(title)
            ledger(items)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    /// A stack of label→value rows with hairline separators between them.
    @ViewBuilder
    private func ledger(_ items: [LedgerItem]) -> some View {
        ForEach(Array(items.enumerated()), id: \.element.label) { idx, item in
            HStack {
                Text(item.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.text)
                Spacer(minLength: 8)
                Text(item.value)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(item.tint)
            }
            .padding(.vertical, 9)
            if idx < items.count - 1 {
                Rectangle().fill(Palette.stroke.opacity(0.45)).frame(height: 1)
            }
        }
    }

    /// The "Haul" rows, flag-aware so they stay in one place: `Boxes Opened` is
    /// omitted entirely while booster boxes are off the shelf — a permanent zero
    /// is worse than no row at all.
    static func haulTiles(packs: Int, boxes: Int, bestGrade: Int,
                          cards: Int, ultras: Int, foils: Int) -> [(String, String)] {
        var tiles = [("Packs Opened", "\(packs)")]
        if FeatureFlags.boosterBoxesAvailable {
            tiles.append(("Boxes Opened", "\(boxes)"))
        }
        tiles.append(("Cards Pulled", "\(cards)"))
        tiles.append(("Ultras Pulled", "\(ultras)"))
        tiles.append(("Foils Pulled", "\(foils)"))
        tiles.append(("Best Grade", bestGrade == 0 ? "—" : "PSA \(bestGrade)"))
        return tiles
    }
}

/// The completion ring shown in the Stats hero: a track plus a trimmed arc for
/// the fraction collected, with the percentage in the middle.
private struct CompletionRing: View {
    let fraction: Double
    let percent: Int

    var body: some View {
        ZStack {
            Circle().stroke(Palette.bg0, lineWidth: 9)
            Circle()
                .trim(from: 0, to: max(0.004, min(1, fraction)))
                .stroke(Palette.money, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(percent)%")
                    .font(.system(size: 19, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.text)
                Text("COMPLETE")
                    .font(.system(size: 7, weight: .black))
                    .foregroundStyle(Palette.subtle)
                    .tracking(0.5)
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
