import XCTest
@testable import TradingUp

final class GauntletDecisionTests: XCTestCase {
    func testEverySwapPreviewMatchesTheActualSwapWithTrainerAndCatalystModifiers() {
        for trainer in [Trainer.neutral] + Trainer.roster {
            var run = DebugGauntletScenario.swap.snapshot.run
            run.trainer = trainer
            run.showcase[1].foil = true
            run.showcase[2].grade = 9
            XCTAssertTrue(run.attune(Catalyst.byId("bloom")!))
            let before = run
            let incoming = CardInstance(cardId: "S1-006", foil: true, grade: 10)
            let previews = run.swapPreviews(for: incoming)

            XCTAssertEqual(previews.count, run.showcase.count)
            for preview in previews {
                var actual = run
                let removed = actual.swapIn(incoming, at: preview.index)
                XCTAssertEqual(removed.id, preview.outgoing.id)
                XCTAssertEqual(preview.auraAfter, actual.showcaseAura, accuracy: 1e-9)
                XCTAssertEqual(preview.auraChange, actual.showcaseAura - run.showcaseAura, accuracy: 1e-9)
                XCTAssertEqual(preview.cashGain, actual.cash - run.cash, accuracy: 1e-9)
                XCTAssertEqual(preview.completedLineIds,
                               actual.completedShowcaseLineIds.subtracting(run.completedShowcaseLineIds))
                XCTAssertEqual(preview.brokenLineIds,
                               run.completedShowcaseLineIds.subtracting(actual.completedShowcaseLineIds))
            }
            XCTAssertEqual(run.showcase, before.showcase, "previewing must not move any cards")
            XCTAssertEqual(run.cash, before.cash)
            XCTAssertEqual(run.ripsLeft, before.ripsLeft)
            XCTAssertEqual(run.packsRipped, before.packsRipped)
            for pair in zip(previews, previews.dropFirst()) {
                XCTAssertGreaterThanOrEqual(pair.0.auraAfter, pair.1.auraAfter)
            }
        }
    }

    func testSwappingAwayACheapLinemateCanLoseAuraDespiteAHigherCardPrice() throws {
        let run = DebugGauntletScenario.swap.snapshot.run
        let incoming = CardInstance(cardId: "S1-048")
        let preview = try XCTUnwrap(run.swapPreviews(for: incoming).first { $0.index == 0 })
        XCTAssertGreaterThan(incoming.currentValue, preview.outgoing.currentValue)
        XCTAssertEqual(preview.auraChange, -14.82, accuracy: 1e-9)
        XCTAssertEqual(preview.brokenLineIds, ["S1-E3-1"])
        XCTAssertEqual(run.swapPreviews(for: incoming).first?.index, 5)
    }

    func testCompletingALineIncludesTheBonusOnItsExistingStages() throws {
        let run = DebugGauntletScenario.swap.snapshot.run
        let incoming = CardInstance(cardId: "S1-006")
        let preview = try XCTUnwrap(run.swapPreviews(for: incoming).first)
        XCTAssertEqual(preview.index, 5)
        XCTAssertEqual(preview.auraAfter, 60.30, accuracy: 1e-9)
        XCTAssertEqual(preview.auraChange, 29.53, accuracy: 1e-9)
        XCTAssertEqual(preview.completedLineIds, ["S1-E3-2"])
        XCTAssertTrue(preview.brokenLineIds.isEmpty)
    }

    func testReplacingADuplicateStageDoesNotBreakTheLine() throws {
        var run = GauntletRun(tier: .easy, trainer: .neutral)
        for id in ["S1-001", "S1-002", "S1-003", "S1-001"] {
            run.keep(CardInstance(cardId: id))
        }
        let incoming = CardInstance(cardId: "S1-048")
        let preview = try XCTUnwrap(run.swapPreviews(for: incoming).first { $0.index == 0 })
        XCTAssertTrue(preview.brokenLineIds.isEmpty)
        XCTAssertEqual(preview.auraChange, incoming.currentValue - 0.36 * 6, accuracy: 1e-9)
    }

    func testUpgradingTheSameStagePreservesItsCompletedLine() throws {
        let run = DebugGauntletScenario.swap.snapshot.run
        let incoming = CardInstance(cardId: "S1-001", foil: true)
        let preview = try XCTUnwrap(run.swapPreviews(for: incoming).first { $0.index == 0 })
        XCTAssertTrue(preview.brokenLineIds.isEmpty)
        XCTAssertTrue(preview.completedLineIds.isEmpty)
        XCTAssertEqual(preview.auraChange,
                       (incoming.currentValue - run.showcase[0].currentValue) * 6, accuracy: 1e-9)
    }

