import Foundation

// Deterministic RNG (SplitMix64) for reproducible simulation.
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

var failures = 0
func check(_ cond: Bool, _ msg: String) {
    if cond { print("  ✓ \(msg)") } else { print("  ✗ FAIL: \(msg)"); failures += 1 }
}

print("== Data integrity ==")
check(CardDatabase.all.count == 250, "250 cards loaded (CardData.swift matches Card type)")
check(Set(CardDatabase.all.map { $0.name }).count == 250, "all names unique")
check(Set(CardDatabase.all.map { $0.id }).count == 250, "all ids unique")

for s in 1...5 {
    let sc = CardDatabase.cards(inSet: s)
    let counts = Dictionary(grouping: sc, by: { $0.rarity }).mapValues { $0.count }
    check(counts[.common] == 25 && counts[.uncommon] == 15 && counts[.rare] == 7 && counts[.ultra] == 3,
          "set \(s) rarity counts 25/15/7/3")
    let order: [Rarity] = [.common, .uncommon, .rare, .ultra]
    for (lo, hi) in zip(order, order.dropFirst()) {
        let maxLo = sc.filter { $0.rarity == lo }.map { $0.baseValue }.max()!
        let minHi = sc.filter { $0.rarity == hi }.map { $0.baseValue }.min()!
        check(maxLo < minHi, "set \(s): best \(lo) (\(maxLo)) < worst \(hi) (\(minHi))")
    }
}

var evoBad = 0
for c in CardDatabase.all {
    if let t = c.evolvesToId, CardDatabase.byId[t] == nil { evoBad += 1 }
    if let f = c.evolvesFromId, CardDatabase.byId[f] == nil { evoBad += 1 }
}
check(evoBad == 0, "all evolution links resolve")
check(CardDatabase.evolutionLines.count == 65, "65 multi-stage evolution lines (5×13)")

print("\n== Pack economics (Monte Carlo) ==")
let evTargets: [Int: Double] = [1: 1.50, 2: 1.25, 3: 1.10, 4: 1.00, 5: 0.90]
for s in 1...5 {
    var rng = SeededRNG(0xC0FFEE &+ UInt64(s))
    let core = GameCore()
    let n = 40_000
    check(core.buildPack(set: s, using: &rng).count == 6, "set \(s) pack has 6 cards")
    var total = 0.0
    for _ in 0..<n { total += core.buildPack(set: s, using: &rng).reduce(0) { $0 + $1.currentValue } }
    let ev = total / Double(n)
    let ratio = ev / Economy.packPrice(set: s)
    let target = evTargets[s]!
    print(String(format: "  set %d EV $%.2f vs price $%.0f  ratio %.3f (target %.2f)", s, ev, Economy.packPrice(set: s), ratio, target))
    // realized ratio ≈ target × ~1.02 (foils); allow foil + sampling slack
    check(abs(ratio - target) < 0.06, "set \(s) pack EV ≈ \(target)× price")
}

print("\n== Grading distribution ==")
do {
    var rng = SeededRNG(42)
    var hist = [Int: Int]()
    let n = 200_000
    for _ in 0..<n { hist[Economy.rollGrade(using: &rng), default: 0] += 1 }
    let g10 = Double(hist[10]!) / Double(n) * 100
    let g8 = Double(hist[8]!) / Double(n) * 100
    let g1 = Double(hist[1]!) / Double(n) * 100
    print(String(format: "  PSA1 %.1f%% (exp 1)  PSA8 %.1f%% (exp 35)  PSA10 %.1f%% (exp 10)", g1, g8, g10))
    check(abs(g8 - 35) < 1.5 && abs(g10 - 10) < 1.5 && abs(g1 - 1) < 0.6, "grade odds match spec")
    check(Economy.gradeTable.reduce(0) { $0 + $1.odds } == 100, "grade odds sum to 100")
    check(Economy.gradeMultiplier(10) == 5 && Economy.gradeMultiplier(1) == 10 && Economy.gradeMultiplier(8) == 1,
          "grade multipliers 8=1×, 10=5×, 1=10×")
}

