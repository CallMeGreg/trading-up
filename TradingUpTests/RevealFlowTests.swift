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

    private func completedCore() -> GameCore {
        var core = GameCore()
        for c in CardDatabase.all { core.instances.append(CardInstance(cardId: c.id)) }
        _ = core.checkBonuses()
        return core
    }

    func testWinCelebrationWaitsForTheRevealToFinish() {
        let game = GameState(core: completedCore(), store: tempStore())
        XCTAssertTrue(game.shouldShowWin, "the collection is complete, so a win is pending")
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

    func testFinishingTheCollectionFromTheSeedTriggersTheWin() {
        var core = DebugLaunchState.almostWon()
        let missing = Set(CardDatabase.all.map { $0.id }).subtracting(core.uniqueOwnedIds)
        XCTAssertEqual(missing.count, 1)
        core.instances.append(CardInstance(cardId: missing.first!))
        _ = core.checkBonuses()
        XCTAssertTrue(core.hasWon, "adding the last missing card wins the game")
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

/// The evolution-line **stage pips** are the shared contract behind the "pips
/// update as cards are kept" behaviour on both pack-summary screens: a stage
/// counts as owned exactly when a copy of it stands in the caller's pool — the
/// live Classic keep/sell decisions in `RevealView`, or the Gauntlet Showcase.
/// These lock that mapping so the pips keep reflecting *what is now owned*.
final class EvolutionPipTests: XCTestCase {

    /// A real multi-stage evolution line to exercise (base = stage 1, top = last).
    private func sampleLine() throws -> (line: [Card], base: Card, top: Card) {
        let line = try XCTUnwrap(
            CardDatabase.evolutionLines.values.sorted { $0[0].id < $1[0].id }.first,
            "the card set should contain at least one multi-stage evolution line")
        return (line, line.first!, line.last!)
    }

    func testOwnedStagesFollowTheOwnershipPool() throws {
        let s = try sampleLine()
        // Own only the base stage; the card in hand is the top stage.
        let owned: Set<String> = [s.base.id]
        let series = CardSeries(for: s.top, pull: true) { owned.contains($0.id) }

        XCTAssertEqual(series.line.map(\.id), s.line.map(\.id),
                       "the pips span the whole sorted evolution line")
        XCTAssertTrue(series.ownedStages.contains(s.base.stage), "the owned base stage is lit")
        XCTAssertFalse(series.ownedStages.contains(s.top.stage), "the un-owned top stage is dark…")
        XCTAssertEqual(series.nowStage, s.top.stage, "…and flagged as the current pull (pull: true)")
    }

    func testKeepingACardLightsItsStageForTheOtherCards() throws {
        let s = try sampleLine()
        // A sibling (the base-stage card) looks at the line while the top stage is
        // still undecided, then again once it's been kept into the pool.
        var pool: Set<String> = []
        func siblingPips() -> CardSeries { CardSeries(for: s.base, pull: true) { pool.contains($0.id) } }

        XCTAssertFalse(siblingPips().ownedStages.contains(s.top.stage),
                       "before the top-stage card is kept, its pip reads dark on the other cards")
        pool.insert(s.top.id)          // keep it
        XCTAssertTrue(siblingPips().ownedStages.contains(s.top.stage),
                      "once kept it lights up in the other cards' pips — reflecting what is now owned")
    }

    func testGauntletPipsTrackTheShowcase() throws {
        let s = try sampleLine()
        let onlyPull = CardSeries.gauntlet(s.top, showcase: [])
        XCTAssertTrue(onlyPull.ownedStages.isEmpty, "an empty Showcase owns no stages")
        XCTAssertEqual(onlyPull.nowStage, s.top.stage, "the pulled card's own stage is the current pull")

        let withBaseKept = CardSeries.gauntlet(s.top, showcase: [CardInstance(cardId: s.base.id)])
        XCTAssertTrue(withBaseKept.ownedStages.contains(s.base.stage),
                      "a card standing in the Showcase lights its stage for the new pull")
    }
}
