import SwiftUI

struct ContentView: View {
    @Environment(GameState.self) var game: GameState

    /// Which tab is on screen. Bound so the app can steer the player — e.g. onto
    /// the Shop right after they start a run.
    @State private var selectedTab: AppTab = .shop

    var body: some View {
        TabView(selection: $selectedTab) {
            ShopView()
                .tabItem { Label("Shop", systemImage: "bag.fill") }
                .tag(AppTab.shop)
            CollectionView()
                .tabItem { Label("Collection", systemImage: "square.grid.3x3.fill") }
                .tag(AppTab.collection)
            StatsView()
                .tabItem { Label("Stats", systemImage: "chart.bar.fill") }
                .tag(AppTab.stats)
        }
        .tint(Palette.money)
        // "Start Collecting" is the only way out of the welcome intro, so its
        // dismissal marks the start of a run — first launch, after a download,
        // or a reset. Drop the player on the Shop, where a run begins, even if
        // they kicked the reset off from another tab.
        .onChange(of: game.shouldShowWelcome) { wasShowing, isShowing in
            if wasShowing && !isShowing { selectedTab = .shop }
        }
        .overlay(alignment: .top) { MilestoneToastHost() }
        .fullScreenCover(item: overlayBinding) { overlay in
            switch overlay {
            case .welcome: WelcomeView()
            case .win:     WinView()
            case .bazaar:  BazaarView()
            case .lose:    LoseView()
            }
        }
        .alert(game.loadIssue?.title ?? "", isPresented: loadIssueBinding) {
            Button("OK", role: .cancel) { game.dismissLoadIssue() }
        } message: {
            Text(game.loadIssue?.message ?? "")
        }
    }

    /// Which full-screen overlay (if any) the current model state calls for.
    /// A single cover handles them all so transitions (Show cleared → Bazaar →
    /// next Show, or Season Over → New Season → Welcome) swap content in place
    /// instead of fighting over separate presentations.
    private var activeOverlay: AppOverlay? {
        if game.shouldShowWelcome { return .welcome }
        // A pack reveal owns the screen until the player finishes its summary.
        // Win and Game Over both wait for it (`presentsWin` / `presentsGameOver`),
        // so a Quota-clearing — or wallet-emptying — pull plays out fully first.
        if game.presentsWin { return .win }
        // Between Shows the player shops the Bazaar before the next Show begins.
        if game.atBazaar { return .bazaar }
        if game.presentsGameOver { return .lose }
        return nil
    }

    /// Model-driven; dismissal happens when the state clears (markWelcomeSeen /
    /// acknowledgeWin / newGame), so the setter is intentionally a no-op.
    private var overlayBinding: Binding<AppOverlay?> {
        Binding(get: { activeOverlay }, set: { _ in })
    }

    /// Presents the save-load notice until the player dismisses it.
    private var loadIssueBinding: Binding<Bool> {
        Binding(get: { game.loadIssue != nil },
                set: { if !$0 { game.dismissLoadIssue() } })
    }
}

enum AppOverlay: Int, Identifiable {
    case welcome, win, bazaar, lose
    var id: Int { rawValue }
}

/// The three main tabs, so `ContentView` can drive selection programmatically.
enum AppTab: Hashable {
    case shop, collection, stats
}

// MARK: - The Bazaar