print("\n== Gameplay simulation ==")
do {
    var rng = SeededRNG(7)
    var core = GameCore()
    check(core.cash == 100, "starts with $100")

    var packs = 0
    var bonusCount = 0
    while core.cash >= Economy.packPrice(set: 1) && packs < 5 {
        let before = core.cash
        let r = core.buyPack(set: 1, using: &rng)
        check(r != nil, "pack \(packs + 1) purchased")
        let bonus = r!.bonuses.reduce(0) { $0 + $1.amount }
        bonusCount += r!.bonuses.count
        check(abs(core.cash - (before - 10 + bonus)) < 0.001, "cash = before − $10 + bonuses (\(r!.bonuses.count) bonus)")
        check(r!.pulled.count == 6, "pack yields 6 cards")
        packs += 1
    }
    check(core.instances.count == packs * 6, "collection grew by 6 per pack")
    print("  (bonuses paid during normal pack-buying: \(bonusCount))")

    let singletons = core.instances.filter { core.count(of: $0.cardId) == 1 }
    if let s = singletons.first {
        check(core.sell(instanceId: s.id) == nil, "cannot sell last copy of a card")
    }
    if let dup = core.sellableInstances.first {
        let before = core.cash
        let v = core.sell(instanceId: dup.id)
        check(v != nil && core.cash > before, "sold a duplicate for cash")
    }

    core.cash += 50
    if let gradeable = core.instances.first(where: { $0.card.rarity.canBeGraded && $0.grade == nil }) {
        let res = core.grade(instanceId: gradeable.id, using: &rng)
        check(res != nil && (1...10).contains(res!.grade), "graded a rare/ultra to a valid PSA grade")
    }

    var broke = GameCore()
    broke.cash = 0
    broke.instances = [CardInstance(cardId: "S1-001")]
    check(broke.isGameOver, "broke with only last-copies = game over")
    broke.instances.append(CardInstance(cardId: "S1-001"))
    check(!broke.isGameOver, "broke but holding a sellable duplicate = not over")

    // Loss threshold is the cheapest pack price ($10), NOT $0: you lose once you
    // can no longer afford even the cheapest pack and have nothing left to sell.
    check(Economy.cheapestPackPrice == 10, "cheapest pack price is $10")
    var edge = GameCore()
    edge.instances = [CardInstance(cardId: "S1-001")]   // only a last copy (unsellable)
    edge.cash = Economy.cheapestPackPrice - 0.01        // $9.99 — can't afford any pack
    check(edge.isGameOver, "cash just under cheapest pack with no sellables = game over")
    edge.cash = Economy.cheapestPackPrice               // exactly $10 — can still buy a pack
    check(!edge.isGameOver, "cash == cheapest pack price = still in the game")
}

print("\n== Win condition & bonuses ==")
do {
    var core = GameCore()
    for c in CardDatabase.all { core.instances.append(CardInstance(cardId: c.id)) }
    let events = core.checkBonuses()
    check(core.hasWon, "owning all 250 triggers win")
    check(core.claimedSets.count == 5, "all 5 sets marked complete")
    check(core.claimedEvoLines.count == 65, "all 65 evolution lines marked complete")
    check(events.count == 70, "70 bonus events (65 evo + 5 set)")
    // per set: 6 trios×2.0 + 7 duos×1.0 + 1 set×50 = 69.0 × pack price
    let expected = 69.0 * (10 + 20 + 40 + 70 + 120)
    check(abs(core.cash - (100 + expected)) < 0.01, "bonus payout exact: $\(expected)")
    let again = core.checkBonuses()
    check(again.isEmpty, "bonuses are not paid twice")
}

