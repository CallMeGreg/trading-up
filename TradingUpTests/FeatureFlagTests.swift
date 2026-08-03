import XCTest
@testable import TradingUp

/// The booster-box kill switch. It ships **on** — the shop sells packs only —
/// and when it is on the purchase paths themselves have to refuse: hiding the
/// button is not the same thing as closing the door.
///
/// `FeatureFlags` is global mutable state, so every test here sets the state it
/// needs explicitly and `tearDown` restores whatever the app actually ships.
/// Restoring a hardcoded value instead would let one test dictate what the
/// others observe — which is exactly how the shipped-value assertion below
/// managed to pass in a full run while failing on its own.
@MainActor
final class BoosterBoxFeatureFlagTests: XCTestCase {
    var dir: URL!
    var game: GameState!
    private var shippedFlag: Bool!

    override func setUp() {
        super.setUp()
        shippedFlag = FeatureFlags.removeBoosterBoxes
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
        FeatureFlags.removeBoosterBoxes = shippedFlag
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    func testBoxesShipRemoved() {
        XCTAssertTrue(shippedFlag,
                      "booster boxes are removed from the shop in the shipping build")
        XCTAssertFalse(FeatureFlags.boosterBoxesAvailable,
                       "with the flag on the shop sells packs only")
    }

    func testAvailabilityTracksTheFlag() {
        FeatureFlags.removeBoosterBoxes = true
        XCTAssertFalse(FeatureFlags.boosterBoxesAvailable)
        FeatureFlags.removeBoosterBoxes = false
        XCTAssertTrue(FeatureFlags.boosterBoxesAvailable)
    }

    func testBoxIsPurchasableWhileTheFlagIsOff() {
        FeatureFlags.removeBoosterBoxes = false
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

    /// Flipping the flag hides the box tiles; it must not rewrite the save
    /// underneath them. Box counts already banked stay banked, so turning the
    /// feature back on is lossless.
    func testBoxHistorySurvivesTheFlagFlip() {
        FeatureFlags.removeBoosterBoxes = false
        XCTAssertNotNil(game.buyBoxPacks(set: 1))
        XCTAssertEqual(game.stats.boxesOpened, 1)
        FeatureFlags.removeBoosterBoxes = true
        XCTAssertEqual(game.stats.boxesOpened, 1,
                       "removing boxes from the shop must not erase box history")
    }

    /// The stat tiles are part of the feature, not a readout of it: a permanent
    /// "Boxes Opened 0" advertises something the shop doesn't sell.
    func testStatTilesDropBoxesWhenRemoved() {
        FeatureFlags.removeBoosterBoxes = true
        let labels = StatsView.haulTiles(packs: 3, boxes: 0, bestGrade: 0,
                                         cards: 18, ultras: 1, foils: 0).map(\.0)
        XCTAssertFalse(labels.contains("Boxes Opened"),
                       "no box tile while boxes are off the shelf")
        XCTAssertEqual(labels.first, "Packs Opened", "packs still lead the haul")
        XCTAssertEqual(labels.count, 5)
    }

    func testStatTilesKeepBoxesWhenAvailable() {
        FeatureFlags.removeBoosterBoxes = false
        let tiles = StatsView.haulTiles(packs: 3, boxes: 2, bestGrade: 10,
                                        cards: 18, ultras: 1, foils: 0)
        XCTAssertEqual(tiles.count, 6)
        XCTAssertEqual(tiles.first(where: { $0.0 == "Boxes Opened" })?.1, "2",
                       "with boxes on sale the tile reports the real count")
    }
}
