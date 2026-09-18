import XCTest
@testable import TradingUp

@MainActor
final class AppIdentityTests: XCTestCase {
    func testAppIdentityMatchesItsTestHostAndPurchaseProduct() throws {
        let testBundleID = try XCTUnwrap(Bundle(for: AppIdentityTests.self).bundleIdentifier)
        let bundleID: String
        let displayName: String
        let productID: String
        switch testBundleID {
        case "com.callmegreg.tradingup.tests":
            bundleID = "com.callmegreg.tradingup"
            displayName = "Trading Up"
            productID = "com.callmegreg.tradingup.fullunlock"
        case "com.callmegreg.tradingup.test.tests":
            bundleID = "com.callmegreg.tradingup.test"
            displayName = "Trading Up Test"
            productID = "com.callmegreg.tradingup.test.fullunlock"
        default:
            XCTFail("Unexpected test bundle identifier: \(testBundleID)")
            return
        }

        XCTAssertEqual(Bundle.main.bundleIdentifier, bundleID)
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
                       displayName)
        XCTAssertEqual(PurchaseStore.fullUnlockProductID, productID)
    }

    func testAutomaticUnlockRequiresTestBuildAndExactTestBundleID() {
        let isTestApp = Bundle.main.bundleIdentifier == "com.callmegreg.tradingup.test"
        XCTAssertEqual(
            TestBuildAccess.allowsAutomaticUnlock(bundleIdentifier: "com.callmegreg.tradingup.test"),
            isTestApp,
            "Even the test bundle ID must not qualify when compiled for production."
        )

        let rejectedIDs: [String?] = [
            nil, "", "com.callmegreg.tradingup", "com.callmegreg.tradingup.tests",
            "com.callmegreg.tradingup.test.tests", "com.callmegreg.tradingup.test.extra",
            "com.callmegreg.tradingup.Test", "another.app.test",
        ]
        for bundleID in rejectedIDs {
            XCTAssertFalse(TestBuildAccess.allowsAutomaticUnlock(bundleIdentifier: bundleID),
                           "Unexpected automatic unlock for \(bundleID ?? "nil")")
        }
    }
}
