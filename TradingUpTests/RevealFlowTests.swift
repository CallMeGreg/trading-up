import XCTest
@testable import TradingUp

/// Covers the fix for the win/reveal collision: completing the collection on a
/// pack pull used to pop the win overlay *on top of* the still-open pack reveal.
/// The celebration now waits for the reveal (and its keep/sell summary) to be
/// dismissed first. Game Over is gated the same way.
@MainActor
final class RevealFlowTests: XCTestCase {

    private func tempStore() -> SaveStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return SaveStore(directory: dir)
    }

    /// A core that has just won the Season by clearing the Championship — the
    /// state that now pops the win celebration (completing the 250-card binder no
    /// longer does; that's the Master Collector milestone).
    private func wonCore() -> GameCore {
        var core = GameCore()
        core.ensureActiveRun()
        core.run.show = Economy.seasonShows
        core.cash = Economy.quota(show: Economy.seasonShows) + 1_000
        _ = core.makeCut()
        return core
    }

    func testWinCelebrationWaitsForTheRevealToFinish() {
        let game = GameState(core: wonCore(), store: tempStore())
        XCTAssertTrue(game.shouldShowWin, "the Season is won, so a win is pending")
        XCTAssertTrue(game.presentsWin, "with no reveal on screen the win shows immediately")

        game.beginReveal()
        XCTAssertTrue(game.shouldShowWin, "the pending win doesn't go away…")
        XCTAssertFalse(game.presentsWin, "…but it holds off while the pack reveal is on screen")

        game.endReveal()
        XCTAssertTrue(game.presentsWin, "once the reveal is dismissed the celebration appears")
    }

    func testGameOverWaitsForTheRevealToFinish() {
        var broke = GameCore()
        broke.cash = 0            // no cash and no cards to sell: provably finished
        let game = GameState(core: broke, store: tempStore())
        XCTAssertTrue(game.presentsGameOver, "a broke game with nothing to sell is over")

        game.beginReveal()
        XCTAssertFalse(game.presentsGameOver, "the final affordable pack still gets revealed first")

        game.endReveal()
        XCTAssertTrue(game.presentsGameOver)
    }

    func testRevealFlagStartsClear() {
        let game = GameState(core: GameCore(), store: tempStore())
        XCTAssertFalse(game.revealInFlight)
    }
}

/// The DEBUG-only fast-travel seed used to reach the ending quickly in tests.
final class DebugLaunchStateTests: XCTestCase {

    func testAlmostWonIsExactlyOneUniqueFromWinning() {
        let core = DebugLaunchState.almostWon()
        XCTAssertEqual(core.uniqueCount, CardDatabase.all.count - 1,
                       "seed should own every card but one")
        XCTAssertFalse(core.hasWon, "the win still has to be earned by the last pull")
        XCTAssertGreaterThan(core.cash, Economy.packPrice(set: 1),
                             "seed should have enough cash to keep buying packs")
        XCTAssertTrue(core.welcomeSeen, "seed shouldn't trip the onboarding overlay")
    }

    func testAllButTheFinalSetAreAlreadyClaimed() {
        let core = DebugLaunchState.almostWon()
        // The held-out card is a set 1 common, so set 1 is the only unclaimed set.
        XCTAssertFalse(core.claimedSets.contains(1), "set 1 still has a hole in it")
        for set in 2...CardDatabase.setCount {
            XCTAssertTrue(core.claimedSets.contains(set), "set \(set) is complete and pre-claimed")
        }
    }

    func testFinishingTheCollectionFromTheSeedFiresMasterCollector() {
        var core = DebugLaunchState.almostWon()
        let missing = Set(CardDatabase.all.map { $0.id }).subtracting(core.uniqueOwnedIds)
        XCTAssertEqual(missing.count, 1)
        core.instances.append(CardInstance(cardId: missing.first!))
        _ = core.checkBonuses()
        XCTAssertFalse(core.hasWon, "completing the binder no longer wins — the Championship does")
        let fired = core.refreshMilestones()
        XCTAssertTrue(fired.contains { $0.milestone == .masterCollector },
                      "adding the last missing card fires the Master Collector milestone")
    }

    func testEnvironmentGatesTheSeed() {
        XCTAssertNil(DebugLaunchState.core(environment: [:]),
                     "a normal launch loads the real save, not a seeded state")
        XCTAssertNotNil(DebugLaunchState.core(environment: [DebugLaunchState.key: "almost-won"]))
        XCTAssertNil(DebugLaunchState.core(environment: [DebugLaunchState.key: "nonsense"]),
                     "an unknown state name is ignored")
    }

    func testCashOverride() {
        let core = DebugLaunchState.core(environment: [
            DebugLaunchState.key: "almost-won",
            DebugLaunchState.cashKey: "5000",
        ])
        XCTAssertEqual(core?.cash, 5000)
    }

    func testMissingOverrideHoldsOutTheRequestedCard() {
        let core = DebugLaunchState.core(environment: [
            DebugLaunchState.key: "almost-won",
            DebugLaunchState.missingKey: "S1-047",
        ])
        XCTAssertNotNil(core)
        XCTAssertFalse(core!.owns("S1-047"), "the requested card should be the one held out")
        XCTAssertEqual(core!.uniqueCount, CardDatabase.all.count - 1,
                       "everything else should still be owned")
        // Set 1 owns the held-out rare's set, so it's the only unclaimed set.
        XCTAssertFalse(core!.claimedSets.contains(1))
    }

    func testSeedParsing() {
        XCTAssertNil(DebugLaunchState.seed(environment: [:]),
                     "no seed means genuine system randomness")
        XCTAssertEqual(DebugLaunchState.seed(environment: [DebugLaunchState.seedKey: "62"]), 62)
        XCTAssertNil(DebugLaunchState.seed(environment: [DebugLaunchState.seedKey: "not-a-number"]))
    }
}
