import XCTest
@testable import TradingUp

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

    func testTrainerBonusesApplyAtStart() {
        // Skill magnitudes are unset (a later balance pass tunes them), so today
        // every Trainer opens at the neutral baseline — no seed-cash edge, no bonus
        // rip. The verify harness keeps the mode winnable until they're set.
        let merchant = Trainer.byId("merchant")!
        let run = GauntletRun(tier: .easy, trainer: merchant)
        XCTAssertEqual(run.cash, GauntletEconomy.startingCash)
        XCTAssertEqual(merchant.mods, .none)

        let ripper = Trainer.byId("ripper")!
        let ripRun = GauntletRun(tier: .easy, trainer: ripper)
        XCTAssertEqual(ripRun.ripsLeft, GauntletEconomy.ripBudget(.easy, round: 1))
    }

    // MARK: Aura engine

    // A full evolution line and one of its lower stages, for the completion-bonus tests.
    private var fullLine: [Card] { CardDatabase.evolutionLines.values.first { $0.count >= 2 }! }

    func testEmptyShowcaseHasZeroAura() {
        XCTAssertEqual(GauntletRun.aura([], evoLineBonus: 0.90, auraMult: 1), 0)
    }

    func testCompleteEvolutionLineEarnsTheCompletionBonus() {
        let line = fullLine
        let cards = line.map { CardInstance(cardId: $0.id) }
        let b = GauntletEconomy.baseEvoLineBonus
        let raw = cards.reduce(0.0) { $0 + $1.currentValue }

        let complete = GauntletRun.aura(cards, evoLineBonus: b, auraMult: 1)
        // Every stage is present, so the whole line is lifted by the completion bonus.
        XCTAssertEqual(complete, raw * (1 + b), accuracy: 1e-6)
    }

    func testIncompleteEvolutionLineEarnsNoBonus() {
        let line = fullLine
        let partial = [CardInstance(cardId: line[0].id)]   // only the first stage
        let b = GauntletEconomy.baseEvoLineBonus
        let aura = GauntletRun.aura(partial, evoLineBonus: b, auraMult: 1)
        XCTAssertEqual(aura, partial[0].currentValue, accuracy: 1e-6)
    }

    func testAuraMultScalesTheWholeShowcase() {
        let cards = fullLine.map { CardInstance(cardId: $0.id) }
        let b = GauntletEconomy.baseEvoLineBonus
        let base = GauntletRun.aura(cards, evoLineBonus: b, auraMult: 1)
        let lifted = GauntletRun.aura(cards, evoLineBonus: b, auraMult: 1.10)
        XCTAssertEqual(lifted, base * 1.10, accuracy: 1e-6)
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
