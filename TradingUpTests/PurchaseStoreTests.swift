import XCTest
@testable import TradingUp

@MainActor
final class PurchaseStoreTests: XCTestCase {
    private let cacheKey = "fullVersionUnlocked"
    private var isTestApp: Bool { Bundle.main.bundleIdentifier == "com.callmegreg.tradingup.test" }

    private func makeDefaults() throws -> UserDefaults {
        let name = "TradingUp.PurchaseTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    private func makeGame() throws -> GameState {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tu_purchase_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return GameState(store: SaveStore(directory: directory))
    }

    func testFreshStoreOnlyAutomaticallyUnlocksTheIsolatedTestApp() throws {
        let defaults = try makeDefaults()
        let game = try makeGame()
        let store = PurchaseStore(game: game, defaults: defaults)

        XCTAssertEqual(store.isFullVersionUnlocked, isTestApp)
        XCTAssertEqual(game.isFullVersionUnlocked, isTestApp)
        XCTAssertEqual(game.requiresFullUnlock(set: 2), !isTestApp)
        XCTAssertEqual(game.requiresFullUnlock(set: 5), !isTestApp)
        XCTAssertNil(defaults.object(forKey: cacheKey))
    }

    func testExistingPurchaseHintStillInitializesTheStore() throws {
        let defaults = try makeDefaults()
        defaults.set(true, forKey: cacheKey)
        let game = try makeGame()
        let store = PurchaseStore(game: game, defaults: defaults)

        XCTAssertTrue(store.isFullVersionUnlocked)
        XCTAssertTrue(game.isFullVersionUnlocked)
        XCTAssertTrue(defaults.bool(forKey: cacheKey))
    }

    func testAutomaticTestAccessSurvivesAllStoreOperationsWithoutAPurchase() async throws {
        try XCTSkipUnless(isTestApp, "Automatic access belongs only to the isolated test app.")
        let defaults = try makeDefaults()
        let game = try makeGame()
        let store = PurchaseStore(game: game, defaults: defaults)

        game.setFullVersionUnlocked(false)
        await store.refresh()
        XCTAssertTrue(game.isFullVersionUnlocked)

        await store.loadProducts()
        XCTAssertNil(store.fullUnlock, "The auto-unlocked test app must not fetch a product.")

        game.setFullVersionUnlocked(false)
        await store.restore()
        XCTAssertTrue(game.isFullVersionUnlocked)

        game.setFullVersionUnlocked(false)
        let unlocked = await store.purchaseFullUnlock()
        XCTAssertTrue(unlocked)
        XCTAssertTrue(store.isFullVersionUnlocked)
        XCTAssertTrue(game.isFullVersionUnlocked)
        XCTAssertNil(store.lastError)
        XCTAssertFalse(store.isWorking)
        XCTAssertNil(defaults.object(forKey: cacheKey), "Automatic access must never become a purchase hint.")
    }

    func testAutomaticTestAccessNeverCreatesOrOverwritesACachedEntitlement() async throws {
        try XCTSkipUnless(isTestApp, "Automatic access belongs only to the isolated test app.")
        for cached in [nil, false, true] as [Bool?] {
            let defaults = try makeDefaults()
            if let cached { defaults.set(cached, forKey: cacheKey) }
            let game = try makeGame()
            let store = PurchaseStore(game: game, defaults: defaults)

            XCTAssertTrue(store.isFullVersionUnlocked)
            await store.refresh()
            XCTAssertEqual(defaults.object(forKey: cacheKey) as? Bool, cached)

            let relaunched = PurchaseStore(game: game, defaults: defaults)
            XCTAssertTrue(relaunched.isFullVersionUnlocked)
            XCTAssertTrue(game.isFullVersionUnlocked)
            XCTAssertEqual(defaults.object(forKey: cacheKey) as? Bool, cached)
        }
    }

    func testAutomaticTestAccessSurvivesANewRunWithoutSkippingProgression() throws {
        try XCTSkipUnless(isTestApp, "Automatic access belongs only to the isolated test app.")
        let defaults = try makeDefaults()
        let game = try makeGame()
        let store = PurchaseStore(game: game, defaults: defaults)

        game.newGame()

        XCTAssertTrue(store.isFullVersionUnlocked)
        XCTAssertTrue(game.isFullVersionUnlocked)
        XCTAssertFalse(game.requiresFullUnlock(set: 2))
        XCTAssertFalse(game.isSetUnlocked(2))
        let cash = game.cash
        XCTAssertNil(game.buyPack(set: 2))
        XCTAssertEqual(game.cash, cash)
        XCTAssertNil(defaults.object(forKey: cacheKey))
    }
}
