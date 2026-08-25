import XCTest
@testable import TradingUp

/// The Chase v3 save envelope and the one-time 2.0 migration. Guards the
/// never-delete quarantine contract (unreadable / newer-schema saves are moved
/// aside, never removed) and the reset-and-seed that imports a v1/v2 collection
/// into the new Binder exactly once.
final class ChaseSaveTests: XCTestCase {
    var dir: URL!
    var store: ChaseSaveStore!

    override func setUp() {
        super.setUp()
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("chase_tests_\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        store = ChaseSaveStore(directory: dir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func filesInDir() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
    }

    func testBrandNewPlayerIsFreshWithNoIssue() {
        let loaded = store.load()
        XCTAssertNil(loaded.core, "no save and no legacy collection means a truly fresh start")
        XCTAssertNil(loaded.issue, "a brand-new player sees no reset or error screen")
    }

    func testSaveRoundTripsMetaState() {
        var core = ChaseCore()
        core.meta.renown = 123
        core.meta.deposit(CardInstance(cardId: CardDatabase.all[0].id, foil: true, grade: 10))
        _ = core.meta.unlockTrainer(.grader)
        XCTAssertTrue(store.save(core), "a healthy save writes to disk")

        let back = store.load()
        XCTAssertNil(back.issue, "a healthy save reports no issue")
        XCTAssertEqual(back.core?.meta.renown, 123, "Renown survives the round-trip")
        XCTAssertEqual(back.core?.meta.binderUnique, 1, "the Binder survives the round-trip")
        XCTAssertEqual(back.core?.meta.isTrainerUnlocked(.grader), true, "unlocked Trainers survive the round-trip")
    }

    func testUnreadableSaveIsQuarantinedNotDeleted() {
        try! Data("definitely not json".utf8).write(to: store.url)
        let loaded = store.load()

        XCTAssertNil(loaded.core, "an unreadable save falls back to a fresh game")
        var name: String? = nil
        if case .unreadable(let n) = loaded.issue { name = n }
        XCTAssertNotNil(name, "the player is told where the bad save went")

        XCTAssertTrue(filesInDir().contains { $0.hasPrefix("tradingup_chase.archived-") },
                      "the unreadable save is quarantined on disk, never deleted")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url.path),
                       "the bad file is moved aside so the next save starts clean")
    }

    func testNewerSchemaSaveIsQuarantinedNotTruncated() {
        let future = #"{"schemaVersion":99,"core":{"meta":{"renown":5},"secretFutureField":"keep me"}}"#
        try! Data(future.utf8).write(to: store.url)
        let loaded = store.load()

        XCTAssertNil(loaded.core, "a save from a newer schema version must not load")
        var name: String? = nil
        if case .fromNewerVersion(let n) = loaded.issue { name = n }
        XCTAssertNotNil(name, "the player is told they need a newer app version")

        let archived = filesInDir().first { $0.hasPrefix("tradingup_chase.archived-") }
        XCTAssertNotNil(archived, "a newer-schema save is quarantined, never deleted")
        let recovered = try? String(contentsOf: dir.appendingPathComponent(archived!), encoding: .utf8)
        XCTAssertEqual(recovered, future, "the quarantined bytes are the original, byte-for-byte")
    }

    func test2point0MigrationSeedsBinderQuarantinesLegacyAndReports() {
        // A v1/v2 collection on disk, no Chase save yet.
        var legacy = GameCore()
        legacy.instances = [CardInstance(cardId: CardDatabase.all[0].id, foil: true, grade: 9),
                            CardInstance(cardId: CardDatabase.all[1].id)]
        XCTAssertTrue(SaveStore(directory: dir).save(legacy), "seed a legacy save to migrate from")

        let loaded = store.load()
        XCTAssertNotNil(loaded.core, "the first 2.0 launch starts a fresh Chase career")
        XCTAssertEqual(loaded.core?.meta.binderUnique, 2, "the best copy of every owned card seeds the Binder")
        XCTAssertNil(loaded.core?.run, "nothing transfers as a live run")
        XCTAssertEqual(loaded.core?.meta.renown, 0, "no cash or Renown carries over — only the Binder")

        var quarantined: String? = nil
        if case .resetForNewVersion(let n) = loaded.issue { quarantined = n }
        XCTAssertNotNil(quarantined, "the reset surfaces the What's-New screen")
        XCTAssertTrue(filesInDir().contains { $0.hasPrefix("tradingup_save.archived-") },
                      "the old collection is quarantined, never deleted")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url.path),
                      "a fresh Chase save is written so the reset runs exactly once")
    }

    func testMigrationRunsExactlyOnce() {
        var legacy = GameCore()
        legacy.instances = [CardInstance(cardId: CardDatabase.all[0].id)]
        _ = SaveStore(directory: dir).save(legacy)

        let first = store.load()
        if case .resetForNewVersion = first.issue {} else { XCTFail("first launch should reset") }

        let second = store.load()
        XCTAssertNil(second.issue, "a second launch reads the Chase save with no reset")
        XCTAssertEqual(second.core?.meta.binderUnique, 1, "the seeded Binder persists across launches")
    }

    func testLoadSanitizesRetiredCards() {
        var core = ChaseCore()
        core.meta.deposit(CardInstance(cardId: CardDatabase.all[0].id))
        core.meta.binder["S9-999"] = BinderCopy(foil: false, grade: nil)   // no longer shipped
        _ = store.save(core)

        let loaded = store.load()
        XCTAssertNil(loaded.core?.meta.binder["S9-999"], "a retired card is stripped on load")
        XCTAssertEqual(loaded.core?.meta.binderUnique, 1, "real cards survive the load")
    }
}
