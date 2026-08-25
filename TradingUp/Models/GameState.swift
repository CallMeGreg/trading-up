import Foundation

/// Observable wrapper around the pure `GameCore`. Owns randomness and persistence
/// so SwiftUI views stay declarative. All mutations funnel through here and autosave.
@Observable
@MainActor
final class GameState {
    private(set) var core: GameCore

    /// Set when the last load didn't go cleanly, so the UI can tell the player
    /// rather than silently presenting them with a fresh game.
    private(set) var loadIssue: SaveLoadIssue?

    /// True while a pack or box reveal is on screen. The win celebration (and,
    /// symmetrically, the Game Over screen) holds off until this clears, so a
    /// collection-completing — or wallet-emptying — pull plays out in full,
    /// every card then the keep/sell summary, before a full-screen overlay
    /// slides in on top of it. Purely presentation state: never persisted, and
    /// deliberately kept out of the pure `GameCore`.
    private(set) var revealInFlight = false

    private var rng = AppRNG()
    private let store: SaveStore

    /// How many sets are playable for free. Set 1 (Emberfall) is the free tier;
    /// sets above this need the one-time "Unlock the full collection" purchase.
    /// A single tuning point should the free slice ever change.
    static let freeSetCount = 1

    /// Whether the one-time full-version unlock is active. Sets above
    /// `freeSetCount` gate *buying packs* on this; Set 1 is always free, and
    /// cards already owned in paid sets stay viewable regardless.
    ///
    /// StoreKit is the source of truth: the `Store` layer verifies
    /// `Transaction.currentEntitlements` on launch and on every transaction
    /// update, then pushes the result here. Nothing in the pure `GameCore`
    /// reads it, so the model and the `tools/verify` harness are untouched. It's
    /// plain instance state rather than a build-time `FeatureFlags` switch
    /// because it turns on at runtime when the player buys — but, like those
    /// flags, it's trivially settable in tests to exercise both the locked and
    /// the unlocked game.
    private(set) var isFullVersionUnlocked = false

    init(store: SaveStore = SaveStore()) {
        self.store = store
        #if DEBUG
        // An automated test (or a developer) can launch straight into a scripted
        // late-game state instead of loading the real save. Compiled out of
        // release builds entirely, so a shipped App Store build has no way in.
        if let seeded = DebugLaunchState.core() {
            core = seeded
            core.ensureActiveRun()
            loadIssue = nil
            // An optional seed pins the RNG so a scripted run (the recorded
            // ending demo) pulls the exact same cards every time.
            if let seed = DebugLaunchState.seed() { rng = AppRNG(seed: seed) }
            store.save(core)
            return
        }
        #endif
        let (loaded, issue) = store.load()
        core = loaded ?? GameCore()
        core.ensureActiveRun()   // a fresh game — or a pre-Circuit save — joins the Circuit
        loadIssue = issue
        // Persist immediately if load had to repair or quarantine something, so
        // the cleaned state is what's on disk from here on.
        if issue != nil { store.save(core) }
    }

    #if DEBUG
    /// Test seam: build a state around an explicit core, bypassing disk. Only
    /// compiled into DEBUG (test) builds, so it can't be reached in production.
    init(core: GameCore, store: SaveStore) {
        self.store = store
        var core = core
        core.ensureActiveRun()   // the shop is always inside an active Show, same as the real init
        self.core = core
        self.loadIssue = nil
    }
    #endif

    // MARK: Read-through conveniences

    var cash: Double { core.cash }
    var stats: Stats { core.stats }
    /// "All time" totals: completed runs plus this still-in-progress one,
    /// so a reset never looks like it erased anything.
    var lifetimeStats: LifetimeStats { core.lifetimeIncludingCurrentRun }
    var uniqueCount: Int { core.uniqueCount }
    var totalCards: Int { CardDatabase.all.count }
    var collectionValue: Double { core.collectionValue }
    var netWorth: Double { core.netWorth }
    var hasWon: Bool { core.hasWon }
    var shouldShowWin: Bool { core.shouldShowWin }
    /// Whether the win celebration should actually be on screen *right now*.
    /// Distinct from the model's `shouldShowWin`: the overlay also waits for any
    /// pack/box reveal to finish, so the collection-completing pull plays all
    /// the way through — reveal, then pack summary — before the win takes over.
    var presentsWin: Bool { core.shouldShowWin && !revealInFlight }
    /// Game Over, gated the same way, so the final affordable pack still gets
    /// revealed before the losing screen appears.
    var presentsGameOver: Bool { core.isGameOver && !revealInFlight }
    /// A personalized, shareable fingerprint of the (winning) run, driving the
    /// one-of-a-kind collector card on the win screen.
    var runSignature: RunSignature { RunSignature.make(from: core) }
    var isGameOver: Bool { core.isGameOver }
    var shouldShowWelcome: Bool { core.shouldShowWelcome }
    var cheapestPackPrice: Double { Economy.cheapestPackPrice }

    // MARK: The Circuit (read-through)

