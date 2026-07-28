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
}
