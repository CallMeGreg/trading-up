import SwiftUI

struct ShopView: View {
    @Environment(GameState.self) var game: GameState
    @Environment(PurchaseStore.self) private var purchases: PurchaseStore
    /// Sends the player back to the main menu. Provided by `ClassicModeView`; the
    /// Shop's wallet header hosts the only home button in Classic mode.
    var onHome: (() -> Void)? = nil
    @State private var pending: PendingOpen?
    /// Collection counts captured at purchase time. While a reveal is on screen
    /// the shop shows these frozen values so the fullScreenCover sliding in/out
    /// never briefly spoilers how many new uniques the pack contained.
    @State private var freeze: ShopFreeze?
    /// Drives the full-version unlock paywall, opened from a paid, locked set.
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                WalletHeader(freeze: freeze, onHome: onHome)
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(1...CardDatabase.setCount, id: \.self) { set in
                            SetShelfRow(set: set, freeze: freeze, revealInFlight: isRevealInFlight,
                                        unlockPriceText: purchases.fullUnlock?.displayPrice,
                                        onBuyPack: { buyPack(set) },
                                        onBuyBox: { buyBox(set) },
                                        onUnlock: { showPaywall = true })
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
                    .readableWidth()
                }
            }
            .background(Palette.screen.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .fullScreenCover(item: $pending, onDismiss: { freeze = nil; game.endReveal() }) { p in
            RevealView(content: p.content, set: p.set) { pending = nil }
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }

    private func buyPack(_ set: Int) {
        let wasBlocked = freeze != nil
        let started = Self.attemptPurchase(
            freeze: &freeze, pending: &pending,
            freezeSnapshot: ShopFreeze(game),
            buy: { game.buyPack(set: set) },
            makePending: { PendingOpen(content: .pack($0), set: set) }
        )
        guard !wasBlocked else { return }   // reveal already in flight: silent no-op
        if started {
            game.beginReveal()
            Haptics.play(.medium)
            Sound.play(.purchase)
        } else {
            Haptics.play(.error)
        }
    }

    private func buyBox(_ set: Int) {
        let wasBlocked = freeze != nil
        let started = Self.attemptPurchase(
            freeze: &freeze, pending: &pending,
            freezeSnapshot: ShopFreeze(game),
            buy: { game.buyBoxPacks(set: set) },
            makePending: { PendingOpen(content: .box(results: $0), set: set) }
        )
        guard !wasBlocked else { return }   // reveal already in flight: silent no-op
        if started {
            game.beginReveal()
            Haptics.play(.heavy)
            Sound.play(.purchase)
        } else {
            Haptics.play(.error)
        }
    }

    /// Whether a reveal is currently pending or on screen. `freeze` (rather
    /// than `pending`) is the sentinel: both are set the instant a purchase
    /// commits and cleared together only when the reveal's `fullScreenCover`
    /// finishes dismissing, so `freeze` exactly brackets the window a
    /// double-tap (or a tap during the cover's slide-in animation) could
    /// otherwise exploit into charging the player twice for one visible reveal.
    var isRevealInFlight: Bool { freeze != nil }

    /// Attempts to start a pack/box purchase. If a reveal is already pending
    /// or on screen, `buy` is never invoked — so a blocked attempt cannot
    /// deduct cash, increment stats, or add cards to the collection. Returns
    /// `true` only when a new reveal was started. Free of `GameState`/view
    /// dependencies beyond `ShopFreeze`/`PendingOpen`, so the guard itself is
    /// directly unit-testable without standing up a live `ShopView`.
    @discardableResult
    static func attemptPurchase<Result>(
        freeze: inout ShopFreeze?,
        pending: inout PendingOpen?,
        freezeSnapshot: @autoclosure () -> ShopFreeze,
        buy: () -> Result?,
        makePending: (Result) -> PendingOpen
    ) -> Bool {
        guard freeze == nil else { return false }
        let snapshot = freezeSnapshot()
        guard let result = buy() else { return false }
        freeze = snapshot
        pending = makePending(result)
        return true
    }
}