    func testEmptyShowcaseHasNoSwapOptionsAndTiesKeepSlotOrder() {
        var run = GauntletRun(tier: .easy, trainer: .neutral)
        let incoming = CardInstance(cardId: "S1-048")
        XCTAssertTrue(run.swapPreviews(for: incoming).isEmpty)
        run.keep(CardInstance(cardId: "S1-001"))
        run.keep(CardInstance(cardId: "S1-001"))
        XCTAssertEqual(run.swapPreviews(for: incoming).map(\.index), [0, 1])
    }

    func testGradeAvailabilityUsesTheActualTrainerFeeAndExcludesGradedCards() {
        var run = GauntletRun(tier: .hard, trainer: Trainer.byId("grader")!)
        run.keep(CardInstance(cardId: "S1-050"))
        let fee = run.gradeFee(for: run.showcase[0].card)
        run.cash = fee - 0.01
        XCTAssertFalse(run.hasAffordableGrade)
        run.cash = fee
        XCTAssertTrue(run.hasAffordableGrade)
        XCTAssertFalse(run.canGradeShowcaseCard(at: -1))
        XCTAssertFalse(run.canGradeShowcaseCard(at: 1))
        run.showcase[0].grade = 8
        XCTAssertFalse(run.hasAffordableGrade)
    }

    func testShoppingChangesCashButNotThePreviousRoundsEarnings() {
        var run = DebugGauntletScenario.shop.snapshot.run
        let cash = run.cash
        let earnings = run.lastClearEarnings
        XCTAssertEqual(earnings, run.lastInterest + run.lastStipend + run.lastRipBank)
        XCTAssertTrue(run.unlockPack(2))
        XCTAssertEqual(run.lastClearEarnings, earnings)
        XCTAssertEqual(run.cash, cash - GauntletEconomy.packUnlockCost(set: 2)!, accuracy: 1e-9)
    }
}

