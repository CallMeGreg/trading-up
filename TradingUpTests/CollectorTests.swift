import XCTest
@testable import TradingUp

final class CollectorTests: XCTestCase {
    private func request(_ collector: Collector, core: GameCore, set: Int = 1) throws -> CollectorDeal {
        try XCTUnwrap(core.collectorRequests(inSet: set).first { $0.collector == collector })
    }

    private func supply(_ deal: CollectorDeal, to core: inout GameCore) {
        for requirement in deal.requirements {
            for id in requirement.cardIDs.sorted().prefix(requirement.count) {
                if !core.owns(id) { core.instances.append(CardInstance(cardId: id)) }
                core.instances.append(CardInstance(cardId: id))
            }
        }
    }

    func testFreshBoardIsFiniteStableAndProgressionGated() throws {
        let core = GameCore()
        let offers = core.collectorRequests(inSet: 1)
        XCTAssertEqual(offers.map(\.collector), [.mira, .rowan])
        XCTAssertEqual(offers.map(\.sequence), [1, 1])
        XCTAssertEqual(offers.map(\.total), [3, 3])
        XCTAssertEqual(core.collectorRequests(inSet: 1).map(\.id), offers.map(\.id))
        XCTAssertTrue(core.collectorRequests(inSet: 2).isEmpty)
        XCTAssertTrue(core.collectorRequests(inSet: 0).isEmpty)
        XCTAssertNil(core.collectorDeal(for: .request("1-mira-1")), "later requests cannot be claimed early")
        XCTAssertEqual(core.collectorTradesRemaining(inSet: 1), CollectorEconomy.tradesPerSet)
    }

    func testRequestSuppliesOnlyNormalDuplicatesAndKeepsBestCopy() throws {
        var core = GameCore()
        let offer = try request(.mira, core: core)
        supply(offer, to: &core)
        let cardID = try XCTUnwrap(offer.requirements.first?.cardIDs.sorted().first)
        let foil = CardInstance(cardId: cardID, foil: true)
        let graded = CardInstance(cardId: cardID, grade: 2)
        core.instances += [foil, graded]
        let before = core.uniqueOwnedIds
        let preview = try XCTUnwrap(core.collectorPreview(for: offer.goal))
        XCTAssertTrue(preview.isReady)
        XCTAssertEqual(preview.supplied.count, offer.requiredCount)
        XCTAssertTrue(preview.supplied.allSatisfy { !$0.foil && $0.grade == nil })
        let cash = core.cash
        let receipt = try core.completeCollectorDeal(offer.goal, expectedInstanceIDs: preview.suppliedIDs)
        XCTAssertEqual(core.cash, cash + offer.cashReward, accuracy: 0.001)
        XCTAssertEqual(core.uniqueOwnedIds, before)
        XCTAssertTrue(core.instances.contains(foil))
        XCTAssertTrue(core.instances.contains(graded))
        XCTAssertNil(receipt.received)
        XCTAssertEqual(core.collectors.requestsCompleted, 1)
        XCTAssertEqual(core.stats.cardsPulled, 0)
    }

    func testLastCopiesAndPremiumExtrasCannotFillRequests() throws {
        var core = GameCore()
        let offer = try request(.mira, core: core)
        for id in offer.requirements[0].cardIDs.sorted().prefix(3) {
            core.instances += [CardInstance(cardId: id), CardInstance(cardId: id, foil: true),
                               CardInstance(cardId: id, grade: 10)]
        }
        // A normal copy is a spare when the higher-value foil/grade is the keeper.
        XCTAssertTrue(try XCTUnwrap(core.collectorPreview(for: offer.goal)).isReady)
        core.instances.removeAll { !$0.foil && $0.grade == nil }
        let preview = try XCTUnwrap(core.collectorPreview(for: offer.goal))
        XCTAssertFalse(preview.isReady)
        XCTAssertTrue(preview.supplied.isEmpty)
        XCTAssertThrowsError(try core.completeCollectorDeal(offer.goal, expectedInstanceIDs: [])) {
            XCTAssertEqual($0 as? CollectorError, .missingCopies)
        }
    }

