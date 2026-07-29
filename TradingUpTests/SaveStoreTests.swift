import XCTest
@testable import TradingUp

/// Quarantine behavior for the on-disk save store: unreadable saves must be
/// preserved (never deleted) and reported, while retired cards are stripped
/// on load with a user-visible issue.
final class SaveStoreTests: XCTestCase {
    var dir: URL!
    var store: SaveStore!

    override func setUp() {
        super.setUp()
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tu_tests_\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        store = SaveStore(directory: dir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    func testNoSaveFileYetIsFreshGame() {
        let loaded = store.load()
        XCTAssertNil(loaded.core)
        XCTAssertNil(loaded.issue)
    }

    func testSaveWritesAndReloadsCorrectly() {
        var core = GameCore()
        core.cash = 321
        core.hasWon = true
        core.acknowledgeWin()
        XCTAssertTrue(store.save(core), "save should write to disk")
        let reloaded = store.load()
        XCTAssertEqual(reloaded.core?.cash, 321, "reload should restore cash")
        XCTAssertEqual(reloaded.core?.winAcknowledged, true, "reload should restore win acknowledgement")
        XCTAssertNil(reloaded.issue, "a healthy save should report no issue")
    }

    func testPreEnvelopeSaveStillLoads() {
        var legacyCore = GameCore(); legacyCore.cash = 55
        try! JSONEncoder().encode(legacyCore).write(to: store.url)
        XCTAssertEqual(store.load().core?.cash, 55, "a pre-envelope (bare GameCore) save should still load")
    }

    func testRetiredCardsAreStrippedAndReportedOnLoad() {
        var stale = GameCore()
        stale.instances = [CardInstance(cardId: "S1-001"), CardInstance(cardId: "S9-999")]
        _ = store.save(stale)
        let cleaned = store.load()
        XCTAssertEqual(cleaned.core?.instances.count, 1, "retired cards should be stripped on load")
        XCTAssertEqual(cleaned.issue, .droppedUnknownCards(count: 1), "the player should be told cards were removed")
    }

    func testUnreadableSaveIsQuarantinedNotDeleted() {
        try! Data("not json at all".utf8).write(to: store.url)
        let broken = store.load()
        XCTAssertNil(broken.core, "an unreadable save should fall back to a fresh game")
        var quarantinedName: String? = nil
        if case .unreadable(let name) = broken.issue { quarantinedName = name }
        XCTAssertNotNil(quarantinedName, "an unreadable save should report where it was moved")

        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        XCTAssertTrue(leftovers.contains { $0.hasPrefix("tradingup_save.corrupt-") },
                     "the unreadable save should be quarantined on disk, never deleted")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url.path),
                       "the bad file should be moved aside so the next save starts clean")
    }

    func testV1SaveMigratesToV2WithoutLosingData() {
        let v1Save = """
        {"schemaVersion":1,"core":{"cash":250,"instances":[{"cardId":"S1-001"}],\
        "claimedEvoLines":[],"claimedSets":[],"stats":{"packsOpened":9,"moneyEarned":30},"hasWon":false}}
        """
        try! Data(v1Save.utf8).write(to: store.url)
        let migrated = store.load()
        XCTAssertEqual(migrated.core?.cash, 250, "a v1 save should migrate without losing cash")
        XCTAssertEqual(migrated.core?.stats.packsOpened, 9, "a v1 save should keep its current-run stats")
        XCTAssertEqual(migrated.core?.instances.count, 1, "a v1 save should keep its collection")
        XCTAssertEqual(migrated.core?.lifetime.runsStarted, 0, "a v1 save's stored lifetime should default to zero")
        XCTAssertEqual(migrated.core?.lifetimeIncludingCurrentRun.packsOpened, 9,
                       "all-time display should immediately reflect the in-progress run's stats after migration")
        XCTAssertNil(migrated.issue, "a valid v1 save should migrate cleanly with no reported issue")
    }

    func testBarePreEnvelopeSaveDecodesLifetimeToDefaults() {
        var legacyCore = GameCore(); legacyCore.cash = 55
        try! JSONEncoder().encode(legacyCore).write(to: store.url)
        let loaded = store.load()
        XCTAssertEqual(loaded.core?.cash, 55)
        XCTAssertEqual(loaded.core?.lifetime.runsStarted, 0,
                       "a bare pre-envelope save should also decode lifetime to defaults")
    }

    func testSaveFromNewerSchemaVersionIsQuarantinedNotSilentlyTruncated() {
        // A hypothetical v99 save carrying a field this build has never heard
        // of (`futureField`). A lenient decode would just drop it — and the
        // next autosave would make that loss permanent — so this must refuse
        // to load rather than absorb it.
        let futureSave = """
        {"schemaVersion":99,"core":{"cash":777,"instances":[{"cardId":"S1-001"}],\
        "claimedEvoLines":[],"claimedSets":[],"stats":{},"hasWon":false,"futureField":"do not drop me"}}
        """
        try! Data(futureSave.utf8).write(to: store.url)
        let loaded = store.load()

        XCTAssertNil(loaded.core, "a save from a newer schema version should not load at all")
        var quarantinedName: String? = nil
        if case .fromNewerVersion(let name) = loaded.issue { quarantinedName = name }
        XCTAssertNotNil(quarantinedName, "the player should be told this save needs a newer app version")

        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        XCTAssertTrue(leftovers.contains { $0.hasPrefix("tradingup_save.corrupt-") },
                     "a newer-schema save should be quarantined on disk, never deleted")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url.path),
                       "the newer-schema file should be moved aside so it isn't overwritten")

        // The original bytes must still be fully intact (and readable as v99)
        // under the quarantined name — nothing was truncated or rewritten.
        let quarantinedURL = dir.appendingPathComponent(quarantinedName!)
        let recovered = try? String(contentsOf: quarantinedURL, encoding: .utf8)
        XCTAssertEqual(recovered, futureSave, "the quarantined file should be byte-for-byte the original save")

        // A subsequent save (e.g. GameState falling back to a fresh game and
        // autosaving) must not touch the quarantined file.
        _ = store.save(GameCore())
        let stillRecovered = try? String(contentsOf: quarantinedURL, encoding: .utf8)
        XCTAssertEqual(stillRecovered, futureSave,
                       "a later save must not overwrite the quarantined newer-schema file")
    }
}
