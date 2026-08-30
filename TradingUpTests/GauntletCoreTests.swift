import XCTest
@testable import TradingUp

/// A generator that always yields 0, so any `Double.random(in: 0..<1) < chance`
/// gate with a non-zero `chance` fires — lets the per-round rip roll be forced
/// deterministically in a test.
private struct ZeroRNG: RandomNumberGenerator { mutating func next() -> UInt64 { 0 } }

/// The Gauntlet run state machine (`GauntletRun`): the Aura engine, keep /
/// sell / swap, grading, the shop, and how a round resolves into cleared / won /
/// lost. Pure Foundation logic, driven with a seeded RNG so it's
/// reproducible, exactly like the Classic `GameCore` tests. See docs/DESIGN.md §14.
final class GauntletCoreTests: XCTestCase {

    // A couple of low-stage Set-1 cards, reused by the keep/sell/swap tests below.
    private let fireIds = CardDatabase.cards(inSet: 1).filter { $0.element == .fire }.map(\.id)

    // The catalogue's most valuable card, as a foil PSA-10 — a single copy easily
    // clears any Round-1 bar, so round-transition tests don't depend on RNG.
    private var whale: CardInstance {
        let top = CardDatabase.all.max { $0.baseValue < $1.baseValue }!
        return CardInstance(cardId: top.id, foil: true, grade: 10)
    }

    // MARK: Starting state

    func testRunStartsWithTierResources() {
        let run = GauntletRun(tier: .easy, trainer: .neutral)
        XCTAssertEqual(run.round, 1)
        XCTAssertFalse(run.won)
        XCTAssertFalse(run.lost)
        XCTAssertEqual(run.cash, GauntletEconomy.startingCash)
        XCTAssertEqual(run.ripsLeft, GauntletEconomy.ripBudget(.easy, round: 1))
        XCTAssertEqual(run.effectiveSlots, GauntletEconomy.startingSlots(.easy))
        XCTAssertTrue(run.showcase.isEmpty)
    }

    func testTrainerSkillEdgesApplyAtStart() {
        // Skill magnitudes are live: the Merchant's 5-Selling seeds extra starting
        // cash, so a run opens above the base stake.
        let merchant = Trainer.byId("merchant")!
        XCTAssertGreaterThan(merchant.mods.startingCashBonus, 0)
        let run = GauntletRun(tier: .easy, trainer: merchant)
        XCTAssertEqual(run.cash, GauntletEconomy.startingCash + merchant.mods.startingCashBonus, accuracy: 1e-9)

        // The Ripper's 5-Energy is a per-round *chance* of a bonus rip, rolled only by
        // the RNG-threaded init, so the deterministic init opens at the plain budget.
        let ripper = Trainer.byId("ripper")!
        let ripRun = GauntletRun(tier: .easy, trainer: ripper)
        XCTAssertEqual(ripRun.ripsLeft, GauntletEconomy.ripBudget(.easy, round: 1))
    }

    // MARK: Skill downside levers (docs/DESIGN.md §14.3)

    func testLowEnergyRisksLosingARipAtRoundStart() {
        // A 1-Energy Trainer carries a negative bonus-rip chance: at round start it can
        // *lose* a rip. Forcing the roll (ZeroRNG) drops exactly one.
        let weak = Trainer(id: "lowE", name: "LowE", blurb: "",
                           skills: TrainerSkills(energy: 1, aura: 3, selling: 3, grading: 3, inventory: 3))
        var rng = ZeroRNG()
        let run = GauntletRun(tier: .easy, trainer: weak, using: &rng)
        XCTAssertEqual(run.ripsLeft, GauntletEconomy.ripBudget(.easy, round: 1) - 1,
                       "a forced low-Energy roll loses a rip")
    }

    func testHighEnergyCanGainARipAtRoundStart() {
        let strong = Trainer(id: "hiE", name: "HiE", blurb: "",
                             skills: TrainerSkills(energy: 5, aura: 3, selling: 3, grading: 3, inventory: 3))
        var rng = ZeroRNG()
        let run = GauntletRun(tier: .easy, trainer: strong, using: &rng)
        XCTAssertEqual(run.ripsLeft, GauntletEconomy.ripBudget(.easy, round: 1) + 1,
                       "a forced high-Energy roll gains a rip")
    }