/// A snapshot of the wallet + collection counts the Shop displays, captured just
/// before a pack/box is opened. Held while the reveal is on screen so the
/// underlying shop doesn't reveal the pull's new-unique count — or, via the
/// bankroll jumping on an evolution/set-completion bonus, that the pack completed
/// something — during the cover transition. Cash and net worth resolve to their
/// post-pack values only once the reveal is dismissed.
struct ShopFreeze {
    let cash: Double
    let netWorth: Double
    let uniqueCount: Int
    let ownedInSet: [Int: Int]

    @MainActor
    init(_ game: GameState) {
        cash = game.cash
        netWorth = game.netWorth
        uniqueCount = game.uniqueCount
        var owned: [Int: Int] = [:]
        for set in 1...CardDatabase.setCount { owned[set] = game.ownedCount(inSet: set) }
        ownedInSet = owned
    }
}

// MARK: - Wallet header

/// The money bar that stays put at the top of the shop. Cash is the number that
/// decides every tap on this screen, so it never scrolls out of reach.
struct WalletHeader: View {
    @Environment(GameState.self) var game: GameState
    var freeze: ShopFreeze? = nil
    /// When set, a home button is shown at the leading edge that returns to the
    /// main menu. The wallet rows shift right to make room for it.
    var onHome: (() -> Void)? = nil

    private var cash: Double { freeze?.cash ?? game.cash }
    private var netWorth: Double { freeze?.netWorth ?? game.netWorth }
    private var uniqueCount: Int { freeze?.uniqueCount ?? game.uniqueCount }