@MainActor
final class GauntletDecisionStateTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tu_decisions_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    private func loadState(seed: UInt64 = 0) -> GauntletState {
        GauntletState(game: GameState(core: GameCore(), store: SaveStore(directory: directory)),
                      store: GauntletProgressStore(directory: directory),
                      runStore: GauntletRunStore(directory: directory), seed: seed)
    }

    private func seed(_ snapshot: GauntletRunSnapshot, rng: UInt64 = 0) -> GauntletState {
        XCTAssertTrue(GauntletRunStore(directory: directory).save(snapshot))
        return loadState(seed: rng)
    }

    private func settleLastPack(_ state: GauntletState) throws {
        let card = try XCTUnwrap(state.pendingCards.first)
        state.sell(card)
        XCTAssertEqual(state.phase, .ripping, "never interrupt the reveal")
        state.finishReveal()
    }

    func testLastRipLeavesAnAffordableGradeAvailableAndSavesTheChance() throws {
        let state = seed(DebugGauntletScenario.lastPack.snapshot)
        try settleLastPack(state)
        XCTAssertEqual(state.phase, .ripping)
        XCTAssertTrue(state.isLastChance)
        XCTAssertFalse(state.canRip)
        XCTAssertTrue(state.canGrade(showcaseIndex: 0))
        XCTAssertTrue(state.canEndRound)
        state.persistForExit()
        let restored = loadState()
        XCTAssertTrue(restored.isLastChance)
        XCTAssertEqual(restored.run?.showcase, state.run?.showcase)
        XCTAssertEqual(restored.run?.cash, state.run?.cash)
    }

    func testWinningLastChanceGradeShowsItsResultBeforeOpeningTheShop() throws {
        let state = seed(DebugGauntletScenario.lastPack.snapshot)
        try settleLastPack(state)
        let cash = try XCTUnwrap(state.run?.cash)
        XCTAssertEqual(state.grade(showcaseIndex: 0, deferResolution: true), 9)
        XCTAssertEqual(state.phase, .ripping, "the grade result remains visible")
        XCTAssertEqual(state.run?.cash ?? 0, cash - 2, accuracy: 1e-9)
        XCTAssertFalse(state.canEndRound)
        XCTAssertFalse(state.canRip)
        XCTAssertNil(state.grade(showcaseIndex: 0), "no reroll or second fee")
        state.finishGrading()
        XCTAssertEqual(state.phase, .shop)
        XCTAssertEqual(state.run?.round, 2)
        XCTAssertFalse(state.run?.lost ?? true)
    }

    func testFailedLastChanceGradeShowsItsResultThenEndsWithoutADeadEnd() throws {
        let state = seed(DebugGauntletScenario.lastPack.snapshot, rng: 7)
        try settleLastPack(state)
        XCTAssertEqual(state.grade(showcaseIndex: 0, deferResolution: true), 7)
        XCTAssertEqual(state.phase, .ripping)
        state.finishGrading()
        XCTAssertEqual(state.phase, .lost)
        XCTAssertFalse(GauntletRunStore(directory: directory).hasSavedRun)
        XCTAssertEqual(state.progress.stats[GauntletStat.cardsGraded], 1)
        state.endRound()
        XCTAssertEqual(state.progress.stats[GauntletStat.cardsGraded], 1, "a loss is banked once")
    }

    func testReloadDuringGradeReviewResolvesTheSavedResultWithoutRerolling() throws {
        let state = seed(DebugGauntletScenario.lastPack.snapshot)
        try settleLastPack(state)
        XCTAssertEqual(state.grade(showcaseIndex: 0, deferResolution: true), 9)
        let restored = loadState(seed: 7)
        XCTAssertEqual(restored.phase, .shop)
        XCTAssertEqual(restored.run?.showcase[0].grade, 9)
        XCTAssertEqual(restored.run?.cardsGraded, 1)
    }

    func testLastPackWithoutAnAffordableGradeStillLosesAutomatically() throws {
        var snapshot = DebugGauntletScenario.lastPack.snapshot
        snapshot.run.cash = 0
        let state = seed(snapshot)
        try settleLastPack(state)
        XCTAssertEqual(state.phase, .lost)
        XCTAssertFalse(state.isLastChance)
    }

    func testLastPackWithEveryKeeperGradedStillLosesAutomatically() throws {
        var snapshot = DebugGauntletScenario.lastPack.snapshot
        snapshot.run.showcase[0].grade = 8
        let state = seed(snapshot)
        try settleLastPack(state)
        XCTAssertEqual(state.phase, .lost)
    }

    func testPlayerCanDeclineTheLastChanceAndStillBankMilestones() throws {
        var snapshot = DebugGauntletScenario.lastPack.snapshot
        snapshot.run.packsRipped = 6
        let state = seed(snapshot)
        try settleLastPack(state)
        state.endRound()
        XCTAssertEqual(state.phase, .lost)
        XCTAssertEqual(state.progress.stats[GauntletStat.packsRipped], 6)
        XCTAssertFalse(GauntletRunStore(directory: directory).hasSavedRun)
    }

    func testUnresolvedCatalystStillBlocksTheLastPackExit() throws {
        var snapshot = DebugGauntletScenario.lastPack.snapshot
        snapshot.pendingCatalyst = Catalyst.byId("eclipse")!
        let state = seed(snapshot)
        state.sell(try XCTUnwrap(state.pendingCards.first))
        state.finishReveal()
        XCTAssertTrue(state.revealActive)
        XCTAssertFalse(state.canEndRound)
        state.attunePendingCatalyst()
        state.finishReveal()
        XCTAssertFalse(state.isLastChance)
        XCTAssertTrue(state.canRip, "Eclipse immediately grants a real extra rip")
    }

    func testPendingCardCannotBeKeptSoldOrSwappedTwice() throws {
        let state = seed(DebugGauntletScenario.swap.snapshot)
        let card = try XCTUnwrap(state.pendingCards.first)
        state.swap(card, forShowcaseIndex: 5)
        let cash = state.run?.cash
        let showcase = state.run?.showcase
        state.swap(card, forShowcaseIndex: 0)
        state.keep(card)
        XCTAssertEqual(state.sell(card), 0)
        XCTAssertEqual(state.run?.cash, cash)
        XCTAssertEqual(state.run?.showcase, showcase)
    }

    func testRipsAndRoundResolutionCannotRunBehindTheRevealOrInsideTheShop() throws {
        let state = seed(DebugGauntletScenario.swap.snapshot)
        for card in state.pendingCards { state.sell(card) }
        let before = try XCTUnwrap(state.run)
        XCTAssertFalse(state.canRip)
        XCTAssertFalse(state.canEndRound)
        state.rip()
        state.endRound()
        XCTAssertEqual(state.run?.round, before.round)
        XCTAssertEqual(state.run?.ripsLeft, before.ripsLeft)
        state.finishReveal()
        XCTAssertTrue(state.canRip)
        XCTAssertFalse(state.buySlot(), "shop upgrades stay shop-only")

        let shop = seed(DebugGauntletScenario.shop.snapshot)
        XCTAssertFalse(shop.canRip)
        XCTAssertFalse(shop.canEndRound)
        shop.rip()
        shop.endRound()
        XCTAssertEqual(shop.phase, .shop)
        XCTAssertEqual(shop.run?.round, 2)
    }
}
