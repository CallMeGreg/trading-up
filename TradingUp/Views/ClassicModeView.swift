import SwiftUI

/// Classic Mode: the original Trading Up loop — buy packs, rip them, sell extras,
/// grade rares, and race to all 250 cards. This is the tabbed game as it always
/// was; v2.0.0 moves it behind the main menu, so it now presents full-screen
/// over `MainMenuView` and offers a home button in the Shop's wallet header to
/// get back. Settings now live on the main menu rather than in a tab here.
struct ClassicModeView: View {
    @Environment(GameState.self) var game: GameState
    @Environment(\.dismiss) private var dismiss

    /// Which tab is on screen. Bound so the app can steer the player — e.g. onto
    /// the Shop right after they start a run.
    @State private var selectedTab: AppTab = .shop
    @State private var collectorBadgeCount = 0
    @State private var tradeTargets: [Int: String] = [:]
    @State private var tutorial = ModeTutorial(mode: .classic)
    @State private var preparedTutorial = false

    var body: some View {
        Group {
            if tutorial.isActive {
                guidedContent
            } else {
                tabs
            }
        }
        .environment(\.modeTutorial, tutorial)
        .tint(Palette.money)
        .onAppear {
            guard !preparedTutorial else { return }
            preparedTutorial = true
            tutorial.prepare(hasPlayed: game.core.hasSeenWelcome || game.lifetimeStats.packsOpened > 0)
            tutorial.resumeClassic(hasCards: game.uniqueCount > 0)
            if tutorial.isActive {
                selectedTab = tutorial.needs(.classicSummary) ? .shop
                    : tutorial.needs(.classicDetailDone) ? .collection : .collectors
            }
            if game.shouldShowWelcome { game.markWelcomeSeen() }
        }
        .onChange(of: selectedTab) { _, _ in Sound.play(.uiTap) }
        .onChange(of: game.collectorReadyCount, initial: true) { _, _ in refreshCollectorBadge() }
        .onChange(of: game.revealInFlight) { _, _ in refreshCollectorBadge() }
        .onChange(of: game.collectorReceiptInFlight) { _, _ in refreshCollectorBadge() }
        .onChange(of: game.shouldShowWelcome) { _, showing in
            if showing {
                selectedTab = .shop
                tradeTargets.removeAll()
                game.markWelcomeSeen()
            }
        }
        .fullScreenCover(item: overlayBinding) { overlay in
            switch overlay {
            case .win: WinView()
            case .lose: LoseView()
            }
        }
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            ShopView(onHome: { Sound.play(.uiBack); dismiss() })
                .tabItem { Label("Shop", systemImage: "bag.fill") }
                .tag(AppTab.shop)
            CollectorsView(isSelected: selectedTab == .collectors, tradeTargets: $tradeTargets)
                .tabItem { Label("Collectors", systemImage: "person.2.fill") }
                .badge(collectorBadgeCount)
                .tag(AppTab.collectors)
            CollectionView()
                .tabItem { Label("Collection", systemImage: "square.grid.3x3.fill") }
                .tag(AppTab.collection)
            StatsView()
                .tabItem { Label("Stats", systemImage: "chart.bar.fill") }
                .tag(AppTab.stats)
        }
    }

    // Native tab-item bounds aren't exposed to SwiftUI anchor preferences.
    // Only the guided run uses an equivalent, accessible in-content tab strip.
    private var guidedContent: some View {
        VStack(spacing: 0) {
            Group {
                switch selectedTab {
                case .shop: ShopView(onHome: { dismiss() })
                case .collection: CollectionView()
                case .collectors: CollectorsView(tradeTargets: $tradeTargets)
                case .stats: StatsView()
                }
            }
            HStack {
                guidedTab(.shop, title: "Shop", icon: "bag.fill")
                guidedTab(.collectors, title: "Collectors", icon: "person.2.fill")
                guidedTab(.collection, title: "Collection", icon: "square.grid.3x3.fill")
                guidedTab(.stats, title: "Stats", icon: "chart.bar.fill")
            }
            .padding(.vertical, 8)
            .background(Palette.bg1)
        }
        .tutorialHost(screenPrompt)
    }

    private func guidedTab(_ tab: AppTab, title: String, icon: String) -> some View {
        Button { selectGuidedTab(tab) } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.body)
                Text(title).font(.caption2)
            }
            .foregroundStyle(selectedTab == tab ? Palette.money : Palette.subtle)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .tutorialTarget("tab-\(title)") { selectGuidedTab(tab) }
    }

    private func selectGuidedTab(_ tab: AppTab) {
        guard navigationPrompt != nil else { return }
        selectedTab = tab
        if tab == .collection { tutorial.record(.classicCollection) }
        if tab == .collectors { tutorial.record(.classicCollectors) }
        if tab == .shop, !tutorial.needs(.classicTradeTarget) { tutorial.finish() }
    }

    private var screenPrompt: TutorialPrompt? {
        guard !game.revealInFlight else { return nil }
        if let navigationPrompt { return navigationPrompt }
        switch selectedTab {
        case .shop:
            return tutorial.prompt(.classicBuy, target: "classic-buy-1", title: "Start with a pack",
                                   message: "Spend $10 for six cards. New cards grow your collection; extra copies can fund more packs.")
        case .collection:
            guard tutorial.needs(.classicDetailDone),
                  let card = CardDatabase.cards(inSet: 1).first(where: { game.owns($0.id) }) else { return nil }
            return TutorialPrompt(target: "classic-card-\(card.id)", title: "Look closer",
                                  message: "Tap an owned card to see its evolution line, grade it, or sell spare copies.")
        case .collectors:
            return tutorial.prompt(.classicTradeTarget, target: "classic-choose-trade", title: "Pick a missing card",
                                   message: "Mira and Rowan pay cash for spares. Tess trades them for a card you choose. Set a goal with Tess.")
        case .stats: return nil
        }
    }

    private var navigationPrompt: TutorialPrompt? {
        guard !game.revealInFlight, !tutorial.needs(.classicSummary) else { return nil }
        if tutorial.needs(.classicCollection), selectedTab == .shop {
            return TutorialPrompt(target: "tab-Collection", title: "Your collection",
                                  message: "Find your cards here. Complete evolution lines and sets to earn cash bonuses.")
        }
        if !tutorial.needs(.classicDetailDone), tutorial.needs(.classicCollectors) {
            return TutorialPrompt(target: "tab-Collectors", title: "Plan a trade",
                                  message: "Collectors exchange normal spares for cash or a missing card. Let's choose a goal.")
        }
        if !tutorial.needs(.classicTradeTarget) {
            return TutorialPrompt(target: "tab-Shop", title: "You're ready!",
                                  message: "Head back for more packs. Collect all 250 cards, and keep enough cash for your next pack. The info button has the rules.")
        }
        return nil
    }

    /// Endings wait for the current transaction's presentation to finish.
    private var activeOverlay: AppOverlay? {
        // Summaries, receipts, and sale confirmations own the screen until fully
        // dismissed. The model defers both endings through those transitions.
        if game.presentsWin { return .win }
        if game.presentsGameOver { return .lose }
        return nil
    }

    /// Model-driven; dismissal happens when the ending is acknowledged.
    private var overlayBinding: Binding<AppOverlay?> {
        Binding(get: { activeOverlay }, set: { _ in })
    }

    private func refreshCollectorBadge() {
        // The tab bar can peek through the same cover transitions as the Shop.
        guard !game.revealInFlight, !game.collectorReceiptInFlight else { return }
        collectorBadgeCount = game.collectorReadyCount
    }
}

enum AppOverlay: Int, Identifiable {
    case win, lose
    var id: Int { rawValue }
}

/// The main tabs, so `ClassicModeView` can drive selection programmatically.
enum AppTab: Hashable {
    case shop, collectors, collection, stats
}
