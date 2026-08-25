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
let evTargets: [Int: Double] = [1: 1.00, 2: 0.90, 3: 0.80, 4: 0.70, 5: 0.60]
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

    // A Season busts only when the current Show is genuinely stuck — below the
    // bar with no rip, grade, or Power-Up left that could still lift holdings.
    // A bare core has no active Season, so it's never "bust".
    check(!GameCore().isBust, "a bare core with no active Season is never bust")

    var stuck = GameCore(); stuck.ensureActiveRun()
    stuck.run.ripsRemaining = 0
    stuck.cash = 0
    stuck.instances = [CardInstance(cardId: "S1-001")]   // one unsellable last copy
    check(stuck.isBust, "active Show, no rips, no cash, nothing to sell or grade = bust")

    stuck.run.ripsRemaining = 5
    stuck.cash = Economy.cheapestPackPrice
    check(!stuck.isBust, "a rip in the budget and cash for a pack = still climbing")

    // A gradeable dupe you can afford to send in is a way forward even with no rips.
    stuck.run.ripsRemaining = 0
    stuck.cash = Economy.gradeFee(set: 1)
    stuck.instances = [CardInstance(cardId: "S1-003"), CardInstance(cardId: "S1-003")]
    check(!stuck.isBust, "a gradeable dupe you can afford to grade = a way out")

    // Energy plus a Power-Up in hand is also a move.
    var pu = GameCore(); pu.ensureActiveRun()
    pu.run.ripsRemaining = 0; pu.cash = 0
    pu.instances = [CardInstance(cardId: "S1-001")]
    pu.run.energy = 2; pu.run.powerUpIds = ["market-tip"]
    check(!pu.isBust, "a Power-Up you have the Energy to play = not bust")

    // Reaching the bar is never a loss — you can Make the Cut instead.
    var atBar = GameCore(); atBar.ensureActiveRun()
    atBar.run.ripsRemaining = 0
    atBar.cash = atBar.currentQuota
    check(!atBar.isBust && atBar.canMakeCut, "holdings at the Show bar = Make the Cut, not bust")

    // The between-Show Bazaar is never bust (there's always the next Show).
    atBar.cash = 0; atBar.run.atBazaar = true
    check(!atBar.isBust, "the between-Show Bazaar is never flagged bust")

    check(Economy.cheapestPackPrice == 10, "cheapest pack price is $10")

    // Only genuine extras count: with three copies, two can go and one must stay.
    var extras = GameCore()
    extras.cash = 0
    extras.instances = Array(repeating: CardInstance(cardId: "S1-001"), count: 3)
    check(extras.sellableExtras.count == 2, "3 copies = 2 sellable extras")
    check(abs(extras.maxRaisableCash - 2 * extras.instances[0].sellValue) < 0.001,
          "raisable cash counts each extra exactly once")
}

