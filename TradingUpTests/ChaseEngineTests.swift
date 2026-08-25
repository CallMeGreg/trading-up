import XCTest
@testable import TradingUp

/// The Chase (v2.0) pure engine: Hunt setup, the rip/sell/grade actions and
/// their Energy/cash costs, Trainer perks, the Score win path, and the
/// meta-progression invariants a play-through leans on. Uses the shared seeded
/// RNG (see `SeededRNG` in GameplaySimulationTests) so every case is reproducible.
final class ChaseEngineTests: XCTestCase {

    private func firstGradeable(_ core: ChaseCore) -> CardInstance? {
        core.run?.stock.first { $0.card.rarity.canBeGraded && $0.grade == nil }
    }

    // MARK: Grail generation

    func testGrailOffersAlwaysOneOfEachTier() {
        var rng = SeededRNG(0xC0FFEE)
        let core = ChaseCore()
        for _ in 0..<200 {
            let offers = core.grailOffers(using: &rng)
            XCTAssertEqual(offers.map(\.tier), [.easy, .medium, .hard],
                           "every draw offers exactly Easy, Medium, Hard in order")
            for g in offers {
                XCTAssertGreaterThan(g.price, 0, "a Grail always has a positive price")
                XCTAssertFalse(g.headline.isEmpty, "a Grail always has a headline")
            }
        }
    }

    func testHardGrailNamesARealCard() {
        var rng = SeededRNG(42)
        let core = ChaseCore()
        for _ in 0..<100 {
            let hard = core.grailOffers(using: &rng)[2]
            if !hard.cardId.isEmpty {
                XCTAssertTrue(CardDatabase.exists(hard.cardId),
                              "a named Hard Grail must reference a card that ships")
            }
        }
    }

    // MARK: Hunt setup

    func testStartHuntInitializesAFreshRun() throws {
        var rng = SeededRNG(1)
        var core = ChaseCore()
        let grail = Grail(tier: .easy, price: 100)
        core.startHunt(grail: grail, trainer: .digger, using: &rng)

        let r = try XCTUnwrap(core.run, "starting a Hunt creates a live run")
        XCTAssertEqual(r.cash, core.meta.stake, "a Hunt starts on the Guild stake")
        XCTAssertEqual(r.lead.index, 1, "a Hunt opens on Lead 1")
        XCTAssertEqual(r.phase, .working, "a Hunt opens working the first Lead")
        XCTAssertGreaterThan(r.energy, 0, "Lead 1 grants Energy")
        XCTAssertFalse(r.route.isEmpty, "Lead 1 shows routes to Lead 2")
        XCTAssertEqual(core.meta.lifetime.huntsStarted, 1, "starting a Hunt is counted")
    }

    func testFinancierStartsWithABiggerStake() {
        var rng = SeededRNG(7)
        var base = ChaseCore(); base.startHunt(grail: Grail(tier: .easy, price: 80), trainer: .digger, using: &rng)
        var fin = ChaseCore();  fin.startHunt(grail: Grail(tier: .easy, price: 80), trainer: .financier, using: &rng)
        XCTAssertEqual((fin.run?.cash ?? 0) - (base.run?.cash ?? 0), Economy.financierBonusStake,
                       "the Financier opens with a larger stake")
    }

    // MARK: Ripping

    func testRipPackSpendsOneEnergyAndTheCashPrice() {
        var rng = SeededRNG(3)
        var core = ChaseCore()
        core.startHunt(grail: Grail(tier: .easy, price: 80), trainer: .digger, using: &rng)
        let energy0 = core.run!.energy, cash0 = core.run!.cash, count0 = core.run!.stock.count

        let pack = core.ripPack(set: 1, using: &rng)
        XCTAssertNotNil(pack, "ripping a set within reach succeeds")
        XCTAssertEqual(core.run!.energy, energy0 - 1, "a rip costs one Energy")
        XCTAssertEqual(core.run!.cash, cash0 - Economy.packPrice(set: 1), accuracy: 0.001, "a rip costs the pack price")
        XCTAssertGreaterThan(core.run!.stock.count, count0, "a rip adds cards to stock")
        XCTAssertEqual(core.meta.lifetime.packsRipped, 1, "a rip is counted lifetime")
    }

    func testRipPackBlockedWithoutEnergy() {
        var rng = SeededRNG(4)
        var core = ChaseCore()
        core.startHunt(grail: Grail(tier: .easy, price: 80), trainer: .digger, using: &rng)
        core.run!.energy = 0
        XCTAssertNil(core.ripPack(set: 1, using: &rng), "no Energy means no rip")
    }

