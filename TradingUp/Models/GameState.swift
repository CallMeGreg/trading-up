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

    init(store: SaveStore = SaveStore()) {
        self.store = store
        #if DEBUG
        // An automated test (or a developer) can launch straight into a scripted
        // late-game state instead of loading the real save. Compiled out of
        // release builds entirely, so a shipped App Store build has no way in.
        if let seeded = DebugLaunchState.core() {
            core = seeded
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

    func canAffordPack(set: Int) -> Bool { core.cash >= Economy.packPrice(set: set) }
    func canAffordBox(set: Int) -> Bool { core.cash >= Economy.boxPrice(set: set) }
    func canAffordGrade(set: Int) -> Bool { core.cash >= Economy.gradeFee(set: set) }
    func isSetUnlocked(_ set: Int) -> Bool { core.isUnlocked(set: set) }
    func uniquesToUnlock(set: Int) -> Int { Economy.uniquesToUnlock(set: set) }
    func ownedCount(inSet set: Int) -> Int { core.ownedCount(inSet: set) }
    func instances(of cardId: String) -> [CardInstance] { core.instances(of: cardId) }
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
        let r = core.buyPack(set: set, using: &rng)
        if r != nil { save() }
        return r
    }

    @discardableResult
    func buyBox(set: Int) -> OpenResult? {
        guard FeatureFlags.boosterBoxesAvailable else { return nil }
        let r = core.buyBox(set: set, using: &rng)
        if r != nil { save() }
        return r
    }

    /// Open a box as a sequence of packs (all cards added immediately, revealed
    /// pack-by-pack). Returns one result per pack, or nil if unaffordable/locked
    /// — or if booster boxes have been removed from the shop.
    @discardableResult
    func buyBoxPacks(set: Int) -> [OpenResult]? {
        guard FeatureFlags.boosterBoxesAvailable else { return nil }
        let r = core.buyBoxPacks(set: set, using: &rng)
        if r != nil { save() }
        return r
    }

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

    private func save() {
        store.save(core)
    }
}