    var show: Int { core.run.show }
    var seasonShows: Int { Economy.seasonShows }
    var ripsRemaining: Int { core.run.ripsRemaining }
    var energy: Int { core.run.energy }
    var maxEnergy: Int { core.run.maxEnergy }
    var currentQuota: Double { core.currentQuota }
    var quotaProgress: Double { core.quotaProgress }
    var canMakeCut: Bool { core.canMakeCut }
    var isChampionshipShow: Bool { core.isChampionshipShow }
    var atBazaar: Bool { core.run.atBazaar }
    var isBust: Bool { core.isBust }
    var firstPackFreeAvailable: Bool { core.firstPackFreeAvailable }
    var guaranteedUltraNextPack: Bool { core.run.guaranteedUltraNextPack }

    var renown: Int { core.meta.renown }
    var unlockedMilestones: Set<String> { core.meta.milestones }
    var activeTrainers: [Trainer] { core.activeTrainers }
    var heldPowerUps: [PowerUp] { core.heldPowerUps }
    var activeTwist: Twist? { core.activeTwist }
    var trainerSlots: Int { core.meta.trainerSlots }
    var hasTrainerSlotFree: Bool { core.hasTrainerSlotFree }

    var draftOffers: [BoostCard] { core.run.draftIds.compactMap { BoostCatalog.boost($0) } }
    var bazaarOffers: [BoostCard] { core.run.bazaarIds.compactMap { BoostCatalog.boost($0) } }
    var rerollCost: Double { Economy.rerollCost(rerolls: core.run.rerolls) }

    func guildLevel(_ u: GuildUpgrade) -> Int { core.meta.guildLevel(u) }
    func guildMaxLevel(_ u: GuildUpgrade) -> Int { Economy.guildMaxLevel(u) }
    func guildCost(_ u: GuildUpgrade) -> Int { Economy.guildCost(u, currentLevel: core.meta.guildLevel(u)) }
    func canBuyGuild(_ u: GuildUpgrade) -> Bool { core.canBuyGuild(u) }
    func canAffordBoost(_ b: BoostCard) -> Bool { core.cash >= b.cost }
    /// Whether an offer can be taken slot-wise: Trainers need a free Trainer slot;
    /// Power-Ups and Energy never do. (Cash is checked separately.)
    func hasSlotFor(_ b: BoostCard) -> Bool {
        if case .trainer = b { return core.hasTrainerSlotFree }
        return true
    }

    /// Milestones unlocked since the UI last drained them — a small queue the
    /// app surfaces as celebratory toasts, regardless of which action fired them.
    private(set) var pendingMilestones: [MilestoneEvent] = []
    @discardableResult
    func drainMilestones() -> [MilestoneEvent] {
        let m = pendingMilestones
        pendingMilestones = []
        return m
    }

    func canAffordPack(set: Int) -> Bool { core.cash >= Economy.packPrice(set: set) }
    func canAffordBox(set: Int) -> Bool { core.cash >= Economy.boxPrice(set: set) }
    func canAffordGrade(set: Int) -> Bool { core.cash >= Economy.gradeFee(set: set) }
    func isSetUnlocked(_ set: Int) -> Bool { core.isUnlocked(set: set) }
    func uniquesToUnlock(set: Int) -> Int { Economy.uniquesToUnlock(set: set) }

    /// Whether buying into `set` needs the full-version unlock — true for the
    /// paid sets while the purchase is inactive, false for the free tier and for
    /// everything once unlocked. Drives the shop's "unlock" vs. progression
    /// callout without leaking StoreKit into the view.
    func requiresFullUnlock(set: Int) -> Bool {
        set > Self.freeSetCount && !isFullVersionUnlocked
    }
    func ownedCount(inSet set: Int) -> Int { core.ownedCount(inSet: set) }
    func instances(of cardId: String) -> [CardInstance] { core.instances(of: cardId) }
    /// Every owned copy in the current Season's binder — used by the power-up
    /// target picker to list cards a consumable can act on.
    var binderInstances: [CardInstance] { core.instances }
    func owns(_ id: String) -> Bool { core.owns(id) }
    func count(of id: String) -> Int { core.count(of: id) }
    func isSellable(_ inst: CardInstance) -> Bool { core.isSellable(inst) }

    // MARK: Mutations (autosave)

    /// Mark that a pack/box reveal has taken over the screen. Called the instant
    /// a purchase commits, so any win/lose overlay defers until `endReveal()`.
    func beginReveal() { revealInFlight = true }

    /// Mark the reveal fully dismissed. Any pending win/lose overlay can now
    /// present. Called from the reveal cover's `onDismiss`, i.e. after it has
    /// finished animating away, so the two full-screen presentations never
    /// overlap.
    func endReveal() { revealInFlight = false }

    @discardableResult
    func buyPack(set: Int) -> OpenResult? {
        // Paid sets are closed until the full-version unlock is bought, so no
        // stale call site, deep link, or UI test can spend cash opening a pack
        // behind the paywall. Set 1 is always free. (Progression — the unique
        // count — is still enforced separately inside `core.buyPack`, so a
        // purchase opens the paid sets but never *skips* their unlock.)
        guard !requiresFullUnlock(set: set) else { return nil }
        let r = core.buyPack(set: set, using: &rng)
        if r != nil { save() }
        return r
    }