    func testDifferentCommonsReallyRequireDifferentIdentities() throws {
        var core = GameCore()
        let offer = try request(.mira, core: core)
        let id = try XCTUnwrap(offer.requirements[0].cardIDs.sorted().first)
        core.instances = (0..<10).map { _ in CardInstance(cardId: id) }
        let preview = try XCTUnwrap(core.collectorPreview(for: offer.goal))
        XCTAssertEqual(preview.collectedCount, 1)
        XCTAssertFalse(preview.isReady)
    }

    func testTrackingProtectsBulkSaleAndGradingUntilReleased() throws {
        var core = GameCore()
        let offer = try request(.mira, core: core)
        supply(offer, to: &core)
        try core.setCollectorGoalTracked(offer.goal, tracked: true)
        let reserved = core.collectorReservedInstanceIDs
        XCTAssertEqual(reserved.count, 3)
        XCTAssertEqual(core.duplicateSummary(of: core.uniqueOwnedIds).count, 0)
        XCTAssertEqual(core.sellDuplicates(of: core.uniqueOwnedIds).count, 0)
        var rng = SeededRNG(4)
        for id in reserved {
            XCTAssertNil(core.sell(instanceId: id))
            XCTAssertNil(core.grade(instanceId: id, using: &rng))
        }
        try core.setCollectorGoalTracked(offer.goal, tracked: false)
        XCTAssertTrue(core.collectorReservedInstanceIDs.isEmpty)
        XCTAssertEqual(core.sellDuplicates(of: core.uniqueOwnedIds).count, 3)
        XCTAssertNotNil(core.collectorDeal(for: offer.goal), "untracking must not discard the offer")
    }

    func testTrackingCapsAtTwoAndSharedCopiesAreNotDoubleCounted() throws {
        var core = GameCore()
        let mira = try request(.mira, core: core)
        let rowan = try request(.rowan, core: core)
        supply(mira, to: &core)
        supply(rowan, to: &core)
        try core.setCollectorGoalTracked(mira.goal, tracked: true)
        try core.setCollectorGoalTracked(rowan.goal, tracked: true)
        let previews = core.collectorTrackedPreviews
        XCTAssertEqual(previews.count, 2)
        XCTAssertTrue(previews[0].suppliedIDs.isDisjoint(with: previews[1].suppliedIDs))
        XCTAssertThrowsError(try core.setCollectorGoalTracked(.trade("S1-050"), tracked: true)) {
            XCTAssertEqual($0 as? CollectorError, .trackingFull)
        }
        try core.setCollectorGoalTracked(mira.goal, tracked: true)
        XCTAssertEqual(core.collectors.trackedGoals.count, 2, "tracking twice is idempotent")
    }

    func testStaleConfirmationAndDoubleSubmissionAreAtomic() throws {
        var core = GameCore()
        let offer = try request(.mira, core: core)
        supply(offer, to: &core)
        let preview = try XCTUnwrap(core.collectorPreview(for: offer.goal))
        let cash = core.cash
        let instances = core.instances
        XCTAssertThrowsError(try core.completeCollectorDeal(offer.goal, expectedInstanceIDs: [UUID()])) {
            XCTAssertEqual($0 as? CollectorError, .changedOffer)
        }
        XCTAssertEqual(core.cash, cash)
        XCTAssertEqual(core.instances, instances)
        _ = try core.completeCollectorDeal(offer.goal, expectedInstanceIDs: preview.suppliedIDs)
        let afterCash = core.cash
        let afterInstances = core.instances
        XCTAssertThrowsError(try core.completeCollectorDeal(offer.goal, expectedInstanceIDs: preview.suppliedIDs))
        XCTAssertEqual(core.cash, afterCash)
        XCTAssertEqual(core.instances, afterInstances)
        XCTAssertEqual(try request(.mira, core: core).sequence, 2)
    }

    func testEachCollectorHasOnlyThreeRequestsPerSet() throws {
        var core = GameCore()
        for _ in 0..<CollectorEconomy.requestsPerCollector {
            let offer = try request(.mira, core: core)
            supply(offer, to: &core)
            let preview = try XCTUnwrap(core.collectorPreview(for: offer.goal))
            _ = try core.completeCollectorDeal(offer.goal, expectedInstanceIDs: preview.suppliedIDs)
        }
        XCTAssertFalse(core.collectorRequests(inSet: 1).contains { $0.collector == .mira })
        XCTAssertEqual(core.collectors.requestsCompleted, 3)
    }

