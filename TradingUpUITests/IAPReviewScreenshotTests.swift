import XCTest

/// Captures the single **App Review screenshot** for the Full Collection
/// in-app purchase.
///
/// App Store Connect asks for "a screenshot of the In-App Purchase that clearly
/// shows the item or service being offered." It is used for review only and is
/// never shown on the store, so this is one real frame of the real
/// `PaywallView`, reached the way a player reaches it: tap a paid, still-locked
/// set in the shop on a fresh save.
///
/// The only staged detail is the price string: a UI-test host can't load a live
/// StoreKit product, so the DEBUG-only `TU_FAKE_PRICE` launch override renders
/// the real "$2.99" the App Store Connect product (and the bundled
/// `TradingUp.storekit`) is configured for. Everything else is the shipping
/// paywall drawing its real copy.
///
/// Run it with `tools/capture_iap_review.sh`, which builds the app, runs just
/// this test on a 6.9" iPhone, pins the status bar to 9:41, and exports the
/// attachment to `docs/app-store/`.
final class IAPReviewScreenshotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCaptureIAPReviewScreenshot() throws {
        let app = XCUIApplication()
        // Render the real configured price without a live StoreKit product
        // (DEBUG-only seam; compiled out of release).
        app.launchEnvironment["TU_FAKE_PRICE"] = "$2.99"
        app.launch()

        // First-launch explainer, then into the shop with the starting bankroll.
        // v2.0.0 opens on the main menu, so step into Classic Mode first.
        let classic = app.buttons["classicMode"].firstMatch
        XCTAssertTrue(classic.waitForExistence(timeout: 30), "main menu never appeared")
        classic.tap()

        let start = app.buttons["Start Collecting"]
        if start.waitForExistence(timeout: 30) { start.tap() }

        XCTAssertTrue(app.buttons["buyPack"].firstMatch.waitForExistence(timeout: 20),
                      "shop never appeared")

        // Set 1 · Emberfall is free and sits at the top; the paid sets and their
        // "Unlock the full game" CTA are below it, so scroll until one is on
        // screen. `unlockFullGame` is the paywall callout's accessibility id.
        let unlock = app.buttons["unlockFullGame"].firstMatch
        var swipes = 0
        while !unlock.exists && swipes < 6 {
            app.swipeUp()
            swipes += 1
            _ = unlock.waitForExistence(timeout: 1)
        }
        XCTAssertTrue(unlock.exists, "the paywall CTA never appeared in the shop")
        unlock.tap()

        // The paywall is a sheet. Its Restore control is uniquely identified and
        // lives at the bottom, so seeing it means the sheet is fully presented.
        XCTAssertTrue(app.buttons["restorePurchase"].waitForExistence(timeout: 15),
                      "the paywall never presented")
        // Let the sheet's presentation animation settle so the whole paywall —
        // header, perks, and the "$2.99 · one-time purchase" button — is on screen.
        Thread.sleep(forTimeInterval: 2.5)

        let png = XCUIScreen.main.screenshot().pngRepresentation
        let shot = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        shot.name = "iap-review-full-collection"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