    @discardableResult
    func buyBox(set: Int) -> OpenResult? {
        guard FeatureFlags.boosterBoxesAvailable else { return nil }
        guard !requiresFullUnlock(set: set) else { return nil }
        let r = core.buyBox(set: set, using: &rng)
        if r != nil { save() }
        return r
    }

    /// Open a box as a sequence of packs (all cards added immediately, revealed
    /// pack-by-pack). Returns one result per pack, or nil if unaffordable/locked
    /// — or if booster boxes have been removed from the shop, or the set is
    /// still behind the full-version paywall.
    @discardableResult
    func buyBoxPacks(set: Int) -> [OpenResult]? {
        guard FeatureFlags.boosterBoxesAvailable else { return nil }
        guard !requiresFullUnlock(set: set) else { return nil }
        let r = core.buyBoxPacks(set: set, using: &rng)
        if r != nil { save() }
        return r
    }

    // MARK: The Circuit (mutations)

    /// Open a pack inside the current Show (consumes a rip or the free first
    /// pack). The run-loop counterpart to `buyPack`. Surfaces any milestones the
    /// pull unlocked as toasts.
    @discardableResult
    func ripPack(set: Int) -> OpenResult? {
        guard !requiresFullUnlock(set: set) else { return nil }
        let r = core.ripPack(set: set, using: &rng)
        if let r {
            pendingMilestones += r.milestones
            save()
        }
        return r
    }

    /// Clear the current Show. Advances to the Bazaar (freshly stocked) before the
    /// next Show, or wins the Season at the Championship. Returns milestones fired.
    @discardableResult
    func makeCut() -> [MilestoneEvent] {
        let fired = core.makeCut()
        pendingMilestones += fired
        // Entering the Bazaar: stock the draft and shelf now (GameState owns rng).
        if core.run.atBazaar {
            core.rollDraft(using: &rng)
            core.rollBazaar(using: &rng)
        }
        save()
        return fired
    }

    /// Leave the Bazaar and begin the next Show under the chosen Twist (or none).
    func enterShow(twistId: String?) {
        core.enterShow(twistId: twistId)
        save()
    }

    @discardableResult
    func takeDraft(_ id: String) -> Bool {
        let ok = core.takeDraft(id)
        if ok { save() }
        return ok
    }

    @discardableResult
    func buyFromBazaar(_ id: String) -> Bool {
        let ok = core.buyFromBazaar(id)
        if ok { save() }
        return ok
    }

    @discardableResult
    func rerollBazaar() -> Bool {
        let ok = core.rerollBazaar(using: &rng)
        if ok { save() }
        return ok
    }

    @discardableResult
    func playPowerUp(_ id: String, target: UUID? = nil) -> Bool {
        let ok = core.playPowerUp(id, target: target, using: &rng)
        if ok {
            pendingMilestones += core.refreshMilestones()
            save()
        }
        return ok
    }

    @discardableResult
    func buyGuildUpgrade(_ u: GuildUpgrade) -> Bool {
        let ok = core.buyGuildUpgrade(u)
        if ok { save() }
        return ok
    }

    /// Start a fresh Season, banking the finished one into lifetime totals and
    /// keeping all permanent progress (Renown, milestones, Guild). Alias of
    /// `newGame()` that reads clearly at Circuit call sites.
    func startNewSeason() { newGame() }

    @discardableResult
    func sell(_ instanceId: UUID) -> Double? {
        let v = core.sell(instanceId: instanceId)
        if v != nil { save() }
        return v
    }

    func duplicateSummary(from result: OpenResult) -> (count: Int, proceeds: Double) {
        core.duplicateSummary(of: Set(result.pulled.map { $0.cardId }))
    }

    @discardableResult
    func sellDuplicates(from result: OpenResult) -> (count: Int, proceeds: Double) {
        let r = core.sellDuplicates(of: Set(result.pulled.map { $0.cardId }))
        if r.count > 0 { save() }
        return r
    }

    @discardableResult
    func grade(_ instanceId: UUID) -> GradeResult? {
        let r = core.grade(instanceId: instanceId, using: &rng)
        if r != nil { save() }
        return r
    }

    func newGame() {
        core = core.startingNewRun()
        save()
    }

    func markWelcomeSeen() {
        core.markWelcomeSeen()
        save()
    }

    /// Dismiss the win celebration but keep the completed collection.
    func acknowledgeWin() {
        core.acknowledgeWin()
        save()
    }

    func dismissLoadIssue() { loadIssue = nil }

    /// Apply the verified full-version entitlement. Called by the `Store` layer
    /// after it checks StoreKit (on launch and on transaction updates), and by
    /// tests to exercise both states. Not persisted — StoreKit is the authority,
    /// re-verified every launch — so it never touches the save file.
    func setFullVersionUnlocked(_ unlocked: Bool) { isFullVersionUnlocked = unlocked }

    private func save() {
        store.save(core)
    }
}
