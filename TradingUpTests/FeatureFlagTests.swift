import XCTest
@testable import TradingUp

/// The booster-box kill switch. It ships disabled, and when it is flipped the
/// purchase paths themselves have to refuse — hiding the button is not the same
/// thing as closing the door.
@MainActor
final class BoosterBoxFeatureFlagTests: XCTestCase {
    var dir: URL!
    var game: GameState!

    override func setUp() {
        super.setUp()
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tu_tests_\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Default starting cash doesn't cover a box, so fund generously.
        var core = GameCore()
        core.cash = 10_000
        let store = SaveStore(directory: dir)
        _ = store.save(core)
        game = GameState(store: store)
    }

    override func tearDown() {
        FeatureFlags.removeBoosterBoxes = false
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    func testFlagShipsDisabled() {
        XCTAssertFalse(FeatureFlags.removeBoosterBoxes,
                       "the booster-box removal flag must ship off")
        XCTAssertTrue(FeatureFlags.boosterBoxesAvailable,
                      "with the flag off the shop still sells booster boxes")
    }

    func testAvailabilityTracksTheFlag() {
        FeatureFlags.removeBoosterBoxes = true
        XCTAssertFalse(FeatureFlags.boosterBoxesAvailable)
        FeatureFlags.removeBoosterBoxes = false
        XCTAssertTrue(FeatureFlags.boosterBoxesAvailable)
    }

    func testBoxIsPurchasableWhileTheFlagIsOff() {
        let results = game.buyBoxPacks(set: 1)
        XCTAssertEqual(results?.count, Economy.boxPacks,
                       "a box should open as one result per pack")
        XCTAssertEqual(game.stats.boxesOpened, 1)
        XCTAssertEqual(game.stats.moneySpent, Economy.boxPrice(set: 1), accuracy: 0.001,
                       "buying a box should charge the box price")
    }

    func testFlagBlocksBoxPacksPurchase() {
        FeatureFlags.removeBoosterBoxes = true
        let cashBefore = game.cash
        XCTAssertNil(game.buyBoxPacks(set: 1),
                     "no box may be sold once boxes are removed from the shop")
        XCTAssertEqual(game.cash, cashBefore, "a refused box must not charge the player")
        XCTAssertEqual(game.stats.boxesOpened, 0)
        XCTAssertEqual(game.stats.packsOpened, 0)
        XCTAssertEqual(game.uniqueCount, 0, "a refused box must not add cards")
    }

    func testFlagBlocksSingleResultBoxPurchase() {
        FeatureFlags.removeBoosterBoxes = true
        let cashBefore = game.cash
        XCTAssertNil(game.buyBox(set: 1))
        XCTAssertEqual(game.cash, cashBefore)
        XCTAssertEqual(game.stats.boxesOpened, 0)
    }

    func testFlagLeavesPackPurchasesAlone() {
        FeatureFlags.removeBoosterBoxes = true
        XCTAssertNotNil(game.buyPack(set: 1), "removing boxes must not touch packs")
        XCTAssertEqual(game.stats.packsOpened, 1)
        XCTAssertEqual(game.stats.moneySpent, Economy.packPrice(set: 1), accuracy: 0.001)
    }

    /// Box history stays readable after the flag is flipped: the stat tiles
    /// describe boxes the player already opened, and blanking them would
    /// misreport their save.
    func testAlreadyOpenedBoxesStayInTheStats() {
        XCTAssertNotNil(game.buyBoxPacks(set: 1))
        XCTAssertEqual(game.stats.boxesOpened, 1)
        FeatureFlags.removeBoosterBoxes = true
        XCTAssertEqual(game.stats.boxesOpened, 1,
                       "removing boxes from the shop must not erase box history")
    }
}
