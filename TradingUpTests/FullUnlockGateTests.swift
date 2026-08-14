import XCTest
@testable import TradingUp

/// The full-version unlock gate (Option A monetization): Set 1 · Emberfall is
/// free, and *buying packs* in the paid sets (2–5) is refused until the one-time
/// unlock is active. Like the booster-box kill switch, hiding the button is not
/// enough — the purchase path itself has to say no, so no stale call site, deep
/// link, or UI test can spend cash behind the paywall.
///
/// The entitlement lives on `GameState` as plain state that StoreKit drives in
/// production and tests set directly, so both the locked and unlocked game are
/// exercised here without touching StoreKit.
@MainActor
final class FullUnlockGateTests: XCTestCase {
    private var dir: URL!
    private var shippedBoxFlag: Bool!

    override func setUp() {
        super.setUp()
        shippedBoxFlag = FeatureFlags.removeBoosterBoxes
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tu_iap_\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        FeatureFlags.removeBoosterBoxes = shippedBoxFlag
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    /// Builds a game with plenty of cash, `uniques` unique Set 1 cards already
    /// owned (to clear the progression gate independently of the paywall), and
    /// the unlock in the requested state.
    private func makeGame(uniques: Int = 0, unlocked: Bool) -> GameState {
        var core = GameCore()
        core.cash = 100_000
        if uniques > 0 {
            for i in 1...uniques {
                core.instances.append(CardInstance(cardId: String(format: "S1-%03d", i)))
            }
        }
        let game = GameState(core: core, store: SaveStore(directory: dir))
        game.setFullVersionUnlocked(unlocked)
        return game
    }

    func testFullUnlockShipsLocked() {
        let game = makeGame(unlocked: false)
        XCTAssertFalse(game.isFullVersionUnlocked,
                       "a fresh game starts locked to the free tier")
        XCTAssertFalse(game.requiresFullUnlock(set: 1), "Set 1 is always free")
        XCTAssertTrue(game.requiresFullUnlock(set: 2), "Set 2 is behind the paywall while locked")
        XCTAssertTrue(game.requiresFullUnlock(set: 5), "Set 5 is behind the paywall while locked")
    }

    func testFreeTierBuysWithoutUnlock() {
        let game = makeGame(unlocked: false)
        XCTAssertNotNil(game.buyPack(set: 1), "Set 1 packs are free to buy without the unlock")
        XCTAssertEqual(game.stats.packsOpened, 1)
        XCTAssertEqual(game.stats.moneySpent, Economy.packPrice(set: 1), accuracy: 0.001)
    }

    /// The core test: even with cash *and* enough uniques to clear the
    /// progression gate, a paid set is refused while locked — so it's the
    /// paywall, not progression, doing the blocking.
    func testPaidSetRefusedWithoutUnlock() {
        let game = makeGame(uniques: 25, unlocked: false)
        XCTAssertTrue(game.isSetUnlocked(2), "progression gate for Set 2 is cleared at 25 uniques")
        let cashBefore = game.cash
        XCTAssertNil(game.buyPack(set: 2), "a paid set must not sell a pack while locked")
        XCTAssertEqual(game.cash, cashBefore, "a refused pack must not charge the player")
        XCTAssertEqual(game.stats.packsOpened, 0, "a refused pack must not open")
    }

    func testPaidBoxesRefusedWithoutUnlock() {
        FeatureFlags.removeBoosterBoxes = false   // isolate the paywall guard from the box kill switch
        let game = makeGame(uniques: 25, unlocked: false)
        let cashBefore = game.cash
        XCTAssertNil(game.buyBoxPacks(set: 2), "a paid set must not sell a box while locked")
        XCTAssertNil(game.buyBox(set: 2), "a paid set must not sell a single-result box while locked")
        XCTAssertEqual(game.cash, cashBefore)
        XCTAssertEqual(game.stats.boxesOpened, 0)
    }

    func testUnlockOpensPaidSet() {
        let game = makeGame(uniques: 25, unlocked: true)
        XCTAssertFalse(game.requiresFullUnlock(set: 2), "the unlock opens the paid sets")
        XCTAssertNotNil(game.buyPack(set: 2), "with the unlock and progression met, Set 2 sells packs")
        XCTAssertEqual(game.stats.packsOpened, 1)
    }

    /// The unlock removes the paywall but must not *skip* progression: Set 2
    /// still needs its 25 uniques, so an unlocked-but-early game is still refused
    /// by the core's own gate.
    func testUnlockDoesNotSkipProgression() {
        let game = makeGame(uniques: 0, unlocked: true)
        XCTAssertFalse(game.requiresFullUnlock(set: 2), "paywall is lifted by the unlock")
        XCTAssertFalse(game.isSetUnlocked(2), "but progression still gates Set 2 with 0 uniques")
        XCTAssertNil(game.buyPack(set: 2), "purchase opens the paid sets, it does not skip their unlock")
        XCTAssertEqual(game.stats.packsOpened, 0)
    }

    func testSettingEntitlementTogglesTheGate() {
        let game = makeGame(unlocked: false)
        XCTAssertTrue(game.requiresFullUnlock(set: 3))
        game.setFullVersionUnlocked(true)
        XCTAssertFalse(game.requiresFullUnlock(set: 3))
        game.setFullVersionUnlocked(false)
        XCTAssertTrue(game.requiresFullUnlock(set: 3))
    }
}