    func testGradingLuckBendsRollsUpAndDisadvantageDown() {
        // Grade the same keeper many times under a fixed seed. Because advantage and
        // disadvantage consume the RNG identically (draw g1, the luck check, then g2),
        // a 5-Grading run keeps max(g1, g2) exactly where a 1-Grading run keeps the
        // worse — so the high-Grading average strictly beats the low-Grading one.
        func avgGradeMult(grading: Int, seed: UInt64) -> Double {
            let t = Trainer(id: "g", name: "G", blurb: "",
                            skills: TrainerSkills(energy: 3, aura: 3, selling: 3, grading: grading, inventory: 3))
            var rng = SeededRNG(seed)
            var run = GauntletRun(tier: .easy, trainer: t)
            run.cash = 1e12
            run.keep(CardInstance(cardId: fireIds[0]))
            var total = 0.0
            let n = 4000
            for _ in 0..<n {
                run.showcase[0].grade = nil
                total += Economy.gradeMultiplier(run.gradeShowcaseCard(at: 0, using: &rng)!)
            }
            return total / Double(n)
        }
        let hi = avgGradeMult(grading: 5, seed: 12345)
        let lo = avgGradeMult(grading: 1, seed: 12345)
        XCTAssertGreaterThan(hi, lo, "grading advantage beats disadvantage on average grade value")
    }

    // MARK: Aura engine

    // A full evolution line and one of its lower stages, for the completion-bonus tests.
    private var fullLine: [Card] { CardDatabase.evolutionLines.values.first { $0.count >= 2 }! }

    func testEmptyShowcaseHasZeroAura() {
        XCTAssertEqual(GauntletRun.aura([], evoLineBonusBonus: 0.90, auraMult: 1), 0)
    }

    func testCompleteEvolutionLineEarnsTheCompletionBonus() {
        let line = fullLine
        let cards = line.map { CardInstance(cardId: $0.id) }
        let b = GauntletEconomy.evoLineBonus(set: line[0].set)   // the line's set-scaled bonus
        let raw = cards.reduce(0.0) { $0 + $1.currentValue }

        let complete = GauntletRun.aura(cards, evoLineBonusBonus: 0, auraMult: 1)
        // Every stage is present, so the whole line is lifted by the completion bonus.
        XCTAssertEqual(complete, raw * (1 + b), accuracy: 1e-6)
    }

    func testIncompleteEvolutionLineEarnsNoBonus() {
        let line = fullLine
        let partial = [CardInstance(cardId: line[0].id)]   // only the first stage
        let aura = GauntletRun.aura(partial, evoLineBonusBonus: 0, auraMult: 1)
        XCTAssertEqual(aura, partial[0].currentValue, accuracy: 1e-6)
    }

    func testAuraMultScalesTheWholeShowcase() {
        let cards = fullLine.map { CardInstance(cardId: $0.id) }
        let base = GauntletRun.aura(cards, evoLineBonusBonus: 0, auraMult: 1)
        let lifted = GauntletRun.aura(cards, evoLineBonusBonus: 0, auraMult: 1.10)
        XCTAssertEqual(lifted, base * 1.10, accuracy: 1e-6)
    }

    func testEvolutionLineBonusScalesUpWithSet() {
        let bonuses = (1...CardDatabase.setCount).map { GauntletEconomy.evoLineBonus(set: $0) }
        for (lo, hi) in zip(bonuses, bonuses.dropFirst()) {
            XCTAssertLessThan(lo, hi, "each later set completes a line for strictly more")
        }
        XCTAssertGreaterThanOrEqual(GauntletEconomy.evoLineBonus(set: 5),
                                    2 * GauntletEconomy.evoLineBonus(set: 1),
                                    "a set-5 line completion is worth far more than a set-1 one")
        // Clamps out of range instead of trapping.
        XCTAssertEqual(GauntletEconomy.evoLineBonus(set: 0), GauntletEconomy.evoLineBonus(set: 1))
        XCTAssertEqual(GauntletEconomy.evoLineBonus(set: 99), GauntletEconomy.evoLineBonus(set: 5))
    }