    func testNamedTradeAwardsAnUngradedNormalMissingCard() throws {
        var core = GameCore()
        let goal = CollectorGoal.trade("S1-050")
        let deal = try XCTUnwrap(core.collectorDeal(for: goal))
        supply(deal, to: &core)
        _ = core.checkBonuses()
        let before = core.uniqueCount
        let preview = try XCTUnwrap(core.collectorPreview(for: goal))
        let receipt = try core.completeCollectorDeal(goal, expectedInstanceIDs: preview.suppliedIDs)
        XCTAssertEqual(receipt.received?.cardId, "S1-050")
        XCTAssertEqual(receipt.received?.foil, false)
        XCTAssertNil(receipt.received?.grade)
        XCTAssertEqual(core.uniqueCount, before + 1)
        XCTAssertEqual(core.stats.cardsPulled, 0, "trades are not pack pulls")
        XCTAssertEqual(core.collectorTradesRemaining(inSet: 1), CollectorEconomy.tradesPerSet - 1)
        XCTAssertNil(core.collectorDeal(for: goal), "already-owned cards are not trade targets")
    }

    func testTradeLimitCannotBeBypassedWithANewTarget() {
        var core = GameCore()
        core.collectors.tradesCompletedBySet[1] = CollectorEconomy.tradesPerSet
        XCTAssertTrue(core.collectorTradeTargets(inSet: 1).isEmpty)
        XCTAssertNil(core.collectorDeal(for: .trade("S1-050")))
    }

    func testTradeCompletesAnEvolutionFamilyAndPaysOnlyOnce() throws {
        var core = GameCore()
        let goal = CollectorGoal.trade("S1-003")
        let deal = try XCTUnwrap(core.collectorDeal(for: goal))
        supply(deal, to: &core)
        _ = core.checkBonuses()
        let card = try XCTUnwrap(deal.rewardCard)
        XCTAssertTrue(CardDatabase.line(card.lineId).filter { $0.id != card.id }.allSatisfy { core.owns($0.id) })
        let preview = try XCTUnwrap(core.collectorPreview(for: goal))
        let before = core.cash
        let receipt = try core.completeCollectorDeal(goal, expectedInstanceIDs: preview.suppliedIDs)
        XCTAssertEqual(receipt.bonuses.filter { $0.lineId == card.lineId }.count, 1)
        XCTAssertEqual(core.cash, before + Economy.evolutionBonus(set: card.set, stageCount: card.stageCount), accuracy: 0.001)
        XCTAssertTrue(core.checkBonuses().isEmpty)
    }

    func testPullingTrackedTradeTargetReleasesReservations() throws {
        var core = GameCore()
        let goal = CollectorGoal.trade("S1-050")
        supply(try XCTUnwrap(core.collectorDeal(for: goal)), to: &core)
        try core.setCollectorGoalTracked(goal, tracked: true)
        XCTAssertFalse(core.collectorReservedInstanceIDs.isEmpty)
        core.instances.append(CardInstance(cardId: "S1-050"))
        _ = core.checkBonuses()
        XCTAssertTrue(core.collectors.trackedGoals.isEmpty)
        XCTAssertTrue(core.collectorReservedInstanceIDs.isEmpty)
        XCTAssertEqual(core.collectorTradesRemaining(inSet: 1), CollectorEconomy.tradesPerSet)
    }

    func testReadyCollectorDealPreventsPrematureBankruptcy() throws {
        var core = GameCore()
        supply(try request(.rowan, core: core), to: &core)
        core.cash = 0
        XCTAssertLessThan(core.maxRaisableCash, Economy.cheapestPackPrice)
        XCTAssertFalse(core.isGameOver)
        let preview = try XCTUnwrap(core.collectorPreview(for: request(.rowan, core: core).goal))
        _ = try core.completeCollectorDeal(preview.deal.goal, expectedInstanceIDs: preview.suppliedIDs)
        XCTAssertGreaterThanOrEqual(core.cash, Economy.cheapestPackPrice)
    }

