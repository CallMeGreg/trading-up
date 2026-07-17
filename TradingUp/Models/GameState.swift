import Foundation
import Combine

/// Observable wrapper around the pure `GameCore`. Owns randomness and persistence
/// so SwiftUI views stay declarative. All mutations funnel through here and autosave.
final class GameState: ObservableObject {
    @Published private(set) var core: GameCore

    private var rng = SystemRandomNumberGenerator()
    private let saveURL: URL

    init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        saveURL = dir.appendingPathComponent("tradingup_save.json")
        if let data = try? Data(contentsOf: saveURL),
           let loaded = try? JSONDecoder().decode(GameCore.self, from: data) {
            core = loaded
        } else {
            core = GameCore()
        }
    }

    // MARK: Read-through conveniences

    var cash: Double { core.cash }
    var stats: Stats { core.stats }
    var uniqueCount: Int { core.uniqueCount }
    var totalCards: Int { CardDatabase.all.count }
    var collectionValue: Double { core.collectionValue }
    var netWorth: Double { core.netWorth }
    var hasWon: Bool { core.hasWon }
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
        let r = core.buyBox(set: set, using: &rng)
        if r != nil { save() }
        return r
    }

    /// Open a box as a sequence of packs (all cards added immediately, revealed
    /// pack-by-pack). Returns one result per pack, or nil if unaffordable/locked.
    @discardableResult
    func buyBoxPacks(set: Int) -> [OpenResult]? {
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
        core = GameCore()
        save()
    }

    func markWelcomeSeen() {
        core.markWelcomeSeen()
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(core) {
            try? data.write(to: saveURL, options: .atomic)
        }
    }
}