print("\n== Sell duplicates ==")
do {
    var core = GameCore()
    // 3x S1-001, 1x S1-002 (unique), 2x S1-003
    core.instances = [
        CardInstance(cardId: "S1-001"), CardInstance(cardId: "S1-001"), CardInstance(cardId: "S1-001"),
        CardInstance(cardId: "S1-002"),
        CardInstance(cardId: "S1-003"), CardInstance(cardId: "S1-003"),
    ]
    let ids: Set<String> = ["S1-001", "S1-002", "S1-003"]
    let preview = core.duplicateSummary(of: ids)
    check(preview.count == 3, "preview: 3 duplicate copies (2×S1-001 + 1×S1-003)")

    let startCash = core.cash
    let uniquesBefore = core.uniqueCount
    let sold = core.sellDuplicates(of: ids)
    check(sold.count == 3, "sold 3 duplicate copies")
    check(abs(sold.proceeds - preview.proceeds) < 0.001, "actual proceeds match preview")
    check(abs(core.cash - (startCash + sold.proceeds)) < 0.001, "cash increased by proceeds")
    check(core.count(of: "S1-001") == 1 && core.count(of: "S1-002") == 1 && core.count(of: "S1-003") == 1,
          "exactly one copy of each card kept")
    check(core.uniqueCount == uniquesBefore, "no unique cards lost")
    check(core.instances.count == 3, "collection reduced to the 3 kept uniques")

    // Best copy (foil) is kept, plain copies are the ones sold.
    var core2 = GameCore()
    var foilCopy = CardInstance(cardId: "S1-050"); foilCopy.foil = true
    core2.instances = [CardInstance(cardId: "S1-050"), CardInstance(cardId: "S1-050"), foilCopy]
    _ = core2.sellDuplicates(of: ["S1-050"])
    check(core2.count(of: "S1-050") == 1 && core2.instances(of: "S1-050").first?.foil == true,
          "keeps the most valuable (foil) copy when selling duplicates")
}

print("\n== Set unlocking ==")
do {
    check(Economy.uniquesToUnlock(set: 1) == 0,   "set 1 needs 0 uniques")
    check(Economy.uniquesToUnlock(set: 2) == 25,  "set 2 needs 25 uniques")
    check(Economy.uniquesToUnlock(set: 3) == 50,  "set 3 needs 50 uniques")
    check(Economy.uniquesToUnlock(set: 4) == 75,  "set 4 needs 75 uniques")
    check(Economy.uniquesToUnlock(set: 5) == 100, "set 5 needs 100 uniques")

    var rng = SeededRNG(99)
    var core = GameCore()
    core.cash = 100_000   // take affordability out of the picture
    check(core.isUnlocked(set: 1), "fresh game: set 1 unlocked")
    check(!core.isUnlocked(set: 2) && !core.isUnlocked(set: 5), "fresh game: sets 2–5 locked")

    let before = core.cash
    check(core.buyPack(set: 2, using: &rng) == nil, "cannot buy pack from a locked set")
    check(core.buyBox(set: 2, using: &rng) == nil, "cannot buy box from a locked set")
    check(core.cash == before, "locked purchase spends no cash")

    // Collect 25 uniques (all from set 1) → set 2 unlocks, set 3 still gated.
    for i in 1...25 { core.instances.append(CardInstance(cardId: String(format: "S1-%03d", i))) }
    check(core.uniqueCount == 25, "collected 25 unique cards")
    check(core.isUnlocked(set: 2), "set 2 unlocks at 25 uniques")
    check(!core.isUnlocked(set: 3), "set 3 still locked at 25 uniques (needs 50)")
    check(core.buyPack(set: 2, using: &rng) != nil, "can buy from set 2 once unlocked")
}

print("\n\(failures == 0 ? "ALL CHECKS PASSED ✅" : "\(failures) CHECK(S) FAILED ❌")")
exit(failures == 0 ? 0 : 1)