/// Shown between Shows. The player takes one free Draft pick, optionally buys
/// Trainers / Power-Ups / Energy with the cash they raised, then starts the next
/// Show. Everything here shapes the current Season only.
struct BazaarView: View {
    @Environment(GameState.self) var game: GameState

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "141a2c"), Palette.bg0],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    header
                    walletRow
                    if !game.draftOffers.isEmpty { draftSection }
                    bazaarSection
                    buildSection
                }
                .padding(16)
                .readableWidth()
            }
        }
        .safeAreaInset(edge: .bottom) { enterBar }
        .onAppear { Haptics.play(.light) }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("THE BAZAAR")
                .font(.system(size: 13, weight: .black)).tracking(3)
                .foregroundStyle(Color(hex: "5aa9ff"))
                .padding(.top, 24)
            Text("Before Show \(game.show)")
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Text("Spend what you raised on gear for the rest of the Season.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.subtle)
                .multilineTextAlignment(.center)
        }
    }

    private var walletRow: some View {
        HStack(spacing: 12) {
            StatTile(label: "Cash", value: game.cash.money, tint: Palette.money)
            StatTile(label: "Renown", value: "\(game.renown)", tint: Color(hex: "b06cf7"))
            StatTile(label: "Trainer Slots",
                     value: "\(game.activeTrainers.count)/\(game.trainerSlots)",
                     tint: Color(hex: "5aa9ff"))
        }
    }

    private var draftSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FREE DRAFT · PICK ONE")
                .font(.system(size: 12, weight: .black)).tracking(1).foregroundStyle(Palette.subtle)
            ForEach(game.draftOffers) { boost in
                BoostOfferCard(boost: boost, priced: false,
                               affordable: game.hasSlotFor(boost)) {
                    if game.takeDraft(boost.id) { Haptics.play(.success); Sound.play(.purchase) }
                    else { Haptics.play(.error) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bazaarSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("BAZAAR")
                    .font(.system(size: 12, weight: .black)).tracking(1).foregroundStyle(Palette.subtle)
                Spacer()
                Button {
                    if game.rerollBazaar() { Haptics.play(.light) } else { Haptics.play(.error) }
                } label: {
                    Label("Reroll · \(game.rerollCost.money)", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(game.cash >= game.rerollCost ? Color(hex: "5aa9ff") : Palette.subtle)
                }
                .buttonStyle(.plain)
                .disabled(game.cash < game.rerollCost)
            }
            if game.bazaarOffers.isEmpty {
                Text("Sold out — reroll or start the Show.")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.subtle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ForEach(game.bazaarOffers) { boost in
                    BoostOfferCard(boost: boost, priced: true,
                                   affordable: game.canAffordBoost(boost) && game.hasSlotFor(boost)) {
                        if game.buyFromBazaar(boost.id) { Haptics.play(.medium); Sound.play(.purchase) }
                        else { Haptics.play(.error) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The player's current build: held Trainers (passive all Season) and
    /// Power-Ups (spend Energy in a Show).
    @ViewBuilder private var buildSection: some View {
        if !game.activeTrainers.isEmpty || !game.heldPowerUps.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("YOUR BUILD")
                    .font(.system(size: 12, weight: .black)).tracking(1).foregroundStyle(Palette.subtle)
                ForEach(game.activeTrainers) { t in
                    BuildRow(icon: "person.text.rectangle.fill", tint: Color(hex: "39b56a"),
                             name: t.name, blurb: t.blurb)
                }
                ForEach(Array(game.heldPowerUps.enumerated()), id: \.offset) { _, p in
                    BuildRow(icon: "bolt.fill", tint: Color(hex: "ffd54a"),
                             name: p.name, blurb: "\(p.energyCost)⚡ · \(p.blurb)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var enterBar: some View {
        BigButton(title: "Enter Show \(game.show)",
                  subtitle: game.isChampionshipShow ? "The Masters Invitational — win the Season"
                                                    : "Fresh rips and Energy await",
                  systemImage: "flag.checkered",
                  tint: [Color(hex: "5aa9ff"), Color(hex: "6d5cf7")]) {
            Haptics.play(.medium)
            game.enterShow(twistId: nil)
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)
        .readableWidth()
        .background(
            LinearGradient(colors: [Palette.bg0.opacity(0), Color(hex: "0d1220").opacity(0.95)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

/// One offer in the Draft or Bazaar: kind badge, name, blurb, and a Pick/Buy
/// affordance (free for drafts, priced in the Bazaar).
struct BoostOfferCard: View {
    let boost: BoostCard
    let priced: Bool
    let affordable: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: boost.kind.symbol)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(kindTint)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(kindTint.opacity(0.14)))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(boost.name).font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.text)
                            .lineLimit(1)
                        Text(boost.kind.display.uppercased())
                            .font(.system(size: 8.5, weight: .black))
                            .foregroundStyle(kindTint)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Capsule().fill(kindTint.opacity(0.15)))
                    }
                    Text(boost.blurb).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Palette.subtle)
                        .lineLimit(2).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                Text(priced ? boost.cost.money : "PICK")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(priced ? Palette.money : Color(hex: "06301b"))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(
                        Capsule().fill(priced ? AnyShapeStyle(Palette.bg0.opacity(0.6))
                                              : AnyShapeStyle(LinearGradient(colors: [Color(hex: "b8ffd6"), Palette.money],
                                                               startPoint: .leading, endPoint: .trailing)))
                    )
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16).fill(Palette.panel))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.stroke, lineWidth: 1))
            .opacity(affordable ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!affordable)
    }

    private var kindTint: Color {
        switch boost.kind {
        case .trainer: return Color(hex: "39b56a")
        case .powerUp: return Color(hex: "ffd54a")
        case .energy:  return Color(hex: "5aa9ff")
        }
    }
}

/// A single line in the Bazaar's "Your Build" recap.
struct BuildRow: View {
    let icon: String
    let tint: Color
    let name: String
    let blurb: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 15, weight: .bold)).foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(Circle().fill(tint.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.text)
                Text(blurb).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.subtle)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 13).fill(Palette.bg0.opacity(0.5)))
    }
}

// MARK: - Milestone toasts

/// Pops permanent-unlock celebrations one at a time as they fire, draining the
/// `GameState` queue regardless of which action (a pull, a cut, a power-up)
/// triggered them.
struct MilestoneToastHost: View {
    @Environment(GameState.self) var game: GameState
    @State private var queue: [MilestoneEvent] = []
    @State private var current: MilestoneEvent?

    var body: some View {
        VStack {
            if let current {
                MilestoneToast(event: current)
                    .id(current.id)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.horizontal, 16).padding(.top, 8)
            }
            Spacer(minLength: 0)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: current?.id)
        .allowsHitTesting(false)
        .onChange(of: game.pendingMilestones.count) { _, _ in enqueue() }
        .onAppear { enqueue() }
    }

    private func enqueue() {
        let drained = game.drainMilestones()
        guard !drained.isEmpty else { return }
        queue.append(contentsOf: drained)
        showNext()
    }

    private func showNext() {
        guard current == nil, !queue.isEmpty else { return }
        current = queue.removeFirst()
        Haptics.play(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            current = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showNext() }
        }
    }
}

struct MilestoneToast: View {
    let event: MilestoneEvent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "rosette").font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color(hex: "ffd54a"))
            VStack(alignment: .leading, spacing: 2) {
                Text("MILESTONE · \(event.title.uppercased())")
                    .font(.system(size: 11, weight: .black)).tracking(0.5)
                    .foregroundStyle(Color(hex: "ffd54a"))
                Text(event.detail).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.text)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            Text("+\(event.renown)★")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(Color(hex: "b06cf7"))
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Palette.bg1))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color(hex: "ffd54a").opacity(0.4), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
    }
}
