import XCTest
@testable import TradingUp

@MainActor
final class CollectionSaleTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("tu_collection_sale_\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    private func game(store: SaveStore? = nil) -> GameState {
        var core = GameCore()
        core.instances = [
            CardInstance(cardId: "S1-001"),
            CardInstance(cardId: "S1-001", foil: true),
            CardInstance(cardId: "S1-001", grade: 10),
            CardInstance(cardId: "S1-001", grade: 2),
            CardInstance(cardId: "S1-002"),
            CardInstance(cardId: "S2-001"),
            CardInstance(cardId: "S2-001")
        ]
        return GameState(core: core, store: store ?? SaveStore(directory: directory))
    }

    func testPreviewDoesNotMutateAndSaleKeepsCheapestCopiesAndOtherSets() throws {
        let state = game()
        let before = state.core.instances
        let cash = state.cash
        let best = try XCTUnwrap(before.first { $0.grade == 10 })
        let cheapest = try XCTUnwrap(before.first { $0.grade == 2 })
        let maximumProceeds = state.instances(of: "S1-001").reduce(0) { $0 + $1.sellValue } - cheapest.sellValue
        let otherSet = before.filter { $0.card.set == 2 }
        let preview = state.duplicateSalePreview(inSet: 1)
        XCTAssertEqual(state.core.instances, before, "opening or canceling a review never sells cards")
        XCTAssertEqual(state.cash, cash)
        XCTAssertEqual(preview.count, 3)
        XCTAssertFalse(preview.copies.contains(cheapest))
        XCTAssertTrue(preview.copies.contains(best), "the most valuable copy is sold, not retained")
        XCTAssertEqual(preview.proceeds, maximumProceeds, accuracy: 0.0001)
        XCTAssertTrue(preview.copies.contains { $0.foil }, "bulk selling includes premium extras")
        XCTAssertTrue(preview.copies.contains { $0.grade != nil })
        let result = try state.sellDuplicates(preview)
        XCTAssertEqual(result.count, preview.count)
        XCTAssertEqual(result.proceeds, preview.proceeds, accuracy: 0.0001)
        XCTAssertEqual(state.cash, cash + preview.proceeds, accuracy: 0.0001)
        XCTAssertEqual(state.instances(of: "S1-001"), [cheapest])
        XCTAssertEqual(state.binder.best(for: "S1-001"), best, "the permanent Binder still records the best copy")
        XCTAssertEqual(state.count(of: "S1-002"), 1)
        XCTAssertEqual(state.core.instances.filter { $0.card.set == 2 }, otherSet)
        XCTAssertEqual(state.stats.cardsSold, 3)
        XCTAssertEqual(state.stats.moneyEarned, preview.proceeds, accuracy: 0.0001)
        XCTAssertEqual(state.stats.peakSale, try XCTUnwrap(preview.copies.map(\.sellValue).max()), accuracy: 0.0001)
        let loaded = GameState(store: SaveStore(directory: directory))
        XCTAssertEqual(loaded.core.instances, state.core.instances)
        XCTAssertEqual(loaded.cash, state.cash)
        XCTAssertEqual(loaded.stats.cardsSold, 3)
        XCTAssertEqual(loaded.binder.best(for: "S1-001"), best)
    }

    func testEveryCardKeepsItsCheapestCopyIncludingTiesAndLowGradeFoils() throws {
        let copies = [
            CardInstance(cardId: "S1-001"),
            CardInstance(cardId: "S1-001", foil: true),
            CardInstance(cardId: "S1-001", grade: 10),
            CardInstance(cardId: "S1-002"),
            CardInstance(cardId: "S1-002", foil: true, grade: 2),
            CardInstance(cardId: "S1-002", grade: 10),
            CardInstance(cardId: "S1-003"),
            CardInstance(cardId: "S1-003"),
            CardInstance(cardId: "S1-003"),
            CardInstance(cardId: "S1-004", foil: true)
        ]
        let grouped = Dictionary(grouping: copies, by: \.cardId)
        var maximumProceeds = 0.0
        for owned in grouped.values {
            maximumProceeds += owned.reduce(0) { $0 + $1.sellValue }
                - (try XCTUnwrap(owned.map(\.sellValue).min()))
        }

        for order in [copies, Array(copies.reversed())] {
            var core = GameCore()
            core.instances = order
            let state = GameState(core: core, store: SaveStore(directory: directory))
            let cash = state.cash
            let preview = state.duplicateSalePreview(inSet: 1)
            XCTAssertEqual(preview.count, copies.count - grouped.count)
            XCTAssertEqual(preview.proceeds, maximumProceeds, accuracy: 0.0001)
            XCTAssertEqual(Set(preview.copies), Set(state.duplicateSalePreview(inSet: 1).copies))

            let result = try state.sellDuplicates(preview)
            XCTAssertEqual(result.proceeds, maximumProceeds, accuracy: 0.0001)
            XCTAssertEqual(state.cash, cash + maximumProceeds, accuracy: 0.0001)
            for (cardId, owned) in grouped {
                let remaining = state.instances(of: cardId)
                XCTAssertEqual(remaining.count, 1)
                XCTAssertEqual(try XCTUnwrap(remaining.first).sellValue,
                               try XCTUnwrap(owned.map(\.sellValue).min()), accuracy: 0.0001)
            }
        }
    }

    func testStaleOrRepeatedConfirmationCannotSellMoreCopies() throws {
        let state = game()
        let preview = state.duplicateSalePreview(inSet: 1)
        let extra = try XCTUnwrap(preview.copies.first)
        XCTAssertNotNil(state.sell(extra.id))
        let before = state.core.instances
        let cash = state.cash
        XCTAssertThrowsError(try state.sellDuplicates(preview)) {
            XCTAssertEqual($0 as? DuplicateSaleError, .collectionChanged)
        }
        XCTAssertEqual(state.core.instances, before)
        XCTAssertEqual(state.cash, cash)
        let fresh = state.duplicateSalePreview(inSet: 1)
        _ = try state.sellDuplicates(fresh)
        XCTAssertThrowsError(try state.sellDuplicates(fresh)) {
            XCTAssertEqual($0 as? DuplicateSaleError, .collectionChanged)
        }
        XCTAssertEqual(state.count(of: "S1-001"), 1)
    }

    func testGradingInvalidatesTheReviewedProceeds() throws {
        let state = game()
        let preview = state.duplicateSalePreview(inSet: 1)
        let ungraded = try XCTUnwrap(preview.copies.first { $0.grade == nil })
        XCTAssertNotNil(state.grade(ungraded.id))
        let cash = state.cash
        let before = state.core.instances
        XCTAssertThrowsError(try state.sellDuplicates(preview)) {
            XCTAssertEqual($0 as? DuplicateSaleError, .collectionChanged)
        }
        XCTAssertEqual(state.cash, cash)
        XCTAssertEqual(state.core.instances, before)
    }

    func testFailedSaveLeavesCardsCashAndStatsUntouched() throws {
        let state = game(store: SaveStore(directory: directory.appendingPathComponent("missing")))
        let before = state.core.instances
        let cash = state.cash
        XCTAssertThrowsError(try state.sellDuplicates(state.duplicateSalePreview(inSet: 1))) {
            XCTAssertEqual($0 as? DuplicateSaleError, .couldNotSave)
        }
        XCTAssertEqual(state.core.instances, before)
        XCTAssertEqual(state.cash, cash)
        XCTAssertEqual(state.stats.cardsSold, 0)
        XCTAssertEqual(state.stats.moneyEarned, 0)
    }

    func testEmptyAndInvalidSetsDoNotSellAnything() {
        let state = game()
        for set in [0, 3, CardDatabase.setCount + 1] {
            let preview = state.duplicateSalePreview(inSet: set)
            XCTAssertEqual(preview.count, 0)
            XCTAssertThrowsError(try state.sellDuplicates(preview)) {
                XCTAssertEqual($0 as? DuplicateSaleError, .unavailable)
            }
        }
        XCTAssertEqual(state.stats.cardsSold, 0)
    }

    func testOwnedPaidSetDuplicatesCanBeSoldWithoutAnEntitlement() throws {
        let state = game()
        XCTAssertTrue(state.requiresFullUnlock(set: 2))
        XCTAssertEqual(try state.sellDuplicates(state.duplicateSalePreview(inSet: 2)).count, 1)
        XCTAssertEqual(state.count(of: "S2-001"), 1)
        XCTAssertEqual(state.count(of: "S1-001"), 4)
    }

    func testSalesWaitForPackSummaryAndCollectorReceipt() throws {
        let state = GameState(core: DebugLaunchState.collectorScenario(finalCard: false),
                              store: SaveStore(directory: directory))
        let preview = state.duplicateSalePreview(inSet: 1)
        state.beginReveal()
        XCTAssertThrowsError(try state.sellDuplicates(preview)) {
            XCTAssertEqual($0 as? DuplicateSaleError, .finishAction)
        }
        state.endReveal()
        let goal = try XCTUnwrap(state.collectorRequests(inSet: 1).first?.goal)
        let offer = try XCTUnwrap(state.collectorPreview(for: goal))
        _ = try state.completeCollectorDeal(goal, expectedInstanceIDs: offer.suppliedIDs)
        XCTAssertThrowsError(try state.sellDuplicates(preview)) {
            XCTAssertEqual($0 as? DuplicateSaleError, .finishAction)
        }
        state.endCollectorReceipt()
        XCTAssertGreaterThan(try state.sellDuplicates(state.duplicateSalePreview(inSet: 1)).count, 0)
    }

    func testLossWaitsForTheSaleConfirmationToFinishDismissing() throws {
        let fee = Economy.gradeFee(set: 1)
        let card = try XCTUnwrap(CardDatabase.cards(inSet: 1).first {
            Economy.sellback($0.baseValue) + fee < Economy.cheapestPackPrice
                && Economy.sellback($0.baseValue * Economy.gradeMultiplier(1)) >= Economy.cheapestPackPrice
        })
        var core = GameCore()
        core.cash = fee
        core.instances = [CardInstance(cardId: card.id), CardInstance(cardId: card.id)]
        let state = GameState(core: core, store: SaveStore(directory: directory))
        XCTAssertFalse(state.isGameOver, "an optimistic grade can still rescue this position")
        state.beginDuplicateSaleReview()
        _ = try state.sellDuplicates(state.duplicateSalePreview(inSet: 1))
        XCTAssertTrue(state.isGameOver, "cashing out can give up the last grading rescue")
        XCTAssertFalse(state.presentsGameOver, "the ending must not compete with a dismissing confirmation")
        state.endDuplicateSaleReview()
        XCTAssertTrue(state.presentsGameOver)
    }
}
