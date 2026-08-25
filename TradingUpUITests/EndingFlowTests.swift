import XCTest

/// End-to-end coverage of the v2 Season-win flow, played for real from a seeded
/// state sitting at the Championship.
///
/// Playing eight Shows by hand is far too slow for a test — or the demo video
/// `tools/capture_ending.sh` screen-records — so the state is fast-travelled via
/// the DEBUG-only launch hook:
///
///   * `TU_TEST_STATE=almost-champion` seeds a Season at the final Show (the
///     Masters Invitational) with net worth already past the Quota, so the shop
///     shows the "Make the Cut" call-to-action the instant it appears.
///
/// The test taps Make the Cut, asserts the Season Champion celebration takes the
/// screen, and that dismissing it returns to the shop.
final class EndingFlowTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["TU_TEST_STATE"] = "almost-champion"
        app.launch()
    }

    func testMakingTheChampionshipCutWinsTheSeason() throws {
        // The shop opens on the Championship with the Quota already cleared, so
        // the gold "Make the Cut" CTA is waiting.
        XCTAssertTrue(makeCut.waitForExistence(timeout: 30), "the Make the Cut CTA never appeared")
        shot("01-shop-make-the-cut")

        makeCut.tap()

        // Clearing the Championship wins the Season: the Champion celebration —
        // collector card, fireworks, and the keep / new-season choices — takes
        // over the screen.
        XCTAssertTrue(championScreen.waitForExistence(timeout: 10),
                      "the Season Champion screen never appeared after making the cut")
        // Sit on it the way a player would, so the recorded demo shows the ending
        // at its real pace before choosing.
        sleep(3)
        shot("02-champion")

        // "Keep Browsing" dismisses the celebration and drops back into the shop,
        // the Season still won.
        keepBrowsing.tap()
        XCTAssertTrue(buyPack.waitForExistence(timeout: 15), "the shop never came back after the win")
        shot("03-shop-after-win")
        sleep(2)   // linger before the demo ends
    }

    // MARK: - Element lookup

    private var buyPack: XCUIElement { app.buttons["buyPack"].firstMatch }
    private var makeCut: XCUIElement { app.buttons["makeCut"].firstMatch }
    private var keepBrowsing: XCUIElement { button(labeled: "Keep Browsing") }
    /// The Champion screen is identified by its "Keep Browsing" primary action,
    /// which exists only there.
    private var championScreen: XCUIElement { keepBrowsing }

    private func button(labeled label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
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
