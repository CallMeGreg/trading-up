import XCTest
@testable import TradingUp

final class WinPresentationTests: XCTestCase {
    /// A core that has just won the Season by clearing the Championship Show.
    private func championCore() -> GameCore {
        var core = GameCore()
        core.ensureActiveRun()
        core.run.show = Economy.seasonShows
        core.cash = Economy.quota(show: Economy.seasonShows) + 1_000   // trivially over the bar
        _ = core.makeCut()
        return core
    }

    func testWinOverlayShowsOnceTheSeasonIsWon() {
        let core = championCore()
        XCTAssertTrue(core.hasWon, "clearing the Championship wins the Season")
        XCTAssertTrue(core.shouldShowWin, "the win overlay should show once the Season is won")
    }

    func testDismissingWinKeepsCollectionInsteadOfResetting() {
        var core = championCore()
        core.acknowledgeWin()
        XCTAssertTrue(core.hasWon)
        XCTAssertFalse(core.shouldShowWin, "dismissing the win should not force a reset")
        XCTAssertFalse(core.isGameOver, "a won Season can't then be flagged game over")
    }

    func testNewGameStartsWithWinUnacknowledged() {
        XCTAssertFalse(GameCore().winAcknowledged)
    }
}

final class SetUnlockingTests: XCTestCase {
    func testUniquesNeededPerSet() {
        XCTAssertEqual(Economy.uniquesToUnlock(set: 1), 0)
        XCTAssertEqual(Economy.uniquesToUnlock(set: 2), 25)
        XCTAssertEqual(Economy.uniquesToUnlock(set: 3), 50)
        XCTAssertEqual(Economy.uniquesToUnlock(set: 4), 75)
        XCTAssertEqual(Economy.uniquesToUnlock(set: 5), 100)
    }

    func testFreshGameOnlyHasSetOneUnlocked() {
        var core = GameCore()
        core.cash = 100_000
        XCTAssertTrue(core.isUnlocked(set: 1))
        XCTAssertFalse(core.isUnlocked(set: 2))
        XCTAssertFalse(core.isUnlocked(set: 5))
    }

    func testCannotBuyFromALockedSet() {
        var rng = SeededRNG(99)
        var core = GameCore()
        core.cash = 100_000
        let before = core.cash
        XCTAssertNil(core.buyPack(set: 2, using: &rng), "cannot buy pack from a locked set")
        XCTAssertNil(core.buyBox(set: 2, using: &rng), "cannot buy box from a locked set")
        XCTAssertEqual(core.cash, before, "locked purchase should spend no cash")
    }

    func testSetTwoUnlocksAt25Uniques() {
        var rng = SeededRNG(99)
        var core = GameCore()
        core.cash = 100_000
        for i in 1...25 { core.instances.append(CardInstance(cardId: String(format: "S1-%03d", i))) }
        XCTAssertEqual(core.uniqueCount, 25)
        XCTAssertTrue(core.isUnlocked(set: 2), "set 2 should unlock at 25 uniques")
        XCTAssertFalse(core.isUnlocked(set: 3), "set 3 should still be locked at 25 uniques (needs 50)")
        XCTAssertNotNil(core.buyPack(set: 2, using: &rng), "should be able to buy from set 2 once unlocked")
    }
}
