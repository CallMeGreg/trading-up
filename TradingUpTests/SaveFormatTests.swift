import XCTest
@testable import TradingUp

/// Save/load hygiene: every schema change must remain additive so old saves
/// never crash on decode, and the sanitizer must strip retired cards safely.
final class SaveFormatTests: XCTestCase {
    func testLegacySaveMissingNewerKeysStillDecodes() {
        let legacy = Data(#"{"cash":42.5,"instances":[],"claimedEvoLines":[],"claimedSets":[],"stats":{},"hasWon":false}"#.utf8)
        let old = try? JSONDecoder().decode(GameCore.self, from: legacy)
        XCTAssertNotNil(old, "a save missing newer keys should still decode")
        XCTAssertEqual(old?.cash, 42.5, "existing values should survive a lenient decode")
        XCTAssertEqual(old?.winAcknowledged, false)
        XCTAssertEqual(old?.welcomeSeen, false)
    }

    func testEmptyPayloadDecodesToDefaults() {
        let empty = try? JSONDecoder().decode(GameCore.self, from: Data("{}".utf8))
        XCTAssertNotNil(empty)
        XCTAssertEqual(empty?.cash, Economy.startingCash, "an empty payload should decode to a default game")
    }

    func testSaveRecordsSchemaVersionAndRoundTrips() {
        var core = GameCore()
        core.cash = 777
        let encoded = try! JSONEncoder().encode(SaveFile(core: core))
        let round = try? JSONDecoder().decode(SaveFile.self, from: encoded)
        XCTAssertEqual(round?.schemaVersion, SaveFile.currentVersion)
        XCTAssertEqual(round?.core.cash, 777, "save should round-trip the game state")
    }

    func testCardCopyWithOnlyCardIdDecodes() {
        let sparse = Data(#"{"instances":[{"cardId":"S1-001"}]}"#.utf8)
        let sparseCore = try? JSONDecoder().decode(GameCore.self, from: sparse)
        XCTAssertEqual(sparseCore?.instances.count, 1, "a card copy with only a cardId should still decode")
        XCTAssertEqual(sparseCore?.instances.first?.foil, false, "missing per-copy keys fall back to defaults")
        XCTAssertNil(sparseCore?.instances.first?.grade)
        XCTAssertEqual(sparseCore?.instances.first?.cardId, "S1-001", "the required cardId should survive")
    }

    func testUnknownCardIdResolvesToWorthlessPlaceholder() {
        var stale = GameCore()
        stale.instances = [CardInstance(cardId: "S1-001"), CardInstance(cardId: "S9-999")]
        let ghost = stale.instances[1]
        XCTAssertEqual(ghost.card.id, "S9-999")
        XCTAssertEqual(ghost.currentValue, 0, "an unknown card id should resolve to a worthless placeholder, not crash")
    }

    func testSanitizeDropsInstancesWithRetiredCards() {
        var stale = GameCore()
        stale.instances = [CardInstance(cardId: "S1-001"), CardInstance(cardId: "S9-999")]
        let (clean, dropped) = stale.sanitized()
        XCTAssertEqual(dropped, 1)
        XCTAssertEqual(clean.instances.count, 1)
        XCTAssertEqual(clean.instances[0].cardId, "S1-001")
    }

    func testSanitizeIsANoOpOnAValidSave() {
        XCTAssertEqual(GameCore().sanitized().droppedInstances, 0)
    }

    func testSanitizeUnclaimsSetsThatAreNoLongerComplete() {
        var claimed = GameCore()
        for c in CardDatabase.cards(inSet: 1) { claimed.instances.append(CardInstance(cardId: c.id)) }
        _ = claimed.checkBonuses()
        XCTAssertTrue(claimed.claimedSets.contains(1), "set 1 should be claimed while complete")
        claimed.instances.append(CardInstance(cardId: "S9-999"))
        claimed.instances.removeAll { $0.cardId == "S1-001" }
        XCTAssertFalse(claimed.sanitized().core.claimedSets.contains(1),
                       "a set that is no longer complete after sanitizing should be un-claimed")
    }

    // MARK: - Lifetime stats

    func testFoldingALostRunCountsStartedButNotWon() {
        var run = Stats()
        run.packsOpened = 10
        run.moneyEarned = 50
        run.peakCash = 500
        let after = LifetimeStats().folding(run, won: false)
        XCTAssertEqual(after.runsStarted, 1)
        XCTAssertEqual(after.runsWon, 0)
        XCTAssertEqual(after.packsOpened, 10, "sums should add the run's counters into lifetime")
        XCTAssertEqual(after.moneyEarned, 50)
        XCTAssertEqual(after.peakCash, 500, "maxes should rise to the run's peak")
        XCTAssertNil(after.bestRunPacks, "a lost run should never set bestRunPacks")
    }

    func testFoldingAWonRunIncrementsRunsWonAndRecordsBestRunPacks() {
        var won = Stats(); won.packsOpened = 7
        let after = LifetimeStats().folding(won, won: true)
        XCTAssertEqual(after.runsWon, 1)
        XCTAssertEqual(after.bestRunPacks, 7)
    }

    func testBestRunPacksOnlyImprovesTowardFewestPacks() {
        var first = Stats(); first.packsOpened = 7
        var better = LifetimeStats().folding(first, won: true)
        XCTAssertEqual(better.bestRunPacks, 7)

        var fewer = Stats(); fewer.packsOpened = 3
        better = better.folding(fewer, won: true)
        XCTAssertEqual(better.bestRunPacks, 3, "a faster winning run should lower bestRunPacks")

        var more = Stats(); more.packsOpened = 20
        better = better.folding(more, won: true)
        XCTAssertEqual(better.bestRunPacks, 3, "a slower winning run should not raise bestRunPacks")
    }

    func testFoldingMultipleRunsAccumulatesSumsAndCounters() {
        var runA = Stats(); runA.cardsSold = 4
        var runB = Stats(); runB.cardsSold = 6
        let twoRuns = LifetimeStats().folding(runA, won: false).folding(runB, won: true)
        XCTAssertEqual(twoRuns.cardsSold, 10)
        XCTAssertEqual(twoRuns.runsStarted, 2)
        XCTAssertEqual(twoRuns.runsWon, 1)
    }

    func testDisplayTimeFoldingNeverMutatesStoredLifetime() {
        var core = GameCore()
        core.stats.packsOpened = 5
        core.stats.moneyEarned = 40
        let display = core.lifetimeIncludingCurrentRun
        XCTAssertEqual(display.runsStarted, 1, "the in-progress run should count toward all-time display")
        XCTAssertEqual(display.packsOpened, 5)
        XCTAssertEqual(core.lifetime.runsStarted, 0, "stored lifetime must not be mutated by a display read")
    }

    func testStartingNewRunFoldsFinishedRunIntoLifetimeAndResets() {
        var finished = GameCore()
        finished.cash = 999
        finished.stats.packsOpened = 12
        finished.hasWon = true
        let next = finished.startingNewRun()
        XCTAssertEqual(next.lifetime.runsStarted, 1)
        XCTAssertEqual(next.lifetime.runsWon, 1, "a won run should be folded in as a win")
        XCTAssertEqual(next.lifetime.packsOpened, 12)
        XCTAssertEqual(next.cash, Economy.startingCash, "cash should reset on a new run")
        XCTAssertEqual(next.stats.packsOpened, 0, "current-run stats should reset on a new run")
        XCTAssertEqual(next.lifetimeIncludingCurrentRun.runsStarted, 2,
                       "all-time display right after reset should count the completed run plus the new one")
    }

    func testFoldingALostRunDoesNotFlipRunsWon() {
        var finished = GameCore()
        finished.stats.packsOpened = 4
        finished.hasWon = false
        let next = finished.startingNewRun()
        XCTAssertEqual(next.lifetime.runsStarted, 1)
        XCTAssertEqual(next.lifetime.runsWon, 0, "a run that ended without winning should not increment runsWon")
    }

    func testEmptyLifetimeStatsPayloadDecodesToDefaults() {
        let empty = try? JSONDecoder().decode(LifetimeStats.self, from: Data("{}".utf8))
        XCTAssertNotNil(empty)
        XCTAssertEqual(empty?.runsStarted, 0)
        XCTAssertEqual(empty?.runsWon, 0)
        XCTAssertNil(empty?.bestRunPacks)
        XCTAssertEqual(empty?.peakCash, Economy.startingCash)
    }

    func testGameCoreDecodesMissingLifetimeToDefaults() {
        let legacy = Data(#"{"cash":42.5,"instances":[],"claimedEvoLines":[],"claimedSets":[],"stats":{},"hasWon":false}"#.utf8)
        let core = try? JSONDecoder().decode(GameCore.self, from: legacy)
        XCTAssertNotNil(core)
        XCTAssertEqual(core?.lifetime.runsStarted, 0, "a save with no lifetime key should default to zero")
    }
}
