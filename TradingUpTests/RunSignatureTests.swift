import XCTest
@testable import TradingUp

final class RunSignatureTests: XCTestCase {

    // MARK: Rank thresholds

    func testRankBoundaries() {
        XCTAssertEqual(CollectorRank.forPacks(0), .s)
        XCTAssertEqual(CollectorRank.forPacks(259), .s)
        XCTAssertEqual(CollectorRank.forPacks(260), .a)
        XCTAssertEqual(CollectorRank.forPacks(359), .a)
        XCTAssertEqual(CollectorRank.forPacks(360), .b)
        XCTAssertEqual(CollectorRank.forPacks(499), .b)
        XCTAssertEqual(CollectorRank.forPacks(500), .c)
        XCTAssertEqual(CollectorRank.forPacks(719), .c)
        XCTAssertEqual(CollectorRank.forPacks(720), .d)
        XCTAssertEqual(CollectorRank.forPacks(5000), .d)
    }

    // MARK: Title selection

    func testFoilHeavyRunEarnsGilded() {
        var s = Stats()
        s.cardsPulled = 1000
        s.foilsPulled = 30            // 3% — well above the ~1% baseline
        XCTAssertEqual(RunSignature.earnedTitle(stats: s, element: .fire).title, "The Gilded")
    }

    func testUltraHeavyRunEarnsApex() {
        var s = Stats()
        s.packsOpened = 200
        s.ultrasPulled = 60           // 0.30 per pack
        XCTAssertEqual(RunSignature.earnedTitle(stats: s, element: .fire).title, "The Apex")
    }

    func testBigFlipEarnsCloser() {
        var s = Stats()
        s.peakSale = 500
        s.peakCardValue = 520         // sold for ~96% of the best card ever held
        XCTAssertEqual(RunSignature.earnedTitle(stats: s, element: .fire).title, "The Closer")
    }

    func testUnremarkableRunFallsBackToElementMaster() {
        let s = Stats()               // all zeros — no standout feat
        XCTAssertEqual(RunSignature.earnedTitle(stats: s, element: .water).title, Element.water.masterTitle)
        XCTAssertEqual(RunSignature.earnedTitle(stats: s, element: .shadow).title, "The Nightbound")
    }

    func testStrongestStandoutWinsWhenSeveralApply() {
        var s = Stats()
        s.cardsPulled = 1000
        s.foilsPulled = 18            // ~0.018 → just over the bar, low intensity
        s.packsOpened = 100
        s.ultrasPulled = 40           // 0.40 per pack → high intensity
        XCTAssertEqual(RunSignature.earnedTitle(stats: s, element: .fire).title, "The Apex")
    }

    // MARK: Dominant element

    func testDominantElementReflectsWhatWasKept() {
        let water = Array(CardDatabase.all.filter { $0.element == .water }.prefix(3))
        let fire = Array(CardDatabase.all.filter { $0.element == .fire }.prefix(1))
        XCTAssertFalse(water.isEmpty, "catalogue should contain water cards")

        var instances: [CardInstance] = []
        for c in water { for _ in 0..<4 { instances.append(CardInstance(cardId: c.id)) } }
        for c in fire { instances.append(CardInstance(cardId: c.id)) }

        XCTAssertEqual(RunSignature.dominantElement(instances), .water)
    }

    // MARK: End-to-end on a finished collection

    func testSignatureFromCompletedCollectionIsValid() {
        var core = GameCore()
        for c in CardDatabase.all { core.instances.append(CardInstance(cardId: c.id)) }
        _ = core.checkBonuses()

        let sig = RunSignature.make(from: core)
        XCTAssertFalse(sig.title.isEmpty)
        XCTAssertNotNil(sig.crownJewel, "a finished binder has a most-valuable card")
        XCTAssertGreaterThan(sig.crownJewelValue, 0)
        XCTAssertGreaterThanOrEqual(sig.runNumber, 1)
        XCTAssertGreaterThan(sig.netWorth, 0)
        XCTAssertFalse(sig.seed.isEmpty)
    }

    /// The crest seed must be stable for a given run so the shared card never
    /// changes out from under the player.
    func testSeedIsDeterministic() {
        var core = GameCore()
        for c in CardDatabase.all.prefix(60) { core.instances.append(CardInstance(cardId: c.id)) }
        XCTAssertEqual(RunSignature.make(from: core).seed, RunSignature.make(from: core).seed)
    }
}
