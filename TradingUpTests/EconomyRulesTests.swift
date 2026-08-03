import XCTest
@testable import TradingUp

/// Deterministic economy-knob checks. The Monte Carlo pack-EV, grading-odds,
/// and full-game strategy simulations are intentionally left in
/// tools/verify/main.swift — they're slow and statistical, not a good fit for
/// a fast unit-test suite.
final class EconomyRulesTests: XCTestCase {
    func testPackPricesAndGradeFees() {
        XCTAssertEqual(Economy.packPrices, [10, 30, 75, 160, 400], "steeper pack prices")
        XCTAssertEqual(Economy.gradeFees, [2, 4, 6, 8, 10], "flat grade-fee ramp")
        XCTAssertEqual(Economy.sellbackRate, 0.65, accuracy: 1e-9, "shop buys dupes at 65% of market")
    }

    func testBoxAndBonusMultipliers() {
        for s in 1...5 {
            XCTAssertEqual(Economy.boxPrice(set: s), Economy.packPrice(set: s) * 11, accuracy: 1e-9,
                           "box price should be 11× pack price for set \(s)")
            XCTAssertEqual(Economy.setCompletionBonus(set: s), Economy.packPrice(set: s) * 15, accuracy: 1e-9,
                           "set-completion bonus should be 15× pack price for set \(s)")
        }
    }

    func testLowGradesReduceValue() {
        XCTAssertLessThan(Economy.gradeMultiplier(2), 1)
        XCTAssertLessThan(Economy.gradeMultiplier(7), 1)
    }

    func testGradeMultiplierSpotValues() {
        XCTAssertEqual(Economy.gradeMultiplier(10), 5)
        XCTAssertEqual(Economy.gradeMultiplier(1), 10)
        XCTAssertEqual(Economy.gradeMultiplier(8), 1)
    }

    func testGradeOddsSumToOneHundred() {
        XCTAssertEqual(Economy.gradeTable.reduce(0) { $0 + $1.odds }, 100)
    }

    func testSellValueUsesSellbackSpread() {
        var foil = CardInstance(cardId: "S1-050"); foil.foil = true
        XCTAssertEqual(foil.sellValue, Economy.sellback(foil.currentValue), accuracy: 1e-9)
        XCTAssertLessThan(foil.sellValue, foil.currentValue, "shop should pay less than market value")
    }

    func testSellingADuplicatePaysSellbackRate() {
        var core = GameCore()
        core.instances = [CardInstance(cardId: "S1-001"), CardInstance(cardId: "S1-001")]
        let market = core.instances[1].currentValue
        let before = core.cash
        let got = core.sell(instanceId: core.instances[1].id)
        XCTAssertNotNil(got)
        XCTAssertEqual(got!, Economy.sellback(market), accuracy: 1e-9, "a dupe should sell for 65% of market value")
        XCTAssertEqual(core.cash, before + Economy.sellback(market), accuracy: 1e-9)
    }

    func testChurningACompleteSetIsNetNegative() {
        var rng = SeededRNG(123)
        var churn = GameCore(); churn.cash = 500
        for c in CardDatabase.cards(inSet: 1) { churn.instances.append(CardInstance(cardId: c.id)) }
        _ = churn.checkBonuses()
        let cashBefore = churn.cash
        _ = churn.buyPack(set: 1, using: &rng)
        _ = churn.sellDuplicates(of: churn.uniqueOwnedIds)
        XCTAssertLessThan(churn.cash, cashBefore, "churning a pack into a full set should be a net loss")
    }
}