print("\n== Bonuses (evolution only; sets no longer pay cash) ==")
do {
    var core = GameCore()
    for c in CardDatabase.all { core.instances.append(CardInstance(cardId: c.id)) }
    let events = core.checkBonuses()
    check(!core.hasWon, "owning all 250 no longer 'wins' — that's the Championship's job now")
    check(core.claimedSets.count == 5, "all 5 sets still recorded complete (for the Set Master milestone)")
    check(core.claimedEvoLines.count == 65, "all 65 evolution lines marked complete")
    check(events.count == 65, "65 bonus events — evolution lines only, no set-completion payouts")
    check(events.allSatisfy { $0.kind == .evolution }, "every bonus paid is an evolution bonus")
    // per set: 6 trios×0.5 + 7 duos×0.25 = 4.75 × pack price (the +15× set bonus is gone)
    let expected = 4.75 * (10.0 + 30 + 75 + 160 + 400)
    check(abs(core.cash - (100 + expected)) < 0.01, "evolution payout exact: $\(expected)")
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

print("\n== Pre-owned snapshot (new-card flag) ==")
do {
    var rng = SeededRNG(7)
    var core = GameCore()
    core.cash = 100_000
    let r1 = core.buyPack(set: 1, using: &rng)
    check(r1?.preOwnedIds.isEmpty == true, "first pack: nothing pre-owned")
    let ownedAfter1 = core.uniqueOwnedIds
    let r2 = core.buyPack(set: 1, using: &rng)
    check(r2?.preOwnedIds == ownedAfter1, "second pack: preOwnedIds = uniques owned before it")
    let newInFirst = Set(r1!.pulled.map { $0.cardId }).subtracting(r1!.preOwnedIds)
    check(!newInFirst.isEmpty, "first pack yields at least one brand-new card")
    // A box snapshots pre-owned ids too.
    let rb = core.buyBox(set: 1, using: &rng)
    check(rb?.preOwnedIds.contains(where: { ownedAfter1.contains($0) }) == true,
          "box also records pre-owned ids")
}

print("\n== Booster box mechanics (off the shelf, still supported by the model) ==")
do {
    var rng = SeededRNG(31)
    var core = GameCore()
    core.cash = 1_000_000
    let ownedBefore = core.instances.count
    guard let results = core.buyBoxPacks(set: 1, using: &rng) else {
        check(false, "buyBoxPacks returns results for an unlocked, affordable box"); fatalError()
    }
    check(results.count == Economy.boxPacks, "box yields \(Economy.boxPacks) packs")
    check(results.allSatisfy { $0.pulled.count == Economy.packSize }, "each pack has \(Economy.packSize) cards")
    check(results.allSatisfy { !$0.isBox }, "box packs render as single-pack summaries")

    let totalCards = results.reduce(0) { $0 + $1.pulled.count }
    check(core.instances.count == ownedBefore + totalCards, "all box cards ingested up front (crash-safe)")

    let ultras = results.flatMap { $0.pulled }.filter { $0.card.rarity == .ultra }.count
    let foils  = results.flatMap { $0.pulled }.filter { $0.foil }.count
    check(ultras >= Economy.boxGuaranteeUltras, "box meets ultra guarantee (\(ultras) ≥ \(Economy.boxGuaranteeUltras))")
    check(foils  >= Economy.boxGuaranteeFoils,  "box meets foil guarantee (\(foils) ≥ \(Economy.boxGuaranteeFoils))")

    // preOwnedIds grows monotonically pack-to-pack; visibleInstanceIds strictly grows.
    var preOK = true, visOK = true
    for k in 1..<results.count {
        if !results[k].preOwnedIds.isSuperset(of: results[k-1].preOwnedIds) { preOK = false }
        let a = results[k-1].visibleInstanceIds ?? []
        let b = results[k].visibleInstanceIds ?? []
        if !(b.isSuperset(of: a) && b.count > a.count) { visOK = false }
    }
    check(preOK, "preOwnedIds is monotonic across packs")
    check(visOK, "visibleInstanceIds grows each pack (pack-by-pack duplicate scope)")
    check(results.last?.visibleInstanceIds?.count == core.instances.count,
          "last pack sees the whole post-box collection")
}

print("\n== Save format & load hygiene ==")
do {
    // A save written before a field existed must still decode. Simulate one by
    // encoding a payload that omits every optional-ish key.
    let legacy = Data(#"{"cash":42.5,"instances":[],"claimedEvoLines":[],"claimedSets":[],"stats":{},"hasWon":false}"#.utf8)
    let old = try? JSONDecoder().decode(GameCore.self, from: legacy)
    check(old != nil, "a save missing newer keys still decodes")
    check(old?.cash == 42.5, "existing values survive a lenient decode")
    check(old?.winAcknowledged == false && old?.welcomeSeen == false,
          "missing keys fall back to defaults instead of throwing")

    // A save missing *every* key must not throw either — that's what makes
    // additive schema changes safe forever.
    let empty = try? JSONDecoder().decode(GameCore.self, from: Data("{}".utf8))
    check(empty != nil && empty?.cash == Economy.startingCash,
          "an empty payload decodes to a default game")

    // Envelope round-trip carries the version tag.
    var core = GameCore()
    core.cash = 777
    let encoded = try! JSONEncoder().encode(SaveFile(core: core))
    let round = try? JSONDecoder().decode(SaveFile.self, from: encoded)
    check(round?.schemaVersion == SaveFile.currentVersion, "save records its schema version")
    check(round?.core.cash == 777, "save round-trips the game state")

    // Owned copies decode leniently too — only `cardId` is required, so a future
    // per-copy field (serial number, acquired date, …) can't invalidate old saves.
    let sparse = Data(#"{"instances":[{"cardId":"S1-001"}]}"#.utf8)
    let sparseCore = try? JSONDecoder().decode(GameCore.self, from: sparse)
    check(sparseCore?.instances.count == 1, "a card copy with only a cardId still decodes")
    check(sparseCore?.instances.first?.foil == false && sparseCore?.instances.first?.grade == nil,
          "missing per-copy keys fall back to defaults")
    check(sparseCore?.instances.first?.cardId == "S1-001", "the required cardId survives")

    // Retired/renamed card ids are dropped rather than crashing on access.
    var stale = GameCore()
    stale.instances = [CardInstance(cardId: "S1-001"), CardInstance(cardId: "S9-999")]
    let ghost = stale.instances[1]
    check(ghost.card.id == "S9-999" && ghost.currentValue == 0,
          "an unknown card id resolves to a worthless placeholder, not a crash")
    let (clean, dropped) = stale.sanitized()
    check(dropped == 1 && clean.instances.count == 1 && clean.instances[0].cardId == "S1-001",
          "sanitize drops instances whose card left the catalogue")
    check(GameCore().sanitized().droppedInstances == 0, "sanitize is a no-op on a valid save")

    // Dropping cards must also un-claim bonuses the player no longer qualifies for.
    var claimed = GameCore()
    for c in CardDatabase.cards(inSet: 1) { claimed.instances.append(CardInstance(cardId: c.id)) }
    _ = claimed.checkBonuses()
    check(claimed.claimedSets.contains(1), "set 1 claimed while complete")
    claimed.instances.append(CardInstance(cardId: "S9-999"))
    claimed.instances.removeAll { $0.cardId == "S1-001" }
    check(!claimed.sanitized().core.claimedSets.contains(1),
          "a set that is no longer complete after sanitizing is un-claimed")
}

print("\n== Lifetime stats (run vs. all-time) ==")
do {
    // Folding a lost run: sums add, maxes take the larger value, runsWon
    // stays put, bestRunPacks stays nil (never won).
    var run = Stats()
    run.packsOpened = 10
    run.moneyEarned = 50
    run.peakCash = 500
    let afterLoss = LifetimeStats().folding(run, won: false)
    check(afterLoss.runsStarted == 1 && afterLoss.runsWon == 0,
          "folding a lost run counts it as started but not won")
    check(afterLoss.packsOpened == 10 && afterLoss.moneyEarned == 50,
          "folding a run sums its counters into lifetime")
    check(afterLoss.peakCash == 500, "folding a run raises lifetime peaks to the run's peak")
    check(afterLoss.bestRunPacks == nil, "a lost run never sets bestRunPacks")

    // Folding a won run: runsWon increments, bestRunPacks records the pack count.
    var won = Stats(); won.packsOpened = 7
    let afterWin = LifetimeStats().folding(won, won: true)
    check(afterWin.runsWon == 1 && afterWin.bestRunPacks == 7,
          "folding a won run increments runsWon and records bestRunPacks")

    // bestRunPacks only ever shrinks toward the fewest packs across won runs.
    var secondWin = Stats(); secondWin.packsOpened = 3
    let afterSecondWin = afterWin.folding(secondWin, won: true)
    check(afterSecondWin.bestRunPacks == 3, "bestRunPacks tracks the fewest packs across won runs")
    var thirdWin = Stats(); thirdWin.packsOpened = 20
    let afterThirdWin = afterSecondWin.folding(thirdWin, won: true)
    check(afterThirdWin.bestRunPacks == 3, "a worse winning run does not raise bestRunPacks")

    // Sums accumulate across multiple folds (simulating several completed runs).
    var runA = Stats(); runA.cardsSold = 4
    var runB = Stats(); runB.cardsSold = 6
    let twoRuns = LifetimeStats().folding(runA, won: false).folding(runB, won: true)
    check(twoRuns.cardsSold == 10 && twoRuns.runsStarted == 2 && twoRuns.runsWon == 1,
          "folding two runs accumulates sums and run counters correctly")

    // Display-time totals = stored lifetime + current run, without mutating
    // stored lifetime — so a reset can't double-count it.
    var core = GameCore()
    core.stats.packsOpened = 5
    core.stats.moneyEarned = 40
    let display = core.lifetimeIncludingCurrentRun
    check(display.runsStarted == 1 && display.packsOpened == 5,
          "an in-progress run is folded into all-time totals for display")
    check(core.lifetime.runsStarted == 0, "display-time folding never mutates stored lifetime")

    // startingNewRun() permanently commits the finished run and resets the rest.
    var finished = GameCore()
    finished.cash = 999
    finished.stats.packsOpened = 12
    finished.hasWon = true
    let next = finished.startingNewRun()
    check(next.lifetime.runsStarted == 1 && next.lifetime.runsWon == 1,
          "startingNewRun folds the just-finished (won) run into lifetime")
    check(next.lifetime.packsOpened == 12, "startingNewRun carries the finished run's totals into lifetime")
    check(next.cash == Economy.startingCash && next.stats.packsOpened == 0,
          "startingNewRun resets cash and the current run's stats")
    check(next.lifetimeIncludingCurrentRun.runsStarted == 2,
          "all-time display after a reset counts the completed run plus the freshly started one")

    // LifetimeStats decodes leniently: missing keys fall back to defaults,
    // exactly like Stats and GameCore.
    let emptyLifetime = try? JSONDecoder().decode(LifetimeStats.self, from: Data("{}".utf8))
    check(emptyLifetime != nil && emptyLifetime?.runsStarted == 0 && emptyLifetime?.bestRunPacks == nil,
          "a LifetimeStats payload missing every key decodes to defaults")
}

print("\n== Save store (files) ==")
do {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tu_verify_\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let store = SaveStore(directory: dir)
    check(store.load().core == nil && store.load().issue == nil,
          "no save file yet = fresh game, no issue reported")

    var core = GameCore()
    core.cash = 321
    core.hasWon = true
    core.acknowledgeWin()
    check(store.save(core), "save writes to disk")
    let reloaded = store.load()
    check(reloaded.core?.cash == 321, "reload restores cash")
    check(reloaded.core?.winAcknowledged == true, "reload restores win acknowledgement")
    check(reloaded.issue == nil, "a healthy save reports no issue")

    // Pre-envelope saves (a bare GameCore) still load.
    var legacyCore = GameCore(); legacyCore.cash = 55
    try! JSONEncoder().encode(legacyCore).write(to: store.url)
    check(store.load().core?.cash == 55, "a pre-envelope (bare GameCore) save still loads")

    // A save referencing a retired card loads, cleaned, and says so.
    var stale = GameCore()
    stale.instances = [CardInstance(cardId: "S1-001"), CardInstance(cardId: "S9-999")]
    _ = store.save(stale)
    let cleaned = store.load()
    check(cleaned.core?.instances.count == 1, "retired cards are stripped on load")
    check(cleaned.issue == .droppedUnknownCards(count: 1), "the player is told cards were removed")

    // An undecodable save must be preserved, not deleted.
    try! Data("not json at all".utf8).write(to: store.url)
    let broken = store.load()
    check(broken.core == nil, "an unreadable save falls back to a fresh game")
    var quarantinedName: String? = nil
    if case .unreadable(let name) = broken.issue { quarantinedName = name }
    check(quarantinedName != nil, "an unreadable save reports where it was moved")
    let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
    check(leftovers.contains { $0.hasPrefix("tradingup_save.corrupt-") },
          "the unreadable save is quarantined on disk, never deleted")
    check(!FileManager.default.fileExists(atPath: store.url.path),
          "the bad file is moved aside so the next save starts clean")

    // A v1 envelope (no `lifetime` key at all) migrates to v2 cleanly: no data
    // is lost, and the missing lifetime defaults to zero — the player's
    // in-progress run is folded in at display time instead.
    let v1Save = """
    {"schemaVersion":1,"core":{"cash":250,"instances":[{"cardId":"S1-001"}],\
    "claimedEvoLines":[],"claimedSets":[],"stats":{"packsOpened":9,"moneyEarned":30},"hasWon":false}}
    """
    try! Data(v1Save.utf8).write(to: store.url)
    let migrated = store.load()
    check(migrated.core?.cash == 250, "a v1 save migrates without losing cash")
    check(migrated.core?.stats.packsOpened == 9, "a v1 save migrates without losing current-run stats")
    check(migrated.core?.instances.count == 1, "a v1 save migrates without losing the collection")
    check(migrated.core?.lifetime.runsStarted == 0, "a v1 save's stored lifetime defaults to zero")
    check(migrated.core?.lifetimeIncludingCurrentRun.packsOpened == 9,
          "a v1 save's all-time display still reflects the in-progress run's stats immediately")

    // A bare pre-envelope save (no schemaVersion, no lifetime) also loads cleanly.
    let bare = try! JSONEncoder().encode(GameCore())
    try! bare.write(to: store.url)
    check(store.load().core?.lifetime.runsStarted == 0,
          "a bare pre-envelope save also decodes lifetime to defaults")

    // A save from a *newer* schema version than this build knows about must
    // not be absorbed by the lenient decode — that would silently drop
    // whatever fields the future version added, and the next autosave would
    // make that loss permanent. It must be quarantined instead, like an
    // unreadable file, with the original bytes fully recoverable.
    let futureSave = """
    {"schemaVersion":99,"core":{"cash":777,"instances":[{"cardId":"S1-001"}],\
    "claimedEvoLines":[],"claimedSets":[],"stats":{},"hasWon":false,"futureField":"do not drop me"}}
    """
    try! Data(futureSave.utf8).write(to: store.url)
    let futureLoaded = store.load()
    check(futureLoaded.core == nil, "a save from a newer schema version does not load at all")
    var futureQuarantinedName: String? = nil
    if case .fromNewerVersion(let name) = futureLoaded.issue { futureQuarantinedName = name }
    check(futureQuarantinedName != nil, "the player is told this save needs a newer app version")
    let laterLeftovers = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
    check(laterLeftovers.contains { $0.hasPrefix("tradingup_save.corrupt-") },
          "a newer-schema save is quarantined on disk, never deleted")
    check(!FileManager.default.fileExists(atPath: store.url.path),
          "the newer-schema file is moved aside so it isn't overwritten")
    if let name = futureQuarantinedName {
        let quarantinedURL = dir.appendingPathComponent(name)
        let recovered = try? String(contentsOf: quarantinedURL, encoding: .utf8)
        check(recovered == futureSave, "the quarantined file is byte-for-byte the original newer-schema save")
        _ = store.save(GameCore())
        let stillRecovered = try? String(contentsOf: quarantinedURL, encoding: .utf8)
        check(stillRecovered == futureSave, "a later save does not overwrite the quarantined newer-schema file")
    }
}

print("\n== Win presentation (Season Champion) ==")
do {
    var core = GameCore()
    core.ensureActiveRun()
    core.run.show = Economy.seasonShows        // the Championship
    core.cash = core.currentQuota              // holdings meet the bar
    check(core.canMakeCut, "at the Championship with holdings at the bar, you can Make the Cut")
    let fired = core.makeCut()
    check(core.hasWon && core.shouldShowWin, "clearing the Championship wins the Season and shows the overlay")
    check(fired.contains { $0.milestone == .seasonChampion }, "winning fires the Season Champion milestone")
    core.acknowledgeWin()
    check(core.hasWon && !core.shouldShowWin,
          "dismissing the win keeps the run instead of forcing a reset")
    check(!core.isGameOver, "a won Season is never also flagged bust")
    check(GameCore().winAcknowledged == false, "a new game starts with the win un-acknowledged")
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

print("\n== Economy knobs (tempo & risk) ==")
do {
    check(Economy.packPrices == [10, 30, 75, 160, 400], "steeper pack prices [10,30,75,160,400]")
    check(Economy.gradeFees == [2, 4, 6, 8, 10], "flat grade-fee ramp [2,4,6,8,10]")
    check(abs(Economy.sellbackRate - 0.75) < 1e-9, "shop buys dupes at 75% of market")
    var boxesOK = true
    for s in 1...5 {
        if abs(Economy.boxPrice(set: s) - Economy.packPrice(set: s) * 11) > 1e-9 { boxesOK = false }
    }
    check(boxesOK, "booster box = 11× pack price (trimmed the free-pack ATM discount)")
    // Cheap, flat grade fees make grading high sets attractive, but grading stays a
    // gamble: low PSA grades multiply value *down*, so a graded card can be worth less.
    check(Economy.gradeMultiplier(2) < 1 && Economy.gradeMultiplier(7) < 1,
          "low PSA grades (2–7) reduce value — grading keeps real downside")
}

print("\n== Sell-back spread ==")
do {
    var foil = CardInstance(cardId: "S1-050"); foil.foil = true
    check(abs(foil.sellValue - Economy.sellback(foil.currentValue)) < 1e-9, "sellValue = sellback(currentValue)")
    check(foil.sellValue < foil.currentValue, "shop pays less than market value (a real spread)")

    var core = GameCore()
    core.instances = [CardInstance(cardId: "S1-001"), CardInstance(cardId: "S1-001")]
    let market = core.instances[1].currentValue
    let before = core.cash
    let got = core.sell(instanceId: core.instances[1].id)
    check(got != nil && abs(got! - Economy.sellback(market)) < 1e-9, "a dupe sells for 75% of its market value")
    check(abs(core.cash - (before + Economy.sellback(market))) < 1e-9, "cash rises by the discounted proceeds")

    // Buying into an already-completed set and dumping every dupe returns less than you
    // paid: churning is now net-negative — the core source of losing risk.
    var rng = SeededRNG(123)
    var churn = GameCore(); churn.cash = 500
    for c in CardDatabase.cards(inSet: 1) { churn.instances.append(CardInstance(cardId: c.id)) }
    _ = churn.checkBonuses()                       // claim set-1 bonuses up front
    let cashBefore = churn.cash
    _ = churn.buyPack(set: 1, using: &rng)         // −$10
    _ = churn.sellDuplicates(of: churn.uniqueOwnedIds)
    check(churn.cash < cashBefore,
          String(format: "churn a pack into a full set = net loss (%+.2f)", churn.cash - cashBefore))
}

print("\n== The Circuit: run-structure knobs ==")
do {
    // The net-worth bar is a strictly rising ladder across all 8 Shows.
    let quotas = (1...Economy.seasonShows).map { Economy.quota(show: $0) }
    check(quotas.count == 8, "a Season is 8 Shows")
    var rising = true
    for i in 1..<quotas.count where !(quotas[i] > quotas[i - 1]) { rising = false }
    check(rising, "the net-worth bar rises every Show (\(quotas.map { Int($0) }))")
    check(quotas.first! >= Economy.startingCash * 0.8,
          "Show 1's bar is within reach of the starting stake")
    check(quotas.last! > quotas.first! * 1.5,
          "the Championship bar is meaningfully higher than the opener")

    // The rip budget is always a positive, finite clock; upgrades only add to it.
    check(Economy.baseRipsPerShow >= 1, "every Show grants at least one rip")
    check(Economy.ripsPerShow(bonus: 3) == Economy.baseRipsPerShow + 3, "rip bonuses add on top")

    // Energy is a small, bounded pool.
    check(Economy.startingEnergy >= 1 && Economy.startingEnergy <= Economy.baseMaxEnergy,
          "starting Energy sits within the ceiling")

    // Guild ladders are capped and cost strictly more each level.
    for u in GuildUpgrade.allCases {
        let maxLvl = Economy.guildMaxLevel(u)
        check(maxLvl >= 1, "\(u.name) has at least one level")
        let costs = (0..<maxLvl).map { Economy.guildCost(u, currentLevel: $0) }
        var monotone = true
        for i in 1..<costs.count where !(costs[i] > costs[i - 1]) { monotone = false }
        check(monotone, "\(u.name) Renown cost rises each level (\(costs))")
    }

    // A bigger Stake means a bigger opening bankroll; an un-upgraded Season is classic.
    check(Economy.startingStake(stakeLevel: 2) > Economy.startingStake(stakeLevel: 0),
          "the Stake upgrade raises the starting bankroll")
    check(Economy.startingStake(stakeLevel: 0) == Economy.startingCash,
          "an un-upgraded Season starts at the classic bankroll")

    // The Market Tip Power-Up's payout scales with the Show it's played in.
    check(Economy.marketTipCash(show: 5) > Economy.marketTipCash(show: 1),
          "Market Tip pays more in later Shows")
}

print("\n== BoostCatalog: content integrity ==")
do {
    let trainerIds = BoostCatalog.trainers.map { $0.id }
    let powerUpIds = BoostCatalog.powerUps.map { $0.id }
    let energyIds  = BoostCatalog.energyCards.map { $0.id }
    let allIds = trainerIds + powerUpIds + energyIds
    check(Set(allIds).count == allIds.count, "every boost id is unique across Trainers/Power-Ups/Energy")
    check(allIds.allSatisfy { BoostCatalog.boost($0) != nil }, "every boost id round-trips through the catalog")

    // Every `requires` gate points at a real milestone id.
    let milestoneIds = Set(Milestone.allCases.map { $0.rawValue })
    let gates = BoostCatalog.trainers.compactMap { $0.requires }
        + BoostCatalog.powerUps.compactMap { $0.requires }
        + BoostCatalog.energyCards.compactMap { $0.requires }
    check(!gates.isEmpty, "some boosts are gated behind milestones (there's something to unlock)")
    check(gates.allSatisfy { milestoneIds.contains($0) },
          "every boost unlock gate references a real milestone")

    // The opening pool (no milestones, no Trainers held) is non-empty and ungated,
    // so a first-time player always has offers.
    let starter = BoostCatalog.availablePool(unlocked: [], ownedTrainerIds: [])
    check(!starter.isEmpty, "the opening pool is never empty")
    check(starter.allSatisfy { $0.requires == nil }, "nothing gated leaks into the opening pool")

    // Unlocking milestones widens the pool; a Trainer already held drops out.
    let widened = BoostCatalog.availablePool(unlocked: milestoneIds, ownedTrainerIds: [])
    check(widened.count > starter.count, "unlocking milestones adds gated boosts to the pool")
    let heldOne = BoostCatalog.availablePool(unlocked: [], ownedTrainerIds: [trainerIds[0]])
    check(!heldOne.contains { $0.id == trainerIds[0] }, "a Trainer already held stops being offered")

    // Twists are well-formed and uniquely identified.
    let twistIds = BoostCatalog.twists.map { $0.id }
    check(Set(twistIds).count == twistIds.count, "every Twist id is unique")
    check(BoostCatalog.twists.allSatisfy { $0.quotaMultiplier > 0 }, "no Twist zeroes the bar")

    // Guild upgrades enumerate cleanly.
    check(Set(GuildUpgrade.allCases.map { $0.id }).count == GuildUpgrade.allCases.count,
          "every Guild upgrade id is unique")
}

print("\n== Milestones: unlock conditions ==")
do {
    func fresh() -> GameCore { var c = GameCore(); c.ensureActiveRun(); return c }
    let cid = CardDatabase.all[0].id

    // firstCut: satisfied once a Show has been cleared (Show advanced past 1).
    var c = fresh()
    check(!c.satisfies(.firstCut), "First Cut isn't met at Show 1")
    c.run.show = 2
    check(c.satisfies(.firstCut), "First Cut fires after clearing a Show")

    // setMaster: any completed set recorded this run.
    c = fresh()
    check(!c.satisfies(.setMaster), "Set Master needs a completed set")
    c.claimedSets = [1]
    check(c.satisfies(.setMaster), "Set Master fires on a completed set")

    // hoarder: 8 copies of a single card.
    c = fresh()
    for _ in 0..<7 { c.instances.append(CardInstance(cardId: cid)) }
    check(!c.satisfies(.hoarder), "Hoarder needs 8 copies (7 isn't enough)")
    c.instances.append(CardInstance(cardId: cid))
    check(c.satisfies(.hoarder), "Hoarder fires at 8 copies")

    // gemHolo: a foil graded PSA 10.
    c = fresh()
    c.instances.append(CardInstance(cardId: cid, foil: true, grade: 9))
    check(!c.satisfies(.gemHolo), "Gem Holo needs a PSA 10 foil (PSA 9 doesn't count)")
    c.instances.append(CardInstance(cardId: cid, foil: true, grade: 10))
    check(c.satisfies(.gemHolo), "Gem Holo fires on a PSA 10 foil")

    // aceGrader: three cards graded PSA 9+.
    c = fresh()
    c.instances.append(CardInstance(cardId: cid, grade: 9))
    c.instances.append(CardInstance(cardId: cid, grade: 10))
    check(!c.satisfies(.aceGrader), "Ace Grader needs three PSA 9+ (two isn't enough)")
    c.instances.append(CardInstance(cardId: cid, grade: 9))
    check(c.satisfies(.aceGrader), "Ace Grader fires on the third PSA 9+")

    // deepRun: reach Show 5.
    c = fresh(); c.run.show = 4
    check(!c.satisfies(.deepRun), "Deep Run isn't met at Show 4")
    c.run.show = 5
    check(c.satisfies(.deepRun), "Deep Run fires at Show 5")

    // seasonChampion: winning the Season.
    c = fresh()
    check(!c.satisfies(.seasonChampion), "Season Champion needs a win")
    c.hasWon = true
    check(c.satisfies(.seasonChampion), "Season Champion fires on a win")

    // ultraHunter: 10 ultras pulled all-time (current run folded into lifetime).
    c = fresh(); c.stats.ultrasPulled = 9
    check(!c.satisfies(.ultraHunter), "Ultra Hunter needs 10 ultras (9 isn't enough)")
    c.stats.ultrasPulled = 10
    check(c.satisfies(.ultraHunter), "Ultra Hunter fires at 10 ultras")

    // centurion / masterCollector: unique-count gates.
    c = fresh()
    for card in CardDatabase.all.prefix(99) { c.instances.append(CardInstance(cardId: card.id)) }
    check(!c.satisfies(.centurion), "Centurion needs 100 uniques (99 isn't enough)")
    c.instances.append(CardInstance(cardId: CardDatabase.all[99].id))
    check(c.satisfies(.centurion), "Centurion fires at 100 uniques")
    check(!c.satisfies(.masterCollector), "Master Collector needs all 250")
    for card in CardDatabase.all where !c.owns(card.id) { c.instances.append(CardInstance(cardId: card.id)) }
    check(c.satisfies(.masterCollector), "Master Collector fires at the full 250")

    // refreshMilestones banks Renown once and never re-fires.
    c = fresh(); c.run.show = 2
    let before = c.meta.renown
    let fired = c.refreshMilestones()
    check(fired.contains { $0.milestone == .firstCut }, "refreshMilestones surfaces a newly-met milestone")
    check(c.meta.renown == before + Milestone.firstCut.renown, "the milestone's Renown is banked")
    let again = c.refreshMilestones()
    check(!again.contains { $0.milestone == .firstCut }, "a milestone never fires twice")
}

print("\n== The Circuit: run-loop mechanics ==")
do {
    var rng = SeededRNG(0x0C1E)
    var c = GameCore()
    c.ensureActiveRun()
    check(c.run.active, "ensureActiveRun activates a Season")
    check(c.run.show == 1, "a fresh Season opens at Show 1")

    // Entering a Show refills the rip clock and the Energy pool.
    c.enterShow(twistId: nil)
    check(c.run.ripsRemaining == Economy.ripsPerShow(), "entering a Show refills the rip clock")
    check(c.run.energy == min(c.run.maxEnergy, Economy.startingEnergy), "entering a Show refills Energy")

    // Ripping consumes exactly one rip and lands cards in the collection.
    let ripsBefore = c.run.ripsRemaining
    let ownedBefore = c.instances.count
    let res = c.ripPack(set: 1, using: &rng)
    check(res != nil, "ripping the base set succeeds")
    check(c.run.ripsRemaining == ripsBefore - 1, "a rip is consumed")
    check(c.instances.count > ownedBefore, "the pull lands in the collection")

    // Making the Cut over the bar advances the Show and opens the Bazaar.
    var winner = GameCore(); winner.ensureActiveRun(); winner.enterShow(twistId: nil)
    winner.cash = Economy.quota(show: 1) + 1_000     // trivially over the bar
    check(winner.canMakeCut, "over the bar, the Cut is available")
    let fired = winner.makeCut()
    check(winner.run.show == 2, "clearing a non-final Show advances to the next")
    check(winner.run.atBazaar, "clearing a Show opens the Bazaar")
    check(fired.contains { $0.milestone == .firstCut }, "the first Cut fires First Cut")
    check(winner.meta.renown >= Economy.renownPerShowCleared, "clearing a Show banks Renown")

    // Clearing the Championship wins the Season.
    var champ = GameCore(); champ.ensureActiveRun()
    champ.run.show = Economy.seasonShows
    champ.enterShow(twistId: nil)
    champ.cash = Economy.quota(show: Economy.seasonShows) + 10_000
    check(champ.canMakeCut, "the Championship Cut is available over the bar")
    _ = champ.makeCut()
    check(champ.hasWon, "clearing the final Show wins the Season")
    check(champ.satisfies(.seasonChampion), "winning satisfies Season Champion")

    // Busting: no rips, no cash, under the bar, nothing to play → isBust.
    var bust = GameCore(); bust.ensureActiveRun(); bust.enterShow(twistId: nil)
    bust.run.ripsRemaining = 0
    bust.cash = 0
    check(bust.netWorth < bust.currentQuota, "under the bar with nothing to spend")
    check(bust.isBust, "a stalled Show with no forward move is a bust")
    check(bust.isGameOver, "isGameOver mirrors isBust")
}

// Play a full Season on the Circuit with a fixed strategy. Both styles climb the
// same way — rip packs toward the Show's net-worth bar, Make the Cut when they
// reach it, advance Show to Show until the Championship or a bust. The only
// difference is how they treat what they pull:
//   .thoughtful keeps its collection and *grades* what it can afford (grading is
//     +EV on the flat fee, so it lifts net worth), selling only cheap commons for
//     the liquidity to keep ripping.
//   .reckless dumps every duplicate raw at the 75% buylist and never grades, so
//     it bleeds net worth on the spread and stalls below the rising bar.
// Net worth carries Show to Show (the collection persists), so a good climb
// compounds. Crude proxies, but they bracket careless vs. considered play.
enum Style { case reckless, thoughtful }

func playSeason(seed: UInt64, style: Style) -> (showsCleared: Int, won: Bool, netAtEnd: Double) {
    var rng = SeededRNG(seed)
    var core = GameCore()
    core.ensureActiveRun()

    func highestAffordableSet() -> Int? {
        (1...CardDatabase.setCount)
            .filter { core.isUnlocked(set: $0) && core.cash >= Economy.packPrice(set: $0) }
            .last
    }

    for _ in 0..<100_000 {
        if core.hasWon { return (Economy.seasonShows, true, core.netWorth) }

        if core.run.atBazaar {
            // A free draft pick is pure upside; thoughtful grabs the first offer.
            if style == .thoughtful, let pick = core.run.draftIds.first { _ = core.takeDraft(pick) }
            core.enterShow(twistId: nil)
            continue
        }

        if core.canMakeCut {
            _ = core.makeCut()
            if core.run.atBazaar {           // GameState does this in the app; the harness owns rng here
                core.rollDraft(using: &rng)
                core.rollBazaar(using: &rng)
            }
            continue
        }

        // Value actions for the style.
        if style == .thoughtful {
            for cardId in core.uniqueOwnedIds {
                for inst in core.instances(of: cardId)
                where inst.grade == nil && inst.card.rarity.canBeGraded
                    && core.cash >= Economy.gradeFee(set: inst.card.set) {
                    _ = core.grade(instanceId: inst.id, using: &rng)
                }
            }
        } else {
            _ = core.sellDuplicates(of: core.uniqueOwnedIds)   // dump everything raw
        }

        if core.canMakeCut { continue }

        // Rip toward the bar: the priciest set affordable (bigger cards climb
        // faster), falling back to the cheapest unlocked set.
        let target = highestAffordableSet() ?? 1
        if core.firstPackFreeAvailable
            || (core.run.ripsRemaining > 0 && core.cash >= Economy.packPrice(set: target)) {
            if core.ripPack(set: target, using: &rng) != nil { continue }
        }

        // Can't afford the target but rips remain — thoughtful sells its cheapest
        // *commons* for just enough liquidity to keep ripping the base set.
        if style == .thoughtful, core.run.ripsRemaining > 0,
           core.cash < Economy.packPrice(set: 1) {
            let commons = core.sellableExtras
                .filter { $0.card.rarity == .common }
                .sorted { core.sellPrice(of: $0) < core.sellPrice(of: $1) }
            var sold = false
            for c in commons where core.cash < Economy.packPrice(set: 1) {
                _ = core.sell(instanceId: c.id); sold = true
            }
            if sold, core.cash >= Economy.packPrice(set: 1) {
                _ = core.ripPack(set: 1, using: &rng); continue
            }
        }

        // No move left this Show: the climb stalls below the bar.
        break
    }
    // Cleared everything up to (but not including) the current Show.
    return (core.run.show - 1, core.hasWon, core.netWorth)
}

print("\n== Circuit: Season simulations (risk & skill) ==")
do {
    let n = 200
    var recklessCleared = 0, thoughtfulCleared = 0
    var recklessWins = 0, thoughtfulWins = 0
    var recklessBustShow1 = 0
    for (style, isThoughtful) in [(Style.reckless, false), (Style.thoughtful, true)] {
        var clearedTotal = 0, wins = 0, bustShow1 = 0
        var hist = [Int: Int]()
        for s in 0..<n {
            let r = playSeason(seed: 0xA11CE &+ UInt64(s), style: style)
            clearedTotal += r.showsCleared
            hist[r.showsCleared, default: 0] += 1
            if r.won { wins += 1 }
            if r.showsCleared == 0 { bustShow1 += 1 }
        }
        let avg = Double(clearedTotal) / Double(n)
        let label = isThoughtful ? "Thoughtful (keep + grade)" : "Reckless (dump raw)"
        let dist = (0...Economy.seasonShows).map { "\($0):\(hist[$0] ?? 0)" }.joined(separator: " ")
        print(String(format: "  %@: avg shows cleared %.2f, wins %d/%d", label, avg, wins, n))
        print("    cleared-distribution [\(dist)]")
        if isThoughtful { thoughtfulCleared = clearedTotal; thoughtfulWins = wins }
        else { recklessCleared = clearedTotal; recklessWins = wins; recklessBustShow1 = bustShow1 }
    }
    let recklessAvg = Double(recklessCleared) / Double(n)
    let thoughtfulAvg = Double(thoughtfulCleared) / Double(n)
    let thoughtfulWinRate = Double(thoughtfulWins) / Double(n)
    let recklessBustRate = Double(recklessBustShow1) / Double(n)

    // (1) Skill gap: considered play (keep + grade) climbs meaningfully further than
    // careless play (dump everything raw). This is the invariant that makes the
    // Circuit a game of decisions, not just a slot machine. Measured gap ≈ 1.4 Shows;
    // assert ≥ 1.0 for slack against model drift.
    check(thoughtfulAvg >= recklessAvg + 1.0,
          String(format: "grading + keeping climbs further than dumping raw (%.2f vs %.2f shows)", thoughtfulAvg, recklessAvg))

    // (2) Real bust risk: careless play stalls low and busts the opening Show often,
    // so death actually happens — which is what makes Renown (death-is-progress)
    // matter. Measured: reckless avg ≈ 1.2 Shows, busts Show 1 ≈ 44% of runs.
    check(recklessAvg <= 3.0,
          String(format: "reckless play stalls early (avg %.2f ≤ 3.0 shows)", recklessAvg))
    check(recklessBustRate >= 0.10,
          String(format: "careless play carries real bust risk (busts opening Show %.0f%% ≥ 10%%)", recklessBustRate * 100))

    // (3) Winnable but not a lock: a no-upgrade season CAN be run to the Championship
    // with good play, but only rarely — permanent Guild upgrades are what make deep
    // runs reliable. Measured thoughtful win rate ≈ 12%.
    check(thoughtfulWins >= 3,
          String(format: "the Championship is reachable with skill alone (%d/%d thoughtful wins)", thoughtfulWins, n))
    check(thoughtfulWinRate <= 0.50,
          String(format: "but not guaranteed without upgrades (%.0f%% thoughtful win rate ≤ 50%%)", thoughtfulWinRate * 100))
    _ = recklessWins
}

print("\n\(failures == 0 ? "ALL CHECKS PASSED ✅" : "\(failures) CHECK(S) FAILED ❌")")
exit(failures == 0 ? 0 : 1)

