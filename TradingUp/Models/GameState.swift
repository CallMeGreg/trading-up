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

    private var rng = SystemRandomNumberGenerator()
    private let store: SaveStore

    init(store: SaveStore = SaveStore()) {
        self.store = store
        let (loaded, issue) = store.load()
        core = loaded ?? GameCore()
        loadIssue = issue
        // Persist immediately if load had to repair or quarantine something, so
        // the cleaned state is what's on disk from here on.
        if issue != nil { store.save(core) }
    }

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
