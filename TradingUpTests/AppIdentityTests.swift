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
}