    func testCompletedShowcaseLineIdsFlagsAFullLineForTheCue() {
        var run = GauntletRun(tier: .hard, trainer: .neutral)   // 5 slots
        let line = fullLine
        for c in line { run.keep(CardInstance(cardId: c.id)) }
        XCTAssertTrue(run.completedShowcaseLineIds.contains(line[0].lineId),
                      "a Showcase holding every stage of a line reports it complete")
        XCTAssertTrue(run.isInCompletedLine(run.showcase[0]))
        let set = line[0].set
        XCTAssertEqual(run.evoLineMultiplier(forSet: set), 1 + run.evoLineBonus(forSet: set), accuracy: 1e-9,
                       "the cue's multiplier is 1 + the evolution-line bonus for that card's set")
    }

    func testIncompleteShowcaseLineIsNotFlaggedForTheCue() {
        var run = GauntletRun(tier: .hard, trainer: .neutral)
        let line = fullLine
        run.keep(CardInstance(cardId: line[0].id))   // only the first stage
        XCTAssertFalse(run.completedShowcaseLineIds.contains(line[0].lineId))
        XCTAssertFalse(run.isInCompletedLine(run.showcase[0]),
                       "a partial line earns no bonus, so it shows no multiplier cue")
    }

    // MARK: RunMods composition

    func testRunModsCompose() {
        var a = RunMods.none; a.extraRipsPerRound = 1; a.auraMult = 1.10; a.sellbackBonus = 0.05
        var b = RunMods.none; b.extraRipsPerRound = 2; b.auraMult = 1.20; b.sellbackBonus = 0.03
        let sum = a + b
        XCTAssertEqual(sum.extraRipsPerRound, 3)
        XCTAssertEqual(sum.auraMult, 1.32, accuracy: 1e-9)      // multiplies
        XCTAssertEqual(sum.sellbackBonus, 0.08, accuracy: 1e-9)      // adds
    }

    func testAttunedCatalystsFoldIntoMods() {
        var run = GauntletRun(tier: .easy, trainer: .neutral)
        let eclipse = Catalyst.byId("eclipse")!   // +1 rip
        XCTAssertTrue(run.attune(eclipse))
        XCTAssertEqual(run.mods.extraRipsPerRound, 1)
        XCTAssertEqual(run.effectiveCatalystSlots, GauntletEconomy.baseCatalystSlots)
    }

    func testAttuningExtraRipCatalystGrantsThatRipImmediately() {
        var run = GauntletRun(tier: .easy, trainer: .neutral)
        let before = run.ripsLeft
        let eclipse = Catalyst.byId("eclipse")!   // +1 rip per round
        XCTAssertTrue(run.attune(eclipse))
        XCTAssertEqual(run.ripsLeft, before + 1,
                       "an extra-rip Catalyst pays off the round it's attuned in, not just later rounds")
    }

    func testAttuningNonRipCatalystLeavesCurrentRipsUnchanged() {
        var run = GauntletRun(tier: .easy, trainer: .neutral)
        let before = run.ripsLeft
        let bloom = Catalyst.byId("bloom")!   // Aura mult, no rip bonus
        XCTAssertTrue(run.attune(bloom))
        XCTAssertEqual(run.ripsLeft, before,
                       "a Catalyst with no rip bonus doesn't change the current round's rips")
    }

    func testCanSwapCatalystOnlyWhenSlotsAreFull() {
        var run = GauntletRun(tier: .easy, trainer: .neutral)   // 1 catalyst slot
        XCTAssertTrue(run.canAttune)
        XCTAssertFalse(run.canSwapCatalyst,
                       "with a free slot the offer is Attune, not Swap")
        XCTAssertTrue(run.attune(Catalyst.byId("bloom")!))
        XCTAssertFalse(run.canAttune)
        XCTAssertTrue(run.canSwapCatalyst,
                      "with every slot full (and >0 slots) the offer becomes Swap")
    }

    func testSwapCatalystReplacesInPlaceAndKeepsSlotCount() {
        var run = GauntletRun(tier: .easy, trainer: .neutral)
        let bloom = Catalyst.byId("bloom")!
        let eclipse = Catalyst.byId("eclipse")!
        XCTAssertTrue(run.attune(bloom))
        XCTAssertTrue(run.swapCatalyst(eclipse, at: 0))
        XCTAssertEqual(run.attunedCatalysts.count, 1, "a swap trades one Catalyst for another")
        XCTAssertEqual(run.attunedCatalysts[0].id, eclipse.id)
    }

