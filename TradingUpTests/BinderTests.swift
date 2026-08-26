import XCTest
@testable import TradingUp

/// The Binder is the all-time showcase: one slot per Spryte, each holding the most
/// valuable copy ever owned, persisted separately from the run so it survives a
/// reset. These cover the record/merge rules, the derived roll-ups, load hygiene,
/// and the store's round-trip and never-destroy-on-failure guarantees.
final class BinderTests: XCTestCase {
    var dir: URL!
    var store: BinderStore!

    override func setUp() {
        super.setUp()
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tu_binder_tests_\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        store = BinderStore(directory: dir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    // A plain, a foil (×3), and a graded foil copy of the same card — strictly
    // increasing in market value, so "keeps the best" has an unambiguous winner.
    private let plain  = CardInstance(cardId: "S1-001")
    private let foil   = CardInstance(cardId: "S1-001", foil: true)
    private let graded = CardInstance(cardId: "S1-001", foil: true, grade: 10)

    // MARK: Recording

    func testValueOrderingAssumptionHolds() {
        XCTAssertGreaterThan(foil.currentValue, plain.currentValue)
        XCTAssertGreaterThan(graded.currentValue, foil.currentValue)
    }

    func testRecordingFillsEmptySlotAndReportsChange() {
        var binder = Binder()
        XCTAssertTrue(binder.record([plain]), "recording into an empty slot is a change")
        XCTAssertEqual(binder.best(for: "S1-001"), plain)
        XCTAssertTrue(binder.hasCard("S1-001"))
        XCTAssertEqual(binder.filledCount, 1)
    }

    func testRecordingKeepsMostValuableCopy() {
        var binder = Binder()
        binder.record([foil])
        XCTAssertTrue(binder.record([graded]), "a more valuable copy upgrades the slot")
        XCTAssertEqual(binder.best(for: "S1-001"), graded)

        XCTAssertFalse(binder.record([plain]), "a less valuable copy leaves the slot untouched")
        XCTAssertEqual(binder.best(for: "S1-001"), graded, "the best copy is retained")
    }

    func testReRecordingSameBestReportsNoChange() {
        var binder = Binder()
        binder.record([graded])
        XCTAssertFalse(binder.record([graded]), "re-recording the current best isn't a change")
    }

    func testRecordingIsAdditiveAcrossResets() {
        // Simulate a run that pulled a foil, then a fresh run that only has a plain
        // copy: the Binder must still remember the foil.
        var binder = Binder()
        binder.record([foil])
        binder.record([])                 // reset — nothing owned
        binder.record([plain])            // new run pulls a lesser copy
        XCTAssertEqual(binder.best(for: "S1-001"), foil, "the Binder never forgets its best")
    }

    func testRecordingIgnoresUnknownCardIds() {
        var binder = Binder()
        XCTAssertFalse(binder.record([CardInstance(cardId: "S9-999")]),
                       "an id not in the catalogue is ignored")
        XCTAssertEqual(binder.filledCount, 0)
    }

    // MARK: Derived roll-ups

    func testDerivedTotals() {
        var binder = Binder()
        let a = CardInstance(cardId: "S1-001", foil: true)
        let b = CardInstance(cardId: "S2-001")
        binder.record([a, b])

        XCTAssertEqual(binder.filledCount, 2)
        XCTAssertEqual(binder.totalSlots, CardDatabase.all.count)
        XCTAssertEqual(binder.filledCount(inSet: 1), 1)
        XCTAssertEqual(binder.filledCount(inSet: 2), 1)
        XCTAssertEqual(binder.filledCount(inSet: 3), 0)
        XCTAssertEqual(binder.totalValue, a.currentValue + b.currentValue, accuracy: 0.0001)
        XCTAssertEqual(binder.mostValuable, a, "the crown jewel is the highest-value copy")
        XCTAssertFalse(binder.isComplete)
    }

    func testIsCompleteWhenEverySlotFilled() {
        var binder = Binder()
        binder.record(CardDatabase.all.map { CardInstance(cardId: $0.id) })
        XCTAssertEqual(binder.filledCount, binder.totalSlots)
        XCTAssertTrue(binder.isComplete)
    }

    // MARK: Sanitize / load hygiene

    func testSanitizeDropsRetiredCards() {
        var binder = Binder(bestByCardId: [
            "S1-001": CardInstance(cardId: "S1-001"),
            "S9-999": CardInstance(cardId: "S9-999"),
        ])
        XCTAssertEqual(binder.sanitize(), 1, "one retired slot removed")
        XCTAssertTrue(binder.hasCard("S1-001"))
        XCTAssertFalse(binder.hasCard("S9-999"))
    }

    // MARK: Store round-trip & durability

    func testStoreRoundTrips() {
        var binder = Binder()
        binder.record([graded, CardInstance(cardId: "S3-010")])
        XCTAssertTrue(store.save(binder))

        let reloaded = store.load()
        XCTAssertEqual(reloaded.best(for: "S1-001"), graded)
        XCTAssertEqual(reloaded.filledCount, 2)
    }

    func testMissingFileLoadsEmptyBinder() {
        XCTAssertEqual(store.load().filledCount, 0, "no file yet is just an empty binder")
    }

    func testLoadSanitizesRetiredCards() {
        // Write a file that references a card no longer in the catalogue.
        let stale = Binder(bestByCardId: [
            "S1-001": CardInstance(cardId: "S1-001"),
            "S9-999": CardInstance(cardId: "S9-999"),
        ])
        XCTAssertTrue(store.save(stale))
        let loaded = store.load()
        XCTAssertEqual(loaded.filledCount, 1, "retired cards are stripped on load")
        XCTAssertTrue(loaded.hasCard("S1-001"))
    }

    func testUnreadableFileYieldsEmptyBinderWithoutDeleting() {
        try! Data("not json".utf8).write(to: store.url)
        XCTAssertEqual(store.load().filledCount, 0, "an unreadable binder falls back to empty")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url.path),
                      "the unreadable file must be left on disk, never deleted")
    }