    func testRipPackBlockedAboveMaxSet() {
        var rng = SeededRNG(5)
        var core = ChaseCore()
        core.startHunt(grail: Grail(tier: .easy, price: 80), trainer: .digger, using: &rng)
        XCTAssertNil(core.ripPack(set: core.run!.maxSet + 1, using: &rng),
                     "the paywall blocks ripping above the Hunt's max set")
    }

    func testSpeculatorFirstPackIsFree() {
        var rng = SeededRNG(9)
        var core = ChaseCore()
        core.startHunt(grail: Grail(tier: .easy, price: 80), trainer: .speculator, using: &rng)
        let energy0 = core.run!.energy, cash0 = core.run!.cash
        XCTAssertNotNil(core.ripPack(set: 1, using: &rng))
        XCTAssertEqual(core.run!.energy, energy0, "the Speculator's first pack costs no Energy")
        XCTAssertEqual(core.run!.cash, cash0, accuracy: 0.001, "the Speculator's first pack costs no cash")
        // The second pack is charged normally.
        XCTAssertNotNil(core.ripPack(set: 1, using: &rng))
        XCTAssertEqual(core.run!.energy, energy0 - 1, "the second pack costs Energy again")
    }

    // MARK: Grading & selling

    func testGradeChargesFeeSetsGradeAndRejectsRegrade() {
        var rng = SeededRNG(11)
        var core = ChaseCore()
        core.startHunt(grail: Grail(tier: .easy, price: 80), trainer: .digger, using: &rng)
        while firstGradeable(core) == nil { XCTAssertNotNil(core.ripPack(set: 1, using: &rng)) }
        let target = firstGradeable(core)!
        let cashBefore = core.run!.cash

        let grade = core.grade(instanceId: target.id, using: &rng)
        XCTAssertNotNil(grade, "a gradeable card can be graded")
        XCTAssertLessThan(core.run!.cash, cashBefore, "grading charges a fee")
        XCTAssertNotNil(core.run!.stock.first { $0.id == target.id }?.grade, "the card is now graded")
        XCTAssertNil(core.grade(instanceId: target.id, using: &rng), "a graded card cannot be regraded")
    }

    func testGraderTrainerGradesForFree() {
        var rng = SeededRNG(13)
        var core = ChaseCore()
        core.startHunt(grail: Grail(tier: .easy, price: 80), trainer: .grader, using: &rng)
        XCTAssertTrue(core.gradingIsFree(), "the Grader grades for free")
        while firstGradeable(core) == nil { XCTAssertNotNil(core.ripPack(set: 1, using: &rng)) }
        let target = firstGradeable(core)!
        let cashBefore = core.run!.cash
        XCTAssertNotNil(core.grade(instanceId: target.id, using: &rng))
        XCTAssertEqual(core.run!.cash, cashBefore, accuracy: 0.001, "the Grader pays no grading fee")
    }

    func testSellReturnsCashAndRemovesCard() {
        var rng = SeededRNG(17)
        var core = ChaseCore()
        core.startHunt(grail: Grail(tier: .easy, price: 80), trainer: .digger, using: &rng)
        XCTAssertNotNil(core.ripPack(set: 1, using: &rng))
        let victim = core.run!.stock.first!
        let cashBefore = core.run!.cash, countBefore = core.run!.stock.count

        let proceeds = core.sell(instanceId: victim.id)
        XCTAssertNotNil(proceeds, "an owned card can be sold")
        XCTAssertEqual(core.run!.stock.count, countBefore - 1, "selling removes the card")
        XCTAssertEqual(core.run!.cash, cashBefore + (proceeds ?? 0), accuracy: 0.001, "selling banks the proceeds")
    }

    // MARK: The Score

    func testLandGrailWinsDepositsAndCountsIt() {
        var rng = SeededRNG(21)
        var core = ChaseCore()
        // A classifier-free Grail matches any held card, so we can drive the Score.
        core.startHunt(grail: Grail(tier: .easy, price: 50), trainer: .digger, using: &rng)
        core.run!.lead = Lead(index: core.run!.totalLeads, ask: Ask(kind: .cash),
                              energyBudget: 5, complication: .none, isScore: true)
        core.run!.stock = [CardInstance(cardId: CardDatabase.all[0].id)]
        core.run!.cash = 100

        XCTAssertTrue(core.canLandGrail(), "holding a match plus the price can land the Grail")
        let summary = core.landGrail()
        XCTAssertEqual(summary?.won, true, "landing the Grail wins the Hunt")
        XCTAssertEqual(core.meta.lifetime.huntsWon, 1, "a win is counted lifetime")
        XCTAssertNil(core.run, "landing ends the Hunt")
        XCTAssertGreaterThanOrEqual(core.meta.binderUnique, 1, "the held card is kept in the Binder")
    }