    func testSaveRoundTripAndLegacyDefaultsPreserveProgress() throws {
        var core = GameCore()
        let offer = try request(.mira, core: core)
        supply(offer, to: &core)
        try core.setCollectorGoalTracked(offer.goal, tracked: true)
        let encoded = try JSONEncoder().encode(SaveFile(core: core))
        let restored = try JSONDecoder().decode(SaveFile.self, from: encoded).core
        XCTAssertEqual(restored.collectors, core.collectors)
        XCTAssertEqual(restored.collectorReservedInstanceIDs, core.collectorReservedInstanceIDs)
        XCTAssertEqual(restored.instances, core.instances)
        let legacy = try JSONDecoder().decode(GameCore.self, from: Data(#"{"cash":42,"instances":[{"cardId":"S1-001"}]}"#.utf8))
        XCTAssertEqual(legacy.cash, 42)
        XCTAssertTrue(legacy.owns("S1-001"))
        XCTAssertEqual(legacy.collectors, CollectorProgress())
        XCTAssertEqual(try JSONDecoder().decode(CollectorProgress.self, from: Data("{}".utf8)), CollectorProgress())
    }

    func testNewRunResetsDealsButNotLifetimeRecord() throws {
        var core = GameCore()
        core.stats.packsOpened = 8
        let goal = try request(.mira, core: core).goal
        try core.setCollectorGoalTracked(goal, tracked: true)
        core.collectors.tradesCompletedBySet[1] = 2
        let fresh = core.startingNewRun()
        XCTAssertEqual(fresh.collectors, CollectorProgress())
        XCTAssertEqual(fresh.lifetime.packsOpened, 8)
    }

    func testSanitizerReleasesInvalidDuplicateAndOverflowGoals() {
        var core = GameCore()
        core.collectors.trackedGoals = [.request("retired"), .trade("S1-050"),
                                       .trade("S1-050"), .trade("S1-049"), .trade("S1-048")]
        let clean = core.sanitized().core
        XCTAssertEqual(clean.collectors.trackedGoals, [.trade("S1-050"), .trade("S1-049")])
    }
}

@MainActor
final class CollectorStateTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("tu_collectors_\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func game(finalCard: Bool = false) -> GameState {
        GameState(core: DebugLaunchState.collectorScenario(finalCard: finalCard),
                  store: SaveStore(directory: directory))
    }

    func testTrackingAndDealsPersistAcrossRelaunch() throws {
        let state = game()
        let goal = try XCTUnwrap(state.collectorRequests(inSet: 1).first?.goal)
        try state.setCollectorGoalTracked(goal, tracked: true)
        let loaded = GameState(store: SaveStore(directory: directory))
        XCTAssertEqual(loaded.collectorProgress.trackedGoals, [goal])
        let preview = try XCTUnwrap(loaded.collectorPreview(for: goal))
        _ = try loaded.completeCollectorDeal(goal, expectedInstanceIDs: preview.suppliedIDs)
        XCTAssertEqual(GameState(store: SaveStore(directory: directory)).collectorProgress.requestsCompleted, 1)
    }

    func testPaidDealsAreBlockedAndUntrackingRemainsAvailable() throws {
        var core = DebugLaunchState.collectorScenario(finalCard: true)
        let paid = try XCTUnwrap(core.collectorRequests(inSet: 2).first?.goal)
        try core.setCollectorGoalTracked(paid, tracked: true)
        let state = GameState(core: core, store: SaveStore(directory: directory))
        XCTAssertThrowsError(try state.setCollectorGoalTracked(paid, tracked: true)) {
            XCTAssertEqual($0 as? CollectorError, .lockedSet)
        }
        XCTAssertThrowsError(try state.completeCollectorDeal(paid, expectedInstanceIDs: [])) {
            XCTAssertEqual($0 as? CollectorError, .lockedSet)
        }
        try state.setCollectorGoalTracked(paid, tracked: false)
        XCTAssertTrue(state.collectorProgress.trackedGoals.isEmpty)
    }

    func testInaccessiblePaidDealDoesNotStrandAFreeRun() throws {
        var core = GameCore()
        core.instances = CardDatabase.cards(inSet: 1).prefix(25).map { CardInstance(cardId: $0.id) }
        let paid = try XCTUnwrap(core.collectorRequests(inSet: 2).first { $0.collector == .rowan })
        for requirement in paid.requirements {
            let id = try XCTUnwrap(requirement.cardIDs.first)
            core.instances += [CardInstance(cardId: id), CardInstance(cardId: id)]
        }
        _ = core.checkBonuses()
        core.cash = 0
        XCTAssertLessThan(core.maxRaisableCash, Economy.cheapestPackPrice)
        XCTAssertFalse(core.isGameOver, "the full game has a paying collector action")
        let state = GameState(core: core, store: SaveStore(directory: directory))
        XCTAssertTrue(state.isGameOver, "an inaccessible paid request cannot prevent the free game's loss")
        state.setFullVersionUnlocked(true)
        XCTAssertFalse(state.isGameOver)
    }

    func testDealsWaitForPackSummaryAndReceiptDismissal() throws {
        let state = game()
        let goal = try XCTUnwrap(state.collectorRequests(inSet: 1).first?.goal)
        let preview = try XCTUnwrap(state.collectorPreview(for: goal))
        state.beginReveal()
        XCTAssertThrowsError(try state.completeCollectorDeal(goal, expectedInstanceIDs: preview.suppliedIDs)) {
            XCTAssertEqual($0 as? CollectorError, .finishPack)
        }
        state.endReveal()
        _ = try state.completeCollectorDeal(goal, expectedInstanceIDs: preview.suppliedIDs)
        XCTAssertTrue(state.collectorReceiptInFlight)
        XCTAssertThrowsError(try state.setCollectorGoalTracked(.trade("S1-050"), tracked: true)) {
            XCTAssertEqual($0 as? CollectorError, .finishDeal)
        }
        state.endCollectorReceipt()
        XCTAssertFalse(state.collectorReceiptInFlight)
    }

    func testFinalTradeRecordsBinderAndWaitsBeforeShowingWin() throws {
        let state = game(finalCard: true)
        let goal = CollectorGoal.trade("S1-050")
        let preview = try XCTUnwrap(state.collectorPreview(for: goal))
        XCTAssertTrue(preview.isReady)
        let receipt = try state.completeCollectorDeal(goal, expectedInstanceIDs: preview.suppliedIDs)
        XCTAssertTrue(state.hasWon)
        XCTAssertTrue(receipt.bonuses.contains { $0.kind == .set })
        XCTAssertTrue(state.binder.hasCard("S1-050"))
        XCTAssertFalse(state.presentsWin)
        state.endCollectorReceipt()
        XCTAssertTrue(state.presentsWin)
        let reloaded = GameState(store: SaveStore(directory: directory))
        XCTAssertTrue(reloaded.hasWon)
        XCTAssertTrue(reloaded.binder.hasCard("S1-050"))
        XCTAssertEqual(reloaded.collectorProgress.tradesCompleted, 1)
        state.newGame()
        XCTAssertTrue(state.binder.hasCard("S1-050"), "new runs never consume the permanent Binder")
        XCTAssertEqual(state.collectorProgress, CollectorProgress())
    }

    func testFailedSaveDoesNotConsumeCardsOrPayRewards() throws {
        let missingDirectory = directory.appendingPathComponent("does-not-exist")
        let state = GameState(core: DebugLaunchState.collectorScenario(finalCard: false),
                              store: SaveStore(directory: missingDirectory))
        let goal = try XCTUnwrap(state.collectorRequests(inSet: 1).first?.goal)
        let preview = try XCTUnwrap(state.collectorPreview(for: goal))
        let before = state.core.instances
        let cash = state.cash
        XCTAssertThrowsError(try state.completeCollectorDeal(goal, expectedInstanceIDs: preview.suppliedIDs)) {
            XCTAssertEqual($0 as? CollectorError, .couldNotSave)
        }
        XCTAssertEqual(state.core.instances, before)
        XCTAssertEqual(state.cash, cash)
        XCTAssertEqual(state.collectorProgress.requestsCompleted, 0)
        XCTAssertFalse(state.collectorReceiptInFlight)
        XCTAssertThrowsError(try state.setCollectorGoalTracked(goal, tracked: true))
        XCTAssertTrue(state.collectorProgress.trackedGoals.isEmpty)
    }
}
