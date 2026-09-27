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

    private func assertFreshProgress(_ progress: CollectorProgress,
                                     file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(progress.completedRequestIDs.isEmpty, file: file, line: line)
        XCTAssertTrue(progress.tradesCompletedBySet.isEmpty, file: file, line: line)
        XCTAssertEqual(progress.cashEarned, 0, file: file, line: line)
        XCTAssertEqual(progress.familyLineIDsBySet.count, CardDatabase.setCount, file: file, line: line)
        for ids in progress.familyLineIDsBySet.values {
            XCTAssertEqual(ids.count, 3, file: file, line: line)
            XCTAssertEqual(Set(ids).count, 3, file: file, line: line)
        }
    }

    func testStarterProgressionPaysMoreThanEveryPossibleSaleBundleInEverySet() throws {
        var core = GameCore()
        core.instances = CardDatabase.all.map { CardInstance(cardId: $0.id) }
        _ = core.checkBonuses()
        let expected: [(Rarity, Int, Double)] = [(.common, 5, 0.5), (.uncommon, 4, 0.75), (.rare, 3, 1)]
        for set in 1...CardDatabase.setCount {
            for (step, (rarity, count, multiplier)) in expected.enumerated() {
                let offer = try request(.mira, core: core, set: set)
                let requirement = try XCTUnwrap(offer.requirements.first)
                XCTAssertEqual(offer.sequence, step + 1)
                XCTAssertEqual(offer.requirements.count, 1)
                XCTAssertEqual(requirement.rarity, rarity)
                XCTAssertEqual(requirement.count, count)
                XCTAssertTrue(requirement.distinct)
                let cards = CardDatabase.cards(inSet: set).filter { $0.rarity == rarity }
                XCTAssertEqual(requirement.cardIDs, Set(cards.map(\.id)))
                let mostValuable = cards.sorted { $0.baseValue > $1.baseValue }.prefix(count)
                let maximumSale = mostValuable.reduce(0) { $0 + Economy.sellback($1.baseValue) }
                XCTAssertEqual(offer.cashReward, Economy.packPrice(set: set) * multiplier)
                XCTAssertGreaterThan(offer.cashReward, maximumSale, "set \(set), \(rarity)")
                core.instances += mostValuable.map { CardInstance(cardId: $0.id) }
                let preview = try XCTUnwrap(core.collectorPreview(for: offer.goal))
                XCTAssertTrue(preview.isReady)
                XCTAssertEqual(preview.supplied.reduce(0) { $0 + $1.sellValue }, maximumSale, accuracy: 0.001)
                let cash = core.cash
                _ = try core.completeCollectorDeal(offer.goal, expectedInstanceIDs: preview.suppliedIDs)
                XCTAssertEqual(core.cash - cash, offer.cashReward, accuracy: 0.001)
            }
            XCTAssertFalse(core.collectorRequests(inSet: set).contains { $0.collector == .mira })
        }
    }

    func testFamilyRequestsStayStableAcrossPreviewsSavesAndCompletionsWithoutRepeats() throws {
        var rng = SeededRNG(42)
        var core = GameCore(collectors: CollectorProgress(using: &rng))
        core.instances = CardDatabase.all.map { CardInstance(cardId: $0.id) }
        _ = core.checkBonuses()
        var seen: Set<String> = []
        for set in 1...CardDatabase.setCount {
            for step in 0..<CollectorEconomy.requestsPerCollector {
                let offer = try request(.rowan, core: core, set: set)
                let ids = offer.requirements.map(\.id)
                let firstCard = try XCTUnwrap(offer.requirements.first?.card)
                XCTAssertTrue(seen.insert(firstCard.lineId).inserted)
                XCTAssertEqual(firstCard.set, set)
                XCTAssertEqual(offer.sequence, step + 1)
                XCTAssertEqual(ids, CardDatabase.line(firstCard.lineId).prefix(2).map(\.id))
                XCTAssertEqual(offer.cashReward, Economy.packPrice(set: set))
                XCTAssertEqual(core.collectorDeal(for: offer.goal)?.requirements.map(\.id), ids)
                XCTAssertEqual(core.collectorPreview(for: offer.goal)?.deal.requirements.map(\.id), ids)
                let data = try JSONEncoder().encode(SaveFile(core: core))
                core = try JSONDecoder().decode(SaveFile.self, from: data).core
                XCTAssertEqual(try request(.rowan, core: core, set: set).requirements.map(\.id), ids)
                supply(offer, to: &core)
                let preview = try XCTUnwrap(core.collectorPreview(for: offer.goal))
                _ = try core.completeCollectorDeal(offer.goal, expectedInstanceIDs: preview.suppliedIDs)
                XCTAssertNil(core.collectorDeal(for: offer.goal))
            }
            XCTAssertFalse(core.collectorRequests(inSet: set).contains { $0.collector == .rowan })
        }
        XCTAssertEqual(seen.count, CardDatabase.setCount * CollectorEconomy.requestsPerCollector)
    }

    func testEveryEvolutionFamilyHasEqualChanceAtEveryRequestPosition() {
        let trials = 13_000
        var rng = SeededRNG(0xC011EC70)
        var counts: [String: Int] = [:]
        for _ in 0..<trials {
            let progress = CollectorProgress(using: &rng)
            for (set, ids) in progress.familyLineIDsBySet {
                XCTAssertEqual(Set(ids).count, 3)
                for (step, id) in ids.enumerated() {
                    XCTAssertEqual(CardDatabase.evolutionLines[id]?.first?.set, set)
                    counts["\(step):\(id)", default: 0] += 1
                }
            }
        }
        for set in 1...CardDatabase.setCount {
            let lines = CardDatabase.evolutionLines.values.filter { $0.first?.set == set }
            XCTAssertEqual(lines.count, 13, "both two- and three-stage families participate")
            let expected = Double(trials) / Double(lines.count)
            for line in lines {
                for step in 0..<CollectorEconomy.requestsPerCollector {
                    XCTAssertEqual(Double(counts["\(step):\(line[0].lineId)", default: 0]),
                                   expected, accuracy: expected * 0.15)
                }
            }
        }
    }

    func testSeededFamilySelectionIsReproducibleAndNewRunsReshuffle() {
        var firstRNG = SeededRNG(42)
        var secondRNG = SeededRNG(42)
        let core = GameCore(collectors: CollectorProgress(using: &firstRNG))
        XCTAssertEqual(core.collectors, CollectorProgress(using: &secondRNG))
        XCTAssertNotEqual(core.collectors.familyLineIDsBySet,
                          core.startingNewRun().collectors.familyLineIDsBySet)
    }

    func testInvalidPersistedFamilySchedulesAreRejectedRatherThanRerolled() throws {
        let original = try JSONEncoder().encode(CollectorProgress())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        let valid = try XCTUnwrap(object["familyLineIDsBySet"] as? [String: [String]])
        for badIDs in [Array(repeating: valid["1"]![0], count: 3),
                       Array(valid["1"]!.prefix(2)), valid["2"]!, ["missing", "unknown", "retired"]] {
            var invalid = valid
            invalid["1"] = badIDs
            object["familyLineIDsBySet"] = invalid
            let data = try JSONSerialization.data(withJSONObject: object)
            XCTAssertThrowsError(try JSONDecoder().decode(CollectorProgress.self, from: data))
        }
    }

    func testCollectorDisplayNamesKeepPersistedIdentifiersStable() {
        XCTAssertEqual(Collector.allCases.map(\.name), ["Matthew", "Emilie", "Jonny"])
        XCTAssertEqual(Collector.allCases.map(\.rawValue), ["mira", "rowan", "tess"])
        XCTAssertEqual(GameCore().collectorRequests(inSet: 1).map(\.id),
                       ["request:1-mira-0", "request:1-rowan-0"])
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
        XCTAssertEqual(core.collectors.cashEarned, offer.cashReward)
        XCTAssertEqual(core.lifetimeIncludingCurrentRun.collectorRequestsCompleted, 1)
        XCTAssertEqual(core.lifetimeIncludingCurrentRun.collectorCashEarned, offer.cashReward)
        XCTAssertEqual(core.stats.cardsPulled, 0)
    }

    func testLastCopiesAndPremiumExtrasCannotFillRequests() throws {
        var core = GameCore()
        let offer = try request(.mira, core: core)
        for id in offer.requirements[0].cardIDs.sorted().prefix(offer.requiredCount) {
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

    func testPreviewsDoNotReserveSparesFromSellingOrGrading() throws {
        var core = GameCore()
        let offer = try request(.mira, core: core)
        supply(offer, to: &core)
        let preview = try XCTUnwrap(core.collectorPreview(for: offer.goal))
        XCTAssertEqual(preview.supplied.count, 5)
        XCTAssertTrue(preview.supplied.allSatisfy { core.isSellable($0) })
        XCTAssertEqual(core.duplicateSummary(of: core.uniqueOwnedIds).count, 5)
        var selling = core
        XCTAssertEqual(selling.sellDuplicates(of: selling.uniqueOwnedIds).count, 5)
        XCTAssertEqual(selling.uniqueOwnedIds, core.uniqueOwnedIds)
        var rng = SeededRNG(4)
        for id in preview.suppliedIDs {
            XCTAssertNotNil(core.grade(instanceId: id, using: &rng))
        }
        XCTAssertNotNil(core.collectorDeal(for: offer.goal), "previewing never consumes an offer")
    }

    func testIndependentOffersCannotSpendTheSameCopyTwice() throws {
        var core = GameCore()
        let mira = try request(.mira, core: core)
        let rowan = try request(.rowan, core: core)
        supply(rowan, to: &core)
        let familyBase = try XCTUnwrap(rowan.requirements.first?.card?.id)
        core.instances.append(CardInstance(cardId: familyBase))
        for id in mira.requirements[0].cardIDs.sorted().filter({ $0 != familyBase }).prefix(mira.requiredCount - 1) {
            core.instances += [CardInstance(cardId: id), CardInstance(cardId: id)]
        }
        let first = try XCTUnwrap(core.collectorPreview(for: mira.goal))
        let second = try XCTUnwrap(core.collectorPreview(for: rowan.goal))
        XCTAssertFalse(first.suppliedIDs.isDisjoint(with: second.suppliedIDs))
        let disjoint = try XCTUnwrap(core.collectorPreview(for: rowan.goal, excluding: first.suppliedIDs))
        XCTAssertTrue(first.suppliedIDs.isDisjoint(with: disjoint.suppliedIDs))
        _ = try core.completeCollectorDeal(mira.goal, expectedInstanceIDs: first.suppliedIDs)
        let before = core.instances
        XCTAssertThrowsError(try core.completeCollectorDeal(rowan.goal, expectedInstanceIDs: second.suppliedIDs)) {
            XCTAssertEqual($0 as? CollectorError, .changedOffer)
        }
        XCTAssertEqual(core.instances, before)
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
        XCTAssertEqual(core.collectors.requestsCompleted, 1)
        XCTAssertEqual(core.collectors.cashEarned, offer.cashReward, "failed confirmations never inflate stats")
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
        XCTAssertEqual(core.collectors.tradesCompleted, 1)
        XCTAssertEqual(core.lifetimeIncludingCurrentRun.collectorTradesCompleted, 1)
        XCTAssertEqual(core.collectors.cashEarned, 0, "trade bonuses are not request earnings")
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

    func testPullingTradeTargetRemovesOfferWithoutSpendingTrade() throws {
        var core = GameCore()
        let goal = CollectorGoal.trade("S1-050")
        supply(try XCTUnwrap(core.collectorDeal(for: goal)), to: &core)
        XCTAssertNotNil(core.collectorPreview(for: goal))
        let duplicates = core.duplicateSummary(of: core.uniqueOwnedIds).count
        core.instances.append(CardInstance(cardId: "S1-050"))
        _ = core.checkBonuses()
        XCTAssertNil(core.collectorPreview(for: goal))
        XCTAssertEqual(core.duplicateSummary(of: core.uniqueOwnedIds).count, duplicates)
        XCTAssertEqual(core.collectorTradesRemaining(inSet: 1), CollectorEconomy.tradesPerSet)
    }

    func testReadyCountIncludesTessOnceWithoutSelectingATarget() throws {
        var core = GameCore()
        XCTAssertEqual(core.collectorReadyCount(inSet: 1), 0)
        supply(try XCTUnwrap(core.collectorDeal(for: .trade("S1-050"))), to: &core)
        XCTAssertGreaterThan(core.collectorTradeTargets(inSet: 1).count, 1)
        let requests = core.collectorRequests(inSet: 1).filter {
            core.collectorPreview(for: $0.goal)?.isReady == true
        }.count
        XCTAssertEqual(core.collectorReadyCount(inSet: 1), requests + 1)
        XCTAssertEqual(core.collectorReadyCount(inSet: 2), 0)
        XCTAssertEqual(core.collectorReadyCount(inSet: 0), 0)
        core.collectors.tradesCompletedBySet[1] = CollectorEconomy.tradesPerSet
        XCTAssertEqual(core.collectorReadyCount(inSet: 1), requests)
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
        let preview = try XCTUnwrap(core.collectorPreview(for: offer.goal))
        _ = try core.completeCollectorDeal(offer.goal, expectedInstanceIDs: preview.suppliedIDs)
        let encoded = try JSONEncoder().encode(SaveFile(core: core))
        let restored = try JSONDecoder().decode(SaveFile.self, from: encoded).core
        XCTAssertEqual(restored.collectors, core.collectors)
        XCTAssertEqual(restored.collectors.cashEarned, offer.cashReward)
        XCTAssertEqual(restored.instances, core.instances)
        let legacy = try JSONDecoder().decode(GameCore.self, from: Data(#"{"cash":42,"instances":[{"cardId":"S1-001"}]}"#.utf8))
        XCTAssertEqual(legacy.cash, 42)
        XCTAssertTrue(legacy.owns("S1-001"))
        assertFreshProgress(legacy.collectors)
        let legacyProgress = try JSONDecoder().decode(CollectorProgress.self, from: Data("{}".utf8))
        assertFreshProgress(legacyProgress)
        XCTAssertEqual(legacy.collectors, legacyProgress, "saves predating collectors keep a stable legacy schedule")
        XCTAssertEqual(try JSONDecoder().decode(GameCore.self, from: Data("{}".utf8)).collectors, legacyProgress)
        for set in 1...CardDatabase.setCount {
            let oldLines = CardDatabase.evolutionLines.values.filter { $0.first?.set == set && $0.count == 3 }
                .sorted { $0[0].id < $1[0].id }.prefix(3).map { $0[0].lineId }
            XCTAssertEqual(legacyProgress.familyLineIDsBySet[set], oldLines)
        }
    }

    func testNewRunResetsDealsButNotLifetimeRecord() throws {
        var core = GameCore()
        core.stats.packsOpened = 8
        let offer = try request(.mira, core: core)
        supply(offer, to: &core)
        let preview = try XCTUnwrap(core.collectorPreview(for: offer.goal))
        _ = try core.completeCollectorDeal(offer.goal, expectedInstanceIDs: preview.suppliedIDs)
        core.collectors.tradesCompletedBySet[1] = 2
        let fresh = core.startingNewRun()
        assertFreshProgress(fresh.collectors)
        XCTAssertEqual(fresh.lifetime.packsOpened, 8)
        XCTAssertEqual(fresh.lifetime.collectorRequestsCompleted, 1)
        XCTAssertEqual(fresh.lifetime.collectorTradesCompleted, 2)
        XCTAssertEqual(fresh.lifetime.collectorCashEarned, offer.cashReward)
        XCTAssertEqual(fresh.lifetimeIncludingCurrentRun.collectorTradesCompleted, 2,
                       "display-time totals must not double-count the previous run")
    }

    func testLegacyTrackingMetadataIsIgnoredAndRequestEarningsAreRecovered() throws {
        let data = Data(#"""
        {
          "cash":42,
          "instances":[{"cardId":"S1-001"},{"cardId":"S1-001"}],
          "collectors":{
            "completedRequestIDs":["1-mira-0","1-rowan-0"],
            "tradesCompletedBySet":{"1":1},
            "trackedGoals":[{"request":{"_0":"1-mira-1"}},{"trade":{"_0":"S1-050"}}]
          }
        }
        """#.utf8)
        var core = try JSONDecoder().decode(GameCore.self, from: data).sanitized().core
        XCTAssertEqual(core.cash, 42)
        XCTAssertEqual(core.collectors.requestsCompleted, 2)
        XCTAssertEqual(core.collectors.tradesCompleted, 1)
        XCTAssertEqual(core.collectors.cashEarned, Economy.packPrice(set: 1) * 1.5)
        XCTAssertEqual(core.lifetimeIncludingCurrentRun.collectorRequestsCompleted, 2)
        XCTAssertEqual(core.lifetimeIncludingCurrentRun.collectorTradesCompleted, 1)
        let nextFamily = try request(.rowan, core: core)
        XCTAssertEqual(nextFamily.requirements.map(\.id), ["S1-004", "S1-005"])
        XCTAssertEqual(nextFamily.sequence, 2)
        let restored = try JSONDecoder().decode(GameCore.self, from: JSONEncoder().encode(core))
        XCTAssertEqual(restored.collectors, core.collectors)
        XCTAssertEqual(core.sellDuplicates(of: ["S1-001"]).count, 1, "old goals cannot hold cards")
        XCTAssertEqual(core.count(of: "S1-001"), 1)
    }

    func testLegacyLaterRequestsRecoverOriginalRewardsNotNewPayouts() throws {
        let data = Data(#"""
        {"completedRequestIDs":["1-mira-0","1-mira-1","1-mira-2","1-rowan-0","1-rowan-1","1-rowan-2"]}
        """#.utf8)
        let progress = try JSONDecoder().decode(CollectorProgress.self, from: data)
        XCTAssertEqual(progress.cashEarned, Economy.packPrice(set: 1) * 4.5)
        XCTAssertEqual(progress.requestsCompleted, 6)
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

    func testDealsAndStatisticsPersistAcrossRelaunch() throws {
        let state = game()
        let goal = try XCTUnwrap(state.collectorRequests(inSet: 1).first?.goal)
        let preview = try XCTUnwrap(state.collectorPreview(for: goal))
        _ = try state.completeCollectorDeal(goal, expectedInstanceIDs: preview.suppliedIDs)
        let loaded = GameState(store: SaveStore(directory: directory))
        XCTAssertEqual(loaded.collectorProgress.familyLineIDsBySet, state.collectorProgress.familyLineIDsBySet)
        XCTAssertEqual(loaded.collectorRequests(inSet: 1).last?.requirements.map(\.id),
                       state.collectorRequests(inSet: 1).last?.requirements.map(\.id))
        XCTAssertEqual(loaded.collectorProgress.requestsCompleted, 1)
        XCTAssertEqual(loaded.collectorProgress.cashEarned, preview.deal.cashReward)
        XCTAssertEqual(loaded.lifetimeStats.collectorRequestsCompleted, 1)
        loaded.newGame()
        let reset = GameState(store: SaveStore(directory: directory))
        XCTAssertEqual(reset.collectorProgress.requestsCompleted, 0)
        XCTAssertEqual(reset.lifetimeStats.collectorRequestsCompleted, 1)
        XCTAssertEqual(reset.lifetimeStats.collectorCashEarned, preview.deal.cashReward)
    }

    func testPaidDealsAreBlockedAndNeverCountAsReady() throws {
        let core = DebugLaunchState.collectorScenario(finalCard: true)
        let paid = try XCTUnwrap(core.collectorRequests(inSet: 2).first?.goal)
        let state = GameState(core: core, store: SaveStore(directory: directory))
        XCTAssertThrowsError(try state.completeCollectorDeal(paid, expectedInstanceIDs: [])) {
            XCTAssertEqual($0 as? CollectorError, .lockedSet)
        }
        XCTAssertEqual(state.collectorReadyCount(inSet: 2), 0)
        XCTAssertEqual(state.collectorReadyCount, state.collectorReadyCount(inSet: 1))
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
        XCTAssertThrowsError(try state.completeCollectorDeal(.trade("S1-050"), expectedInstanceIDs: [])) {
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
        XCTAssertTrue(state.collectorProgress.completedRequestIDs.isEmpty)
        XCTAssertTrue(state.collectorProgress.tradesCompletedBySet.isEmpty)
        XCTAssertEqual(state.collectorProgress.cashEarned, 0)
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
        XCTAssertEqual(state.collectorProgress.cashEarned, 0)
        XCTAssertEqual(state.lifetimeStats.collectorRequestsCompleted, 0)
    }
}
