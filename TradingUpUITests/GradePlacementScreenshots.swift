import XCTest

/// Screenshots for the "grade slab over the artwork, not the pips" change.
///
/// The PSA grade badge used to sit in the card's top-right corner, on top of the
/// evolution **stage pips**. It now pins to the top-right of the *artwork*, so a
/// graded card still shows its line progress at a glance. This class documents
/// that in both places the pips appear:
///
///   * Classic **Collection** grid — plays far enough to grade a few rares, then
///     shoots the grid (pips + slab side by side) and a single graded card.
///   * Gauntlet **Showcase** grid — rendered deterministically through the DEBUG
///     gallery (`TU_TEST_GALLERY=showcase`) so it needn't grind a whole run to
///     reach a graded Showcase card.
///
/// It leans on the DEBUG-only launch hooks so every shot is deterministic, and
/// lives in `TradingUpUITests`, which CI does not run, so it never gates a build.
///
/// Capture them with:
///
///     xcodebuild test -project TradingUp.xcodeproj -scheme TradingUp \
///       -destination 'platform=iOS Simulator,name=iPhone 17' \
///       -only-testing:TradingUpUITests/GradePlacementScreenshots \
///       -resultBundlePath /tmp/tu_grade.xcresult CODE_SIGNING_ALLOWED=NO
///
/// then export the attachments:
///
///     xcrun xcresulttool export attachments --path /tmp/tu_grade.xcresult \
///       --output-path /tmp/tu_grade_shots
final class GradePlacementScreenshots: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(_ environment: [String: String]) {
        app.launchEnvironment = environment
        app.launch()
    }

    // MARK: - 1. Classic Collection: grade slab clears the evolution pips

    func testClassicCollectionGradePlacement() {
        // Own (almost) everything, with cash to spare so grading a handful of
        // rares never runs the bankroll dry.
        launch(["TU_TEST_STATE": "almost-won", "TU_TEST_CASH": "8000"])

        enterClassic()
        openTab("Collection")

        // Narrow to Rare+ so the grid is nothing but gradable cards.
        tapFilter("Rare+")
        XCTAssertTrue(app.scrollViews.buttons.firstMatch.waitForExistence(timeout: 10),
                      "collection grid never appeared")

        gradeFirstRares(3)

        shot("01-collection-grid-grade-over-artwork", settle: 1.2)

        // A single graded card, big, so the slab-in-the-art-corner reads clearly.
        let firstCard = app.scrollViews.buttons.element(boundBy: 0)
        if firstCard.waitForExistence(timeout: 8) {
            firstCard.tap()
            if button(labeled: "Done").waitForExistence(timeout: 8) {
                shot("02-collection-card-detail-graded", settle: 1.0)
                button(labeled: "Done").tap()
            }
        }
    }

    // MARK: - 2. Gauntlet Showcase: grade slab clears the evolution pips

    func testGauntletShowcaseGradePlacement() {
        launch(["TU_TEST_GALLERY": "showcase"])

        // The grade slab renders a "PSA" label; its presence proves a graded
        // Showcase card has drawn.
        XCTAssertTrue(app.staticTexts["PSA"].firstMatch.waitForExistence(timeout: 20),
                      "gallery Showcase never rendered a graded card")
        shot("03-gauntlet-showcase-grade-over-artwork", settle: 1.2)
    }

    // MARK: - Grading

    /// Opens the first few Rare+ cards in turn and grades each one through the
    /// real detail-sheet flow, so the grid comes back showing genuine PSA slabs.
    private func gradeFirstRares(_ count: Int) {
        var graded = 0
        var index = 0
        while graded < count && index < 8 {
            let card = app.scrollViews.buttons.element(boundBy: index)
            index += 1
            guard card.waitForExistence(timeout: 5), card.isHittable else { continue }
            card.tap()
            guard button(labeled: "Done").waitForExistence(timeout: 8) else { continue }

            let grade = button(labelStartingWith: "Grade")
            if grade.waitForExistence(timeout: 2), grade.isEnabled {
                grade.tap()
                let cont = button(labeled: "Continue")
                if cont.waitForExistence(timeout: 8) { cont.tap() }
                graded += 1
            }
            if button(labeled: "Done").exists { button(labeled: "Done").tap() }
            _ = app.scrollViews.buttons.firstMatch.waitForExistence(timeout: 5)
        }
    }

    // MARK: - Navigation helpers

    /// Enter Classic Mode from the main menu, clearing whichever gate the seeded
    /// save happens to raise (resume prompt, welcome intro, or win overlay).
    private func enterClassic() {
        let classic = app.buttons["classicMode"]
        XCTAssertTrue(classic.waitForExistence(timeout: 30), "main menu never appeared")
        classic.tap()

        let cont = button(labeled: "Continue")
        if cont.waitForExistence(timeout: 5) { cont.tap() }
        let start = button(labeled: "Start Collecting")
        if start.waitForExistence(timeout: 2) { start.tap() }
        let keep = button(labeled: "Keep My Collection")
        if keep.waitForExistence(timeout: 2) { keep.tap() }
    }

    private func openTab(_ name: String) {
        let inBar = app.tabBars.buttons[name]
        if inBar.waitForExistence(timeout: 8) { inBar.tap(); return }
        let loose = button(labeled: name)
        if loose.waitForExistence(timeout: 5) { loose.tap() }
    }

    private func tapFilter(_ title: String) {
        let chip = button(labeled: title)
        if chip.waitForExistence(timeout: 5) { chip.tap() }
    }

    private func button(labeled label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func button(labelStartingWith prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    // MARK: - Capture

    private func shot(_ name: String, settle: TimeInterval = 0.6) {
        Thread.sleep(forTimeInterval: settle)
        let png = XCUIScreen.main.screenshot().pngRepresentation
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name).png"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