    func testSwapCatalystDropsOldEffectAndAppliesNew() {
        var run = GauntletRun(tier: .easy, trainer: .neutral)
        let base = run.ripsLeft
        let eclipse = Catalyst.byId("eclipse")!   // +1 rip per round
        let bloom = Catalyst.byId("bloom")!       // Aura mult, no rip bonus
        XCTAssertTrue(run.attune(eclipse))
        XCTAssertEqual(run.ripsLeft, base + 1)
        XCTAssertTrue(run.swapCatalyst(bloom, at: 0))
        XCTAssertEqual(run.ripsLeft, base,
                       "swapping Eclipse out takes back the extra rip it had granted")
        XCTAssertGreaterThan(run.mods.auraMult, 1.0,
                             "swapping Bloom in applies its Aura multiplier immediately")
        XCTAssertEqual(run.mods.extraRipsPerRound, 0,
                       "Eclipse's rip bonus is gone once it's swapped out")
    }

    func testSwapCatalystAtInvalidIndexIsIgnored() {
        var run = GauntletRun(tier: .easy, trainer: .neutral)
        XCTAssertTrue(run.attune(Catalyst.byId("bloom")!))
        XCTAssertFalse(run.swapCatalyst(Catalyst.byId("eclipse")!, at: 3))
        XCTAssertEqual(run.attunedCatalysts[0].id, "bloom", "an out-of-range swap changes nothing")
    }

    // MARK: Ripping / keeping / selling

    func testRipSpendsARipAndFillsAPack() {
        var rng = SeededRNG(1)
        var run = GauntletRun(tier: .easy, trainer: .neutral)
        let before = run.ripsLeft
        let res = run.rip(using: &rng)
        XCTAssertEqual(run.ripsLeft, before - 1)
        XCTAssertEqual(res.cards.count, Economy.commonsPerPack + Economy.uncommonsPerPack + 1)
    }

    func testKeepFillsToCapacityThenBlocks() {
        var run = GauntletRun(tier: .hard, trainer: .neutral)   // 5 slots
        for _ in 0..<run.effectiveSlots { run.keep(CardInstance(cardId: fireIds[0])) }
        XCTAssertFalse(run.canKeep)
        run.keep(CardInstance(cardId: fireIds[1]))              // ignored
        XCTAssertEqual(run.showcase.count, run.effectiveSlots)
    }

    func testSellAddsSpreadToCash() {
        var run = GauntletRun(tier: .easy, trainer: .neutral)
        let card = CardInstance(cardId: fireIds[0], foil: true)
        let cashBefore = run.cash
        let gained = run.sell(card)
        XCTAssertEqual(gained, card.currentValue * run.sellbackRate, accuracy: 1e-6)
        XCTAssertEqual(run.cash, cashBefore + gained, accuracy: 1e-6)
    }

    func testSwapInBanksTheRemovedCard() {
        var run = GauntletRun(tier: .easy, trainer: .neutral)
        let weak = CardInstance(cardId: fireIds[0])
        run.keep(weak)
        let cashBefore = run.cash
        let removed = run.swapIn(whale, at: 0)
        XCTAssertEqual(removed.cardId, weak.cardId)
        XCTAssertEqual(run.showcase[0].cardId, whale.cardId)
        XCTAssertEqual(run.cash, cashBefore + weak.currentValue * run.sellbackRate, accuracy: 1e-6)
    }

    // MARK: Grading

    func testGradingPaysFeeAndSetsGrade() {
        var rng = SeededRNG(7)
        var run = GauntletRun(tier: .easy, trainer: .neutral)
        run.cash = 1000
        run.keep(CardInstance(cardId: fireIds[0], foil: true))
        let fee = run.gradeFee(for: run.showcase[0].card)
        let cashBefore = run.cash
        let g = run.gradeShowcaseCard(at: 0, using: &rng)
        XCTAssertNotNil(g)
        XCTAssertNotNil(run.showcase[0].grade)
        XCTAssertEqual(run.cash, cashBefore - fee, accuracy: 1e-6)
        // Grading again is a no-op (already graded).
        XCTAssertNil(run.gradeShowcaseCard(at: 0, using: &rng))
    }

    func testGradingBlockedWhenBroke() {
        var rng = SeededRNG(7)
        var run = GauntletRun(tier: .easy, trainer: .neutral)
        run.cash = 0
        run.keep(CardInstance(cardId: fireIds[0]))
        XCTAssertNil(run.gradeShowcaseCard(at: 0, using: &rng))
        XCTAssertNil(run.showcase[0].grade)
    }