    func testCannotLandWithoutBothHoldAndPrice() {
        var rng = SeededRNG(22)
        var core = ChaseCore()
        core.startHunt(grail: Grail(tier: .easy, price: 50), trainer: .digger, using: &rng)
        core.run!.lead = Lead(index: core.run!.totalLeads, ask: Ask(kind: .cash),
                              energyBudget: 5, complication: .none, isScore: true)
        // Holds a match but is broke.
        core.run!.stock = [CardInstance(cardId: CardDatabase.all[0].id)]
        core.run!.cash = 10
        XCTAssertFalse(core.canLandGrail(), "the price still has to be paid")
        // Has the cash but holds nothing.
        core.run!.stock = []
        core.run!.cash = 100
        XCTAssertFalse(core.canLandGrail(), "a matching card still has to be held")
    }

    func testBustStillDepositsHeldCardsToBinder() {
        var rng = SeededRNG(23)
        var core = ChaseCore()
        core.startHunt(grail: Grail(tier: .easy, price: 80), trainer: .digger, using: &rng)
        XCTAssertNotNil(core.ripPack(set: 1, using: &rng))
        let uniquesHeld = Set(core.run!.stock.map { $0.cardId }).count
        XCTAssertGreaterThan(uniquesHeld, 0)

        let summary = core.giveUp()
        XCTAssertFalse(summary.won, "giving up busts the Hunt")
        XCTAssertNil(core.run, "busting ends the Hunt")
        XCTAssertEqual(core.meta.binderUnique, uniquesHeld,
                       "death is progress: held cards still bank in the Binder")
    }

    // MARK: Meta-progression

    func testDepositKeepsOnlyTheBetterCopy() {
        var meta = MetaState()
        let id = CardDatabase.all[0].id
        XCTAssertTrue(meta.deposit(CardInstance(cardId: id)), "a first copy is kept")
        XCTAssertFalse(meta.deposit(CardInstance(cardId: id)), "a worse/equal copy is rejected")
        XCTAssertTrue(meta.deposit(CardInstance(cardId: id, foil: true, grade: 10)),
                      "a strictly better copy upgrades the slot")
        XCTAssertEqual(meta.binderUnique, 1, "quality upgrades don't create duplicate slots")
    }

    /// Regression: a Discovery can gift a Trainer directly, so the Recruit-Trainer
    /// upgrade's availability/cost must track the *unlocked set*, not a separate
    /// purchase counter — otherwise the Guild offers a slot that then fails to buy.
    func testRecruitTrainerStaysConsistentAfterADiscoveryUnlock() {
        var meta = MetaState()
        meta.renown = 100_000
        _ = meta.unlockTrainer(.foilhunter)   // as if gifted by a Discovery

        var bought = 0
        while meta.canUpgrade(.trainerSlot) {
            XCTAssertNotNil(meta.upgradeCost(.trainerSlot), "an offered slot must have a price")
            XCTAssertTrue(meta.purchase(.trainerSlot), "an offered Recruit-Trainer must actually buy")
            bought += 1
            XCTAssertLessThanOrEqual(bought, TrainerKind.allCases.count, "recruiting must terminate")
        }
        XCTAssertNil(meta.nextTrainerToUnlock, "once all are unlocked, no phantom slot remains")
        XCTAssertEqual(meta.availableTrainers.count, TrainerKind.allCases.count, "every Trainer is unlocked")
    }

    func testSanitizeDropsCardsThatLeftTheCatalogue() {
        var core = ChaseCore()
        core.meta.deposit(CardInstance(cardId: CardDatabase.all[0].id))
        core.meta.binder["S9-999"] = BinderCopy(foil: false, grade: nil)   // not in catalogue
        let clean = core.sanitizedChase()
        XCTAssertNil(clean.meta.binder["S9-999"], "a retired card is dropped from the Binder")
        XCTAssertEqual(clean.meta.binderUnique, 1, "real cards survive sanitize")
    }
}
