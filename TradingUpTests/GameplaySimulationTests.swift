import XCTest
@testable import TradingUp

/// Deterministic RNG (SplitMix64) so gameplay tests are reproducible.
struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(_ seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

final class GameplaySimulationTests: XCTestCase {
    func testStartsWithStartingCash() {
        XCTAssertEqual(GameCore().cash, Economy.startingCash)
        XCTAssertTrue(GameCore().instances.isEmpty)
    }

    func testBuyingPacksChargesPriceAndYieldsBonuses() {
        var rng = SeededRNG(7)
        var core = GameCore()
        var packs = 0
        while core.cash >= Economy.packPrice(set: 1) && packs < 5 {
            let before = core.cash
            let r = core.buyPack(set: 1, using: &rng)
            XCTAssertNotNil(r, "pack \(packs + 1) should purchase")
            let bonus = r!.bonuses.reduce(0) { $0 + $1.amount }
            XCTAssertEqual(core.cash, before - 10 + bonus, accuracy: 0.001)
            XCTAssertEqual(r!.pulled.count, 6, "pack should yield 6 cards")
            packs += 1
        }
        XCTAssertEqual(core.instances.count, packs * 6, "collection should grow by 6 per pack")
    }

    func testCannotSellLastCopy() {
        var rng = SeededRNG(7)
        var core = GameCore()
        for _ in 0..<3 { _ = core.buyPack(set: 1, using: &rng) }
        if let singleton = core.instances.first(where: { core.count(of: $0.cardId) == 1 }) {
            XCTAssertNil(core.sell(instanceId: singleton.id), "cannot sell the only copy of a card")
        }
    }

    func testSellingADuplicateAddsCash() {
        var rng = SeededRNG(7)
        var core = GameCore()
        for _ in 0..<3 { _ = core.buyPack(set: 1, using: &rng) }
        if let dup = core.sellableInstances.first {
            let before = core.cash
            let v = core.sell(instanceId: dup.id)
            XCTAssertNotNil(v)
            XCTAssertGreaterThan(core.cash, before)
        }
    }

    func testGradingProducesAValidPSAGrade() {
        var rng = SeededRNG(7)
        var core = GameCore()
        core.cash += 50
        for _ in 0..<3 { _ = core.buyPack(set: 1, using: &rng) }
        if let gradeable = core.instances.first(where: { $0.card.rarity.canBeGraded && $0.grade == nil }) {
            let res = core.grade(instanceId: gradeable.id, using: &rng)
            XCTAssertNotNil(res)
            if let res { XCTAssertTrue((1...10).contains(res.grade)) }
        }
    }

    func testGameOverThresholds() {
        var broke = GameCore()
        broke.cash = 0
        broke.instances = [CardInstance(cardId: "S1-001")]
        XCTAssertTrue(broke.isGameOver, "broke with only last-copies should be game over")
        broke.instances.append(CardInstance(cardId: "S1-001"))
        XCTAssertFalse(broke.isGameOver, "broke but holding a sellable duplicate should not be over")

        XCTAssertEqual(Economy.cheapestPackPrice, 10, "cheapest pack price should be $10")
        var edge = GameCore()
        edge.instances = [CardInstance(cardId: "S1-001")]
        edge.cash = Economy.cheapestPackPrice - 0.01
        XCTAssertTrue(edge.isGameOver, "just under cheapest pack price with no sellables = game over")
        edge.cash = Economy.cheapestPackPrice
        XCTAssertFalse(edge.isGameOver, "== cheapest pack price should still be in the game")
    }

    func testWinConditionAndBonusPayout() {
        var core = GameCore()
        for c in CardDatabase.all { core.instances.append(CardInstance(cardId: c.id)) }
        let events = core.checkBonuses()
        XCTAssertTrue(core.hasWon, "owning all 250 cards should trigger a win")
        XCTAssertEqual(core.claimedSets.count, 5)
        XCTAssertEqual(core.claimedEvoLines.count, 65)
        XCTAssertEqual(events.count, 70, "65 evolution + 5 set bonuses")
        let expected = 34.0 * (10 + 30 + 75 + 160 + 320)
        XCTAssertEqual(core.cash, 100 + expected, accuracy: 0.01)
        XCTAssertTrue(core.checkBonuses().isEmpty, "bonuses should not be paid twice")
    }

    func testSellDuplicatesKeepsOneOfEach() {
        var core = GameCore()
        core.instances = [
            CardInstance(cardId: "S1-001"), CardInstance(cardId: "S1-001"), CardInstance(cardId: "S1-001"),
            CardInstance(cardId: "S1-002"),
            CardInstance(cardId: "S1-003"), CardInstance(cardId: "S1-003"),
        ]
        let ids: Set<String> = ["S1-001", "S1-002", "S1-003"]
        let preview = core.duplicateSummary(of: ids)
        XCTAssertEqual(preview.count, 3, "2×S1-001 + 1×S1-003 duplicates expected")

        let startCash = core.cash
        let uniquesBefore = core.uniqueCount
        let sold = core.sellDuplicates(of: ids)
        XCTAssertEqual(sold.count, 3)
        XCTAssertEqual(sold.proceeds, preview.proceeds, accuracy: 0.001)
        XCTAssertEqual(core.cash, startCash + sold.proceeds, accuracy: 0.001)
        XCTAssertEqual(core.count(of: "S1-001"), 1)
        XCTAssertEqual(core.count(of: "S1-002"), 1)
        XCTAssertEqual(core.count(of: "S1-003"), 1)
        XCTAssertEqual(core.uniqueCount, uniquesBefore, "no unique cards should be lost")
        XCTAssertEqual(core.instances.count, 3)
    }

    func testSellDuplicatesKeepsMostValuableCopy() {
        var core = GameCore()
        var foilCopy = CardInstance(cardId: "S1-050"); foilCopy.foil = true
        core.instances = [CardInstance(cardId: "S1-050"), CardInstance(cardId: "S1-050"), foilCopy]
        _ = core.sellDuplicates(of: ["S1-050"])
        XCTAssertEqual(core.count(of: "S1-050"), 1)
        XCTAssertEqual(core.instances(of: "S1-050").first?.foil, true, "the foil copy should be kept")
    }

    func testPreOwnedSnapshotTracksUniquesBeforePack() {
        var rng = SeededRNG(7)
        var core = GameCore()
        core.cash = 100_000
        let r1 = core.buyPack(set: 1, using: &rng)
        XCTAssertEqual(r1?.preOwnedIds.isEmpty, true, "first pack has nothing pre-owned")
        let ownedAfter1 = core.uniqueOwnedIds
        let r2 = core.buyPack(set: 1, using: &rng)
        XCTAssertEqual(r2?.preOwnedIds, ownedAfter1)
        let newInFirst = Set(r1!.pulled.map { $0.cardId }).subtracting(r1!.preOwnedIds)
        XCTAssertFalse(newInFirst.isEmpty, "first pack should yield at least one brand-new card")
        let rb = core.buyBox(set: 1, using: &rng)
        XCTAssertEqual(rb?.preOwnedIds.contains(where: { ownedAfter1.contains($0) }), true)
    }

    func testBoosterBoxYieldsPacksWithGuarantees() {
        var rng = SeededRNG(31)
        var core = GameCore()
        core.cash = 1_000_000
        let ownedBefore = core.instances.count
        guard let results = core.buyBoxPacks(set: 1, using: &rng) else {
            XCTFail("buyBoxPacks should return results for an unlocked, affordable box")
            return
        }
        XCTAssertEqual(results.count, Economy.boxPacks)
        XCTAssertTrue(results.allSatisfy { $0.pulled.count == Economy.packSize })
        XCTAssertTrue(results.allSatisfy { !$0.isBox })

        let totalCards = results.reduce(0) { $0 + $1.pulled.count }
        XCTAssertEqual(core.instances.count, ownedBefore + totalCards, "all box cards ingested up front")

        let ultras = results.flatMap { $0.pulled }.filter { $0.card.rarity == .ultra }.count
        let foils = results.flatMap { $0.pulled }.filter { $0.foil }.count
        XCTAssertGreaterThanOrEqual(ultras, Economy.boxGuaranteeUltras)
        XCTAssertGreaterThanOrEqual(foils, Economy.boxGuaranteeFoils)

        for k in 1..<results.count {
            XCTAssertTrue(results[k].preOwnedIds.isSuperset(of: results[k - 1].preOwnedIds),
                          "preOwnedIds should be monotonic across packs")
            let a = results[k - 1].visibleInstanceIds ?? []
            let b = results[k].visibleInstanceIds ?? []
            XCTAssertTrue(b.isSuperset(of: a) && b.count > a.count,
                          "visibleInstanceIds should strictly grow each pack")
        }
        XCTAssertEqual(results.last?.visibleInstanceIds?.count, core.instances.count,
                       "last pack should see the whole post-box collection")
    }
}