    // MARK: Round resolution

    func testClearingARoundAdvancesAndPays() {
        var rng = SeededRNG(3)
        var run = GauntletRun(tier: .easy, trainer: .neutral)
        run.cash = 0
        run.showcase = [whale]                       // easily over the Round-1 bar
        XCTAssertGreaterThanOrEqual(run.showcaseAura, run.target)
        let outcome = run.endRound(using: &rng)
        XCTAssertEqual(outcome, .cleared)
        XCTAssertEqual(run.round, 2)
        XCTAssertGreaterThan(run.cash, 0)            // stipend (+ interest) paid
    }

    func testClearingFinalRoundWinsTheRun() {
        var rng = SeededRNG(3)
        var run = GauntletRun(tier: .easy, trainer: .neutral)
        run.round = run.roundsTotal
        run.showcase = [whale]
        XCTAssertEqual(run.endRound(using: &rng), .won)
        XCTAssertTrue(run.won)
    }

    func testMissingTheBarLosesTheRunImmediately() {
        var rng = SeededRNG(3)
        var run = GauntletRun(tier: .easy, trainer: .neutral)
        // Empty showcase → Aura 0 < target → miss. Rounds are single-life,
        // so any miss ends the run — no reprints.
        XCTAssertEqual(run.endRound(using: &rng), .lost)
        XCTAssertTrue(run.lost)
        XCTAssertEqual(run.round, 1)
    }

    // MARK: Shop

    func testUnlockingPacksCostsCashAndOpensEverySet() {
        var run = GauntletRun(tier: .easy, trainer: .neutral)
        run.cash = 100_000
        // Only the starter set is open; unlocking the cheapest-next set each time
        // walks the whole rail and matches the per-set price.
        while let set = run.nextLockedPack {
            let cost = run.packUnlockCost(set)!
            let cashBefore = run.cash
            XCTAssertFalse(run.isPackUnlocked(set))
            XCTAssertTrue(run.unlockPack(set))
            XCTAssertEqual(run.cash, cashBefore - cost, accuracy: 1e-6)
            XCTAssertTrue(run.isPackUnlocked(set))
        }
        XCTAssertEqual(run.unlockedPacks.count, GauntletEconomy.maxPackTier)
        XCTAssertEqual(run.packTier, GauntletEconomy.maxPackTier)
        XCTAssertNil(run.nextLockedPack)
        XCTAssertFalse(run.unlockNextPack())
    }

    func testPacksUnlockOutOfOrderIndependently() {
        var run = GauntletRun(tier: .easy, trainer: .neutral)
        run.cash = 100_000
        // Buying the top set open must not require the sets beneath it.
        let top = GauntletEconomy.maxPackTier
        XCTAssertTrue(run.unlockPack(top))
        XCTAssertTrue(run.isPackUnlocked(top))
        XCTAssertFalse(run.isPackUnlocked(2), "unlocking a high set leaves lower sets locked")
        XCTAssertEqual(run.packTier, top, "packTier tracks the highest unlocked set")
        // The starter is always open and can't be re-bought.
        XCTAssertNil(run.packUnlockCost(1))
        XCTAssertFalse(run.unlockPack(1))
    }

    func testUnlockPackIsANoOpWhenUnaffordable() {
        var run = GauntletRun(tier: .easy, trainer: .neutral)
        run.cash = 0
        XCTAssertFalse(run.canUnlockPack(2))
        XCTAssertFalse(run.unlockPack(2))
        XCTAssertFalse(run.isPackUnlocked(2))
    }

    func testBuyingSlotsRaisesCapacityAndCosts() {
        var run = GauntletRun(tier: .easy, trainer: .neutral)
        run.cash = 10_000
        let slotsBefore = run.effectiveSlots
        let cost = run.nextSlotCost
        let cashBefore = run.cash
        XCTAssertTrue(run.buySlot())
        XCTAssertEqual(run.effectiveSlots, slotsBefore + 1)
        XCTAssertEqual(run.cash, cashBefore - cost, accuracy: 1e-6)
        XCTAssertGreaterThan(run.nextSlotCost, cost)     // next one costs more
    }
}