    func testNewerSchemaFileIsNotLoadedOrClobbered() {
        // A binder written by a hypothetical newer schema version must be neither
        // decoded (dropping its unknown fields) nor overwritten by this build.
        let future = """
        {"schemaVersion":99,"binder":{"bestByCardId":{"S1-001":{"cardId":"S1-001"}}},"futureField":1}
        """
        try! Data(future.utf8).write(to: store.url)

        XCTAssertEqual(store.load().filledCount, 0, "a newer-schema binder is not loaded")
        XCTAssertFalse(store.canSave(), "this build must refuse to overwrite a newer-schema binder")
        XCTAssertFalse(store.save(Binder()), "save is a no-op against a newer-schema file")

        let stillThere = try? String(contentsOf: store.url, encoding: .utf8)
        XCTAssertEqual(stillThere, future, "the newer-schema file is left byte-for-byte intact")
    }
}

/// The Binder's whole reason for a separate store is that it must outlive a run.
/// These drive it through `GameState` to prove the wiring: an existing collection
/// seeds the Binder on launch, and a `newGame()` reset never erases it.
@MainActor
final class GameStateBinderTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        super.setUp()
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tu_gs_binder_\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    func testExistingCollectionSeedsBinderOnLaunch() {
        var core = GameCore()
        core.instances = [CardInstance(cardId: "S1-001", foil: true),
                          CardInstance(cardId: "S2-005")]
        let game = GameState(core: core, store: SaveStore(directory: dir))
        XCTAssertEqual(game.binder.filledCount, 2, "the loaded collection populates the Binder at launch")
        XCTAssertEqual(game.binder.best(for: "S1-001")?.foil, true)
    }

    func testBinderSurvivesNewGameAndPersists() {
        var core = GameCore()
        core.instances = [CardInstance(cardId: "S1-001", foil: true)]
        let game = GameState(core: core, store: SaveStore(directory: dir))
        XCTAssertTrue(game.binder.hasCard("S1-001"))

        game.newGame()   // wipes the run
        XCTAssertTrue(game.binder.hasCard("S1-001"),
                      "resetting the run must not clear the all-time Binder")

        // And it's on disk in the binder's own file, independent of the save.
        let persisted = BinderStore(directory: dir).load()
        XCTAssertTrue(persisted.hasCard("S1-001"), "the Binder is persisted separately from the run")
    }
}

