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
        check(res != nil && (1...10).contains(res!.grade), "graded a card to a valid PSA grade")
    }

    var broke = GameCore()
    broke.cash = 0
    broke.instances = [CardInstance(cardId: "S1-001")]
    check(broke.isGameOver, "broke with only last-copies = game over")
    broke.instances.append(CardInstance(cardId: "S1-001"))
    check(broke.isGameOver, "broke with a dupe worth pennies = still game over")
    broke.cash = Economy.cheapestPackPrice - 0.10
    check(!broke.isGameOver, "a dupe that covers the shortfall = still in the game")

    // Grading is the other escape hatch, so a gradeable dupe you can afford to
    // send in has to count even when selling it raw wouldn't be enough.
    var gamble = GameCore()
    gamble.cash = 2
    gamble.instances = [CardInstance(cardId: "S1-003"), CardInstance(cardId: "S1-003")]
    check(gamble.cash + gamble.instances[0].sellValue < Economy.cheapestPackPrice,
          "that rare sold raw wouldn't reach a pack")
    check(!gamble.isGameOver, "a gradeable dupe you can afford to grade = a way out")
    gamble.cash = Economy.gradeFee(set: 1) - 0.01
    check(gamble.isGameOver, "gradeable dupe but no fee money = game over")

    // Loss threshold is the cheapest pack price ($10), NOT $0: you lose once you
    // can no longer afford even the cheapest pack, and selling everything you
    // could spare (grading the worthwhile ones first) still wouldn't get you one.
    check(Economy.cheapestPackPrice == 10, "cheapest pack price is $10")
    var edge = GameCore()
    edge.instances = [CardInstance(cardId: "S1-001")]   // only a last copy (unsellable)
    edge.cash = Economy.cheapestPackPrice - 0.01        // $9.99 — can't afford any pack
    check(edge.isGameOver, "cash just under cheapest pack with no sellables = game over")
    edge.cash = Economy.cheapestPackPrice               // exactly $10 — can still buy a pack
    check(!edge.isGameOver, "cash == cheapest pack price = still in the game")

    // Only genuine extras count: with three copies, two can go and one must stay.
    var extras = GameCore()
    extras.cash = 0
    extras.instances = Array(repeating: CardInstance(cardId: "S1-001"), count: 3)
    check(extras.sellableExtras.count == 2, "3 copies = 2 sellable extras")
    check(abs(extras.maxRaisableCash - 2 * extras.instances[0].sellValue) < 0.001,
          "raisable cash counts each extra exactly once")
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
    // per set: 6 trios×2.0 + 7 duos×1.0 + 1 set×15 = 34.0 × pack price
    let expected = 34.0 * (10 + 30 + 75 + 160 + 400)
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

