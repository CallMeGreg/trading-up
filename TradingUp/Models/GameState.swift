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

    func canAffordPack(set: Int) -> Bool { core.cash >= Economy.packPrice(set: set) }
    func canAffordBox(set: Int) -> Bool { core.cash >= Economy.boxPrice(set: set) }
    func canAffordGrade(set: Int) -> Bool { core.cash >= Economy.gradeFee(set: set) }
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

    @discardableResult
    func sell(_ instanceId: UUID) -> Double? {
        let v = core.sell(instanceId: instanceId)
        if v != nil { save() }
        return v
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

    private func save() {
        if let data = try? JSONEncoder().encode(core) {
            try? data.write(to: saveURL, options: .atomic)
        }
    }
}
