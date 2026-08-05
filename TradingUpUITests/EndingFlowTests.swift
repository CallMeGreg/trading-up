import XCTest

/// End-to-end coverage of the fix for the win/reveal collision, played for real
/// from a seeded near-complete save.
///
/// The app launches one card short of a finished collection, then rips the pack
/// that lands the last card. To keep the run short and identical every time —
/// this is also the pass `tools/capture_ending.sh` screen-records for the PR's
/// demo video — the state and the RNG are both pinned via the DEBUG-only launch
/// hooks:
///
///   * `TU_TEST_STATE=almost-won` seeds 249 of 250 cards, every other set claimed.
///   * `TU_TEST_MISSING=S1-047` holds out one rare — the set-1 pack's *hit* slot,
///     so the collection-completing card is the dramatic last one revealed.
///   * `TU_TEST_SEED=62` pins `AppRNG` so that first set-1 pack really does pull
///     S1-047 (as a foil, no less). Regenerate with the search in this repo's
///     history if the card data or pack composition ever changes.
///
/// The test asserts the celebration never cuts in over the pack reveal or its
/// keep/sell summary, and only takes the screen once the player has finished the
/// pack — and that the completed set then reads 50 of 50 rather than sticking at
/// 49, which was the bug.
final class EndingFlowTests: XCTestCase {

    /// The rare held out of the seeded collection; the pack's hit completes it.
    private static let finalCard = "S1-047"
    /// RNG seed that makes the first set-1 pack pull `finalCard`. See class docs.
    private static let seed = "62"

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["TU_TEST_STATE"] = "almost-won"
        app.launchEnvironment["TU_TEST_MISSING"] = Self.finalCard
        app.launchEnvironment["TU_TEST_SEED"] = Self.seed
        app.launch()
    }

    func testWinWaitsForThePackSummaryThenSetReadsComplete() throws {
        XCTAssertTrue(buyPack.waitForExistence(timeout: 30), "shop never appeared")
        // Set 1 is the one still one card short in the seeded state.
        XCTAssertTrue(text(containing: "49 of 50").waitForExistence(timeout: 10),
                      "seeded state should show set 1 at 49 of 50")
        shot("01-shop-49-of-50")

        XCTAssertTrue(tapBuyPack(), "couldn't buy the set-1 pack")

        XCTAssertTrue(waitForSealed(), "sealed pack never appeared")
        shot("02-sealed-pack")
        tapCenter()   // tear it open

        // Rip through every card. The win must never appear mid-reveal — that
        // collision, cutting the reveal off, was the bug.
        var card = 0
        while isRevealing && card < 12 {
            card += 1
            XCTAssertFalse(winScreen.exists, "the win overlay cut in during the pack reveal")
            shot("03-reveal-card-\(card)")
            tapCenter()
        }

        XCTAssertTrue(waitForSummary(), "pack summary never appeared")
        XCTAssertFalse(winScreen.exists, "the win overlay cut in before the pack summary decision")
        shot("04-pack-summary")

        // Keep everything: the held-out rare is new, so the collection completes.
        keepEverything()

        XCTAssertTrue(winScreen.waitForExistence(timeout: 6),
                      "the win never appeared after finishing the pack")
        // The celebration only arrives once the reveal has fully dismissed.
        XCTAssertFalse(isRevealing, "reveal should be gone before the win takes the screen")
        shot("05-win-screen")

        // Sit on the win screen the way a player would — the collector card
        // springs in under fireworks and the run is theirs to share, keep, or
        // restart — before choosing, so the recorded demo shows the ending at
        // its real pace instead of dismissing it the instant it appears.
        showcaseWin()
        keepCollection.tap()

        // The whole point of the fix: the finished set now reads complete instead
        // of sticking at 49 of 50.
        XCTAssertTrue(buyPack.waitForExistence(timeout: 15), "shop never came back after the win")
        XCTAssertTrue(text(containing: "50 of 50").waitForExistence(timeout: 10),
                      "the completed set should read 50 of 50 after keeping the collection")
        XCTAssertFalse(text(containing: "49 of 50").exists,
                       "no set should still be stuck one card short")
        shot("06-shop-complete")
        sleep(2)   // linger on the completed shop before the demo ends
    }

    // MARK: - Actions

    @discardableResult
    private func tapBuyPack() -> Bool {
        let b = buyPack
        guard b.waitForExistence(timeout: 10), b.isEnabled else { return false }
        b.tap()
        return true
    }

    /// Sit on the win screen and scroll its options into view, so the recorded
    /// demo shows the celebration at a player's pace — card entrance, fireworks,
    /// and the share / keep / play-again choices — rather than dismissing it the
    /// instant it appears. Non-essential to the assertions; it only paces the
    /// recording.
    private func showcaseWin() {
        sleep(3)                       // let the card spring in and the fireworks settle
        shot("05b-win-hero")
        // Scroll the three choices — Share / Keep My Collection / Play Again —
        // fully into view with gentle, momentum-free drags (the long initial
        // press kills the fling), so the demo shows what the player is actually
        // deciding between rather than snapping straight past it.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42))
        var tries = 0
        while !playAgain.isHittable && tries < 6 {
            start.press(forDuration: 0.5, thenDragTo: end)
            usleep(500_000)
            tries += 1
        }
        sleep(2)                       // hold on the options so they can be read
        shot("05c-win-options")
    }

    private func keepEverything() {
        for label in ["Keep All", "Add to Collection"] {
            let b = button(labeled: label)
            if b.exists { b.tap(); return }
        }
        XCTFail("no keep button on the pack summary")
    }

    private func waitForSealed() -> Bool {
        staticText("Tap to open").waitForExistence(timeout: 15)
            || staticText("Tap to tear it open").exists
    }

    private func waitForSummary() -> Bool {
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if summaryShowing { return true }
            if isRevealing { tapCenter() }
            usleep(200_000)
        }
        return false
    }

    private var isRevealing: Bool {
        staticText("Tap for next card").exists || staticText("Tap to finish").exists
    }

    private var summaryShowing: Bool {
        button(labeled: "Add to Collection").exists
            || button(labeled: "Keep All").exists
            || sellDuplicates.exists
    }

    private func tapCenter() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        usleep(600_000)   // let the flip animation land before the next tap
    }

    // MARK: - Element lookup

    private var buyPack: XCUIElement { app.buttons["buyPack"].firstMatch }
    private var keepCollection: XCUIElement { button(labeled: "Keep My Collection") }
    private var winScreen: XCUIElement { keepCollection }
    private var playAgain: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Play Again'")).firstMatch
    }
    private var sellDuplicates: XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Sell ' AND label CONTAINS 'Duplicate'")
        ).firstMatch
    }

    private func button(labeled label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func staticText(_ value: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label == %@", value)).firstMatch
    }

    private func text(containing value: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", value)).firstMatch
    }

    // MARK: - Capture

    private func shot(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