print("\n== Win presentation ==")
do {
    var core = GameCore()
    for c in CardDatabase.all { core.instances.append(CardInstance(cardId: c.id)) }
    _ = core.checkBonuses()
    check(core.hasWon && core.shouldShowWin, "the win overlay shows once the collection is complete")
    core.acknowledgeWin()
    check(core.hasWon && !core.shouldShowWin,
          "dismissing the win keeps the completed collection instead of forcing a reset")
    check(!core.isGameOver, "a finished collection can't then be flagged game over")
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
    var boxesOK = true, bonusOK = true
    for s in 1...5 {
        if abs(Economy.boxPrice(set: s) - Economy.packPrice(set: s) * 11) > 1e-9 { boxesOK = false }
        if abs(Economy.setCompletionBonus(set: s) - Economy.packPrice(set: s) * 15) > 1e-9 { bonusOK = false }
    }
    check(boxesOK, "booster box = 11× pack price (trimmed the free-pack ATM discount)")
    check(bonusOK, "set-completion bonus = 15× pack price (was 30×)")
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

// Play a full game with a fixed strategy, always working the cheapest unlocked,
// incomplete set. While booster boxes are on the shelf it buys one whenever
// affordable (boxes complete sets fastest via their ultra/foil guarantees);
// with `FeatureFlags.removeBoosterBoxes` on it buys packs only, so these runs
// keep describing the game players can actually reach. `.reckless` dumps every
// dupe raw; `.thoughtful` first grades the high-value dupes it's about to sell —
// grading is +EV on pricey cards thanks to the cheap flat fee, so it squeezes
// extra cash out of the same pulls. Crude proxies, but they bracket careless vs.
// considered play.
enum Style { case reckless, thoughtful }

func playStrategy(seed: UInt64, style: Style) -> (won: Bool, lost: Bool, capped: Bool) {
    var rng = SeededRNG(seed)
    var core = GameCore()
    // Grade before selling only when the ~1.5× grade EV clears the fee:
    // s·(1.5v) − fee > s·v  ⇔  v > fee/(0.5·s).
    let gradeThreshold = { (fee: Double) in fee / (0.5 * Economy.sellbackRate) }
    for _ in 0..<200_000 {
        if core.hasWon { return (true, false, false) }
        if core.isGameOver { return (false, true, false) }

        // Liquidate duplicates (thoughtful grades the valuable ones first).
        if style == .thoughtful {
            for cardId in core.uniqueOwnedIds {
                let copies = core.instances(of: cardId).sorted { $0.currentValue > $1.currentValue }
                guard copies.count > 1 else { continue }
                for extra in copies.dropFirst() {
                    if extra.card.rarity.canBeGraded, extra.grade == nil,
                       extra.currentValue > gradeThreshold(Economy.gradeFee(set: extra.card.set)),
                       core.cash >= Economy.gradeFee(set: extra.card.set) {
                        _ = core.grade(instanceId: extra.id, using: &rng)
                    }
                    _ = core.sell(instanceId: extra.id)
                }
            }
        } else {
            _ = core.sellDuplicates(of: core.uniqueOwnedIds)
        }

        let incomplete = (1...CardDatabase.setCount)
            .filter { core.isUnlocked(set: $0) && core.ownedCount(inSet: $0) < 50 }
        guard let target = incomplete.first else { return (core.hasWon, core.isGameOver, false) }
        if FeatureFlags.boosterBoxesAvailable, core.cash >= Economy.boxPrice(set: target) {
            _ = core.buyBox(set: target, using: &rng)
        } else if core.cash >= Economy.packPrice(set: target) {
            _ = core.buyPack(set: target, using: &rng)
        } else if let cheap = incomplete.first(where: { core.cash >= Economy.packPrice(set: $0) }) {
            _ = core.buyPack(set: cheap, using: &rng)
        } else {
            return (false, true, false)             // stuck: can't afford to progress → lost
        }
    }
    return (core.hasWon, core.isGameOver, true)     // hit the safety cap (should not happen)
}

print("\n== Strategy simulations (risk & winnability) ==")
print("  shop sells: packs" + (FeatureFlags.boosterBoxesAvailable ? " + booster boxes" : " only"))
do {
    let n = 200
    var recklessBust = 0.0, recklessWin = 0.0, thoughtfulWin = 0.0
    for (label, style) in [("Reckless (spam the cheapest set, dump raw)", Style.reckless),
                           ("Thoughtful (reserve + grade dupes)", Style.thoughtful)] {
        var wins = 0, losses = 0, capped = 0
        for s in 0..<n {
            let r = playStrategy(seed: 0xA11CE &+ UInt64(s), style: style)
            if r.capped { capped += 1 } else if r.won { wins += 1 } else if r.lost { losses += 1 }
        }
        let winPct = Double(wins) / Double(n) * 100
        let lossPct = Double(losses) / Double(n) * 100
        let capNote = capped > 0 ? ", \(capped) capped" : ""
        print("  \(label): win \(Int(winPct.rounded()))%  bust \(Int(lossPct.rounded()))%  (n=\(n)\(capNote))")
        check(capped == 0, "\(label): all games resolve (no runaway)")
        if style == .reckless { recklessBust = lossPct; recklessWin = winPct } else { thoughtfulWin = winPct }
    }
    // "Moderate": careless spam-and-dump carries real bankruptcy risk (currently ~61%) …
    check(recklessBust >= 25, "reckless spam-and-dump can bankrupt you (bust ≥ 25%)")
    // … considered play (grade valuable dupes before selling) still usually wins (~59%).
    // The floor is 55, not 60: at a 75% sell-back rate on a packs-only shop the model
    // puts thoughtful play at 59%, which still clears "usually wins" with room for
    // model drift. Raising it back to 60 means raising the sell-back rate to ~0.76.
    check(thoughtfulWin >= 55, "thoughtful play still usually wins (win ≥ 55%)")
    // … and skill is worth a lot: grading meaningfully lifts the win rate over reckless.
    check(thoughtfulWin - recklessWin >= 10, "grading dupes is a real edge (win gap ≥ 10 pts)")
}

print("\n== Gauntlet: appraisal engine & knobs ==")
do {
    // Synergy: two same-element cards must appraise higher than two off-element
    // ones of equal value, and the empty Showcase scores nothing.
    // Elements are set-locked (Set 1 = fire, Set 2 = water, …), so a mixed-element
    // pair means pulling cards from two different sets/tiers.
    let fireCards = CardDatabase.cards(inSet: 1).filter { $0.element == .fire }
    let fireA = CardInstance(cardId: fireCards[0].id)
    let fireB = CardInstance(cardId: fireCards[1].id)
    let water = CardInstance(cardId: CardDatabase.cards(inSet: 2).first { $0.element == .water }!.id)
    let spm = GauntletEconomy.baseSynergyPerMatch
    check(GauntletRun.appraise([], synergyPerMatch: spm, appraisalMult: 1) == 0, "empty Showcase appraises to 0")
    // The engine formula is exact: a same-element pair earns the synergy multiplier,
    // a mixed pair earns none — regardless of the cards' raw base values.
    let matched = GauntletRun.appraise([fireA, fireB], synergyPerMatch: spm, appraisalMult: 1)
    let mixed = GauntletRun.appraise([fireA, water], synergyPerMatch: spm, appraisalMult: 1)
    let matchedExpected = (fireA.currentValue + fireB.currentValue) * (1 + spm)
    let mixedExpected = fireA.currentValue + water.currentValue
    check(abs(matched - matchedExpected) < 1e-6, "same-element pair earns the synergy multiplier")
    check(abs(mixed - mixedExpected) < 1e-6, "off-element pair earns no synergy")

    // RunMods compose: additive fields add, multiplicative fields multiply.
    var a = RunMods.none; a.extraRipsPerRound = 1; a.appraisalMult = 1.10
    var b = RunMods.none; b.extraRipsPerRound = 2; b.appraisalMult = 1.20
    let sum = a + b
    check(sum.extraRipsPerRound == 3, "RunMods sum additive fields")
    check(abs(sum.appraisalMult - 1.32) < 1e-9, "RunMods multiply the *Mult fields")

    // Target curve rises every round and the Hard finale is a spiked boss.
    var rising = true
    for r in 2...GauntletEconomy.rounds(.hard) where GauntletEconomy.target(.hard, round: r) <= GauntletEconomy.target(.hard, round: r - 1) { rising = false }
    check(rising, "Hard target rises every round")
    check(GauntletEconomy.isBossRound(.hard, round: GauntletEconomy.rounds(.hard)), "Hard's last round is the boss")
    let bossR = GauntletEconomy.rounds(.hard)
    let unspiked = GauntletEconomy.baseTarget(.hard) * pow(GauntletEconomy.targetGrowth(.hard), Double(bossR - 1))
    check(GauntletEconomy.target(.hard, round: bossR) > unspiked * 1.4, "boss round spikes the bar")
    check(!GauntletEconomy.isBossRound(.easy, round: GauntletEconomy.rounds(.easy)), "Easy/Medium have no boss round")

    // Interest is capped — banking is a lever, not a runaway engine.
    check(GauntletEconomy.interest(on: 100_000) == GauntletEconomy.interestCap, "interest is capped")
    check(GauntletEconomy.interest(on: 100) == 100 * GauntletEconomy.interestRate, "interest is linear below the cap")
}

print("\n== Gauntlet: difficulty curve (Monte Carlo) ==")
do {
    let n = 200
    var opt: [GauntletTier: Double] = [:]
    var car: [GauntletTier: Double] = [:]
    var cappedTotal = 0
    for tier in GauntletTier.allCases {
        let o = GauntletSim.winRate(tier: tier, trainer: .neutral, style: .optimized, trials: n, seed0: 0x6A17)
        let c = GauntletSim.winRate(tier: tier, trainer: .neutral, style: .careless, trials: n, seed0: 0x6A17)
        opt[tier] = o.win; car[tier] = c.win
        cappedTotal += o.capped + c.capped
        print("  \(tier.rawValue): optimized win \(Int(o.win.rounded()))% / careless win \(Int(c.win.rounded()))%  (n=\(n))")
    }

    check(cappedTotal == 0, "every Gauntlet run resolves (no runaway)")

    // Winnable with skill on every tier; Easy is a gentle teacher.
    check(opt[.easy]! >= 90, "Easy is winnable with optimal play (≥ 90%)")
    check(opt[.medium]! >= 70, "Medium is winnable with optimal play (≥ 70%)")
    // Guardrail (docs/DESIGN.md §14.3): a level-0, no-Trainer run clears Hard.
    check(opt[.hard]! >= 45, "a level-0 neutral run clears Hard with optimal play (≥ 45%)")
    // …but Hard is never a formality.
    check(opt[.hard]! <= 85, "Hard is not a formality even played perfectly (≤ 85%)")

    // Careless play carries real bankruptcy risk that climbs with the tier.
    check(100 - car[.medium]! >= 45, "careless play often busts on Medium (bust ≥ 45%)")
    check(100 - car[.hard]! >= 80, "careless play almost always busts on Hard (bust ≥ 80%)")

    // Skill is worth a lot — the whole point of the mode.
    check(opt[.medium]! - car[.medium]! >= 25, "skill is a big edge on Medium (win gap ≥ 25 pts)")
    check(opt[.hard]! - car[.hard]! >= 30, "skill is a big edge on Hard (win gap ≥ 30 pts)")

    // Difficulty is ordered Easy → Medium → Hard, not just re-skinned.
    check(opt[.easy]! >= opt[.medium]! && opt[.medium]! >= opt[.hard]! + 10, "optimal win rate falls Easy → Medium → Hard")
    check(car[.easy]! >= car[.medium]! && car[.medium]! >= car[.hard]!, "careless win rate falls Easy → Medium → Hard")
}

print("\n== Gauntlet: Trainers help but are never required ==")
do {
    let n = 120
    let base = GauntletSim.winRate(tier: .hard, trainer: .neutral, style: .optimized, trials: n, seed0: 0x2C7)
    var minT = 100.0, maxT = 0.0
    for t in Trainer.roster {
        let r = GauntletSim.winRate(tier: .hard, trainer: t, style: .optimized, trials: n, seed0: 0x2C7)
        minT = min(minT, r.win); maxT = max(maxT, r.win)
        print("  \(t.name): Hard optimized win \(Int(r.win.rounded()))%  (vs neutral \(Int(base.win.rounded()))%)")
    }
    check(minT >= base.win - 5, "no Trainer is a downgrade on Hard (all ≥ neutral within noise)")
    check(maxT <= 97, "no Trainer trivialises Hard (best ≤ 97%)")
}

print("\n\(failures == 0 ? "ALL CHECKS PASSED ✅" : "\(failures) CHECK(S) FAILED ❌")")
exit(failures == 0 ? 0 : 1)