    var body: some View {
        HStack(spacing: 12) {
            if let onHome {
                Button(action: onHome) {
                    Image(systemName: "house.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Palette.text)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Palette.panelHi))
                        .overlay(Circle().stroke(.white.opacity(0.08), lineWidth: 1))
                }
                .accessibilityLabel("Home")
            }
            VStack(spacing: 9) {
                HStack(alignment: .center, spacing: 10) {
                    HStack(spacing: 8) {
                        Text("$")
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .foregroundStyle(Color(hex: "06301b"))
                            .frame(width: 30, height: 30)
                            .background(
                                Circle().fill(
                                    RadialGradient(colors: [Color(hex: "b8ffd6"), Palette.money, Color(hex: "2c9c5c")],
                                                   center: UnitPoint(x: 0.35, y: 0.3), startRadius: 1, endRadius: 26)
                                )
                            )
                            .shadow(color: Palette.money.opacity(0.35), radius: 3, y: 2)
                        Text(cash.money)
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .foregroundStyle(Palette.money)
                            .contentTransition(.numericText())
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Cash \(cash.money)")

                    Spacer(minLength: 0)

                    VStack(alignment: .trailing, spacing: 1) {
                        Text("NET WORTH")
                            .font(.system(size: 10, weight: .heavy)).tracking(0.8)
                            .foregroundStyle(Palette.subtle)
                        Text(netWorth.moneyShort)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(Palette.text)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Net worth \(netWorth.money)")
                }

                HStack(spacing: 8) {
                    Text("BINDER")
                        .font(.system(size: 11, weight: .bold)).tracking(0.3)
                        .foregroundStyle(Palette.subtle)
                    ProgressBar(value: Double(uniqueCount), total: Double(game.totalCards),
                                tint: Palette.money, height: 6)
                    Text("\(uniqueCount)/\(game.totalCards)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Palette.subtle)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Collection \(uniqueCount) of \(game.totalCards)")
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .readableWidth()
        .frame(maxWidth: .infinity)
        .background(Palette.bg1.opacity(0.96))
        .overlay(alignment: .bottom) {
            Rectangle().fill(.white.opacity(0.07)).frame(height: 1)
        }
    }
}

// MARK: - Per-set shelf row

/// One set on the shop shelf: the pack itself, how far the set has come, one
/// obvious buy, and — unless `FeatureFlags.removeBoosterBoxes` is on — the
/// booster box as a quiet second line rather than a rival button.
struct SetShelfRow: View {
    @Environment(GameState.self) var game: GameState
    let set: Int
    var freeze: ShopFreeze? = nil
    /// Disables both buys while a reveal is pending/on screen, so the
    /// affordance matches the behaviour instead of silently swallowing taps.
    var revealInFlight: Bool = false
    /// Localized price of the full-version unlock, shown on the paywall callout
    /// when the product has loaded. Passed in from the shop (which holds the
    /// StoreKit layer) so this row needn't depend on `PurchaseStore` directly.
    var unlockPriceText: String? = nil
    let onBuyPack: () -> Void
    let onBuyBox: () -> Void
    let onUnlock: () -> Void

    private var element: Element { Element.theme(forSet: set) }
    private var displayUnique: Int { freeze?.uniqueCount ?? game.uniqueCount }
    private var owned: Int { freeze?.ownedInSet[set] ?? game.ownedCount(inSet: set) }
    private var packPrice: Double { Economy.packPrice(set: set) }
    private var boxPrice: Double { Economy.boxPrice(set: set) }
    private var unlockThreshold: Int { game.uniquesToUnlock(set: set) }
    /// Progression gate only: enough unique cards owned to unlock this set.
    private var unlocked: Bool { displayUnique >= unlockThreshold }
    /// A paid set (2–5) still behind the one-time full-version purchase.
    private var requiresPurchase: Bool { game.requiresFullUnlock(set: set) }
    /// Fully playable: past the paywall *and* past the progression gate. Drives
    /// the row's art dim, lock icon and title.
    private var isOpen: Bool { !requiresPurchase && unlocked }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            PackWrapper(set: set, width: 58, detail: .mini)
                .opacity(isOpen ? 1 : 0.35)
                .saturation(isOpen ? 1 : 0.4)
                .brightness(isOpen ? 0 : -0.15)
            VStack(alignment: .leading, spacing: 9) {
                title
                if requiresPurchase {
                    paywallCallout
                } else if unlocked {
                    unlockedActions
                } else {
                    lockedCallout
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .padding(.vertical, 14)
        .background {
            ZStack(alignment: .leading) {
                Palette.panel
                RadialGradient(colors: [element.palette[2].opacity(isOpen ? 0.26 : 0.08), .clear],
                               center: .topLeading, startRadius: 0, endRadius: 260)
                LinearGradient(colors: [element.palette[1], element.palette[2]],
                               startPoint: .top, endPoint: .bottom)
                    .frame(width: 4)
                    .opacity(isOpen ? 1 : 0.4)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Palette.stroke, lineWidth: 1))
    }

    private var title: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(CardDatabase.setName(set))
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(isOpen ? "Set \(set) · \(owned) of 50 collected" : "Set \(set) · locked")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Palette.subtle)
            }
            Spacer(minLength: 0)
            if isOpen {
                if owned == 50 {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Palette.money)
                        .accessibilityLabel("Set complete")
                } else {
                    ProgressRing(value: owned, total: 50, tint: element.palette[1])
                }
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Palette.subtle)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var unlockedActions: some View {
        VStack(spacing: 8) {
            Button(action: onBuyPack) {
                HStack {
                    Text("Buy a pack").font(.system(size: 15, weight: .bold))
                    Spacer(minLength: 8)
                    Text(packPrice.money).font(.system(size: 15, weight: .black, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.vertical, 11).padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 13).fill(
                        LinearGradient(colors: canBuyPack ? [element.palette[1], element.palette[2]]
                                                          : [Palette.stroke, Palette.stroke.opacity(0.7)],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                )
                .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.white.opacity(0.2), lineWidth: 1))
                .opacity(canBuyPack ? 1 : 0.55)
            }
            .buttonStyle(.plain)
            .disabled(!canBuyPack)
            .accessibilityIdentifier("buyPack")
            .accessibilityLabel("Buy a pack, \(CardDatabase.setName(set)), 6 cards, \(packPrice.money)")

            if FeatureFlags.boosterBoxesAvailable {
                Button(action: onBuyBox) {
                    HStack(spacing: 6) {
                        Text("Booster box · ").foregroundStyle(Palette.subtle)
                        + Text(boxPrice.money).foregroundStyle(Palette.text).fontWeight(.bold)
                        + Text(" · ≥\(Economy.boxGuaranteeUltras) ultra, ≥\(Economy.boxGuaranteeFoils) foil").foregroundStyle(Palette.subtle)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Palette.subtle)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.75)
                    .padding(.horizontal, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .opacity(canBuyBox ? 1 : 0.5)
                }
                .buttonStyle(.plain)
                .disabled(!canBuyBox)
                .accessibilityIdentifier("buyBox")
                .accessibilityLabel("Buy Booster Box, \(CardDatabase.setName(set)), \(Economy.boxPacks) packs, \(boxPrice.money)")
            }
        }
    }

    /// Shown on paid sets (2–5) while the one-time full-version unlock is
    /// inactive. Tapping opens the paywall; the actual gate is enforced in
    /// `GameState.buyPack`, so this is purely the affordance.
    private var paywallCallout: some View {
        Button(action: onUnlock) {
            HStack(spacing: 8) {
                Image(systemName: "lock.open.fill").font(.system(size: 13, weight: .bold))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Unlock the full game").font(.system(size: 14, weight: .bold))
                    Text(unlockSubtitle).font(.system(size: 11, weight: .medium)).opacity(0.9)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).opacity(0.85)
            }
            .foregroundStyle(.white)
            .padding(.vertical, 10).padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 13).fill(
                    LinearGradient(colors: [Palette.money, Color(hex: "39b56a")],
                                   startPoint: .leading, endPoint: .trailing)
                )
            )
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.white.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("unlockFullGame")
        .accessibilityLabel("Unlock the full game to play \(CardDatabase.setName(set)). \(unlockSubtitle)")
    }

    private var unlockSubtitle: String {
        if let price = unlockPriceText { return "\(price) · sets 2–5 + the full 250" }
        return "Sets 2–5 + the full 250-card collection"
    }

    private var lockedCallout: some View {
        let remaining = max(0, unlockThreshold - displayUnique)
        return HStack(spacing: 8) {
            Image(systemName: "lock.fill").font(.system(size: 11, weight: .bold))
            Text("**\(remaining) more** unique card\(remaining == 1 ? "" : "s") to unlock")
                .font(.system(size: 12.5, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Palette.subtle)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 13)
                .strokeBorder(Palette.stroke, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Locked. Collect \(remaining) more unique cards to unlock \(CardDatabase.setName(set)).")
    }

    private var canBuyPack: Bool { game.canAffordPack(set: set) && !revealInFlight }
    private var canBuyBox: Bool { game.canAffordBox(set: set) && !revealInFlight }
}

/// Set completion as a dial: the number plus how much of the circle is filled,
/// which reads faster in a list than a full-width bar per row.
struct ProgressRing: View {
    let value: Int
    let total: Int
    var tint: Color = Palette.money
    var size: CGFloat = 42

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return max(0, min(1, Double(value) / Double(total)))
    }

    var body: some View {
        ZStack {
            Circle().strokeBorder(.white.opacity(0.09), lineWidth: 4)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(2)
            Text("\(value)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.text)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// What a `RevealView` is opening: a single already-opened pack, or a booster
/// box whose packs are revealed one at a time (all cards are already added).
enum RevealContent {
    case pack(OpenResult)
    case box(results: [OpenResult])
}

/// Identifiable wrapper so a pending open can drive `.fullScreenCover(item:)`.
struct PendingOpen: Identifiable {
    let id = UUID()
    let content: RevealContent
    let set: Int
}
