import XCTest

/// Captures the redesigned Classic Mode Stats screen for PR review: one frame of
/// the "This Run" scope and one of "All Time", both from a real seeded mid-run
/// save so the ledger, the completion ring and the per-set bars all have
/// something to show. Driven by a throwaway seed + `test-without-building`, the
/// same pattern `tools/capture_screenshots.sh` uses for its endgame pass.
final class StatsLayoutScreenshotTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testStatsScopeTabs() throws {
        // Step into Classic Mode from the main menu.
        let classic = app.buttons["classicMode"].firstMatch
        XCTAssertTrue(classic.waitForExistence(timeout: 30), "main menu never appeared")
        classic.tap()

        // A save with a run already going prompts Continue vs. New Run first;
        // continue into the seeded run.
        let cont = app.buttons["Continue"].firstMatch
        if cont.waitForExistence(timeout: 5) { cont.tap() }
        // A fresh save opens the welcome intro instead; step past it if shown.
        let start = button(labeled: "Start Collecting")
        if start.waitForExistence(timeout: 2) { start.tap() }
        // A completed save can land on the win overlay; keep the collection.
        let keep = button(labeled: "Keep My Collection")
        if keep.waitForExistence(timeout: 2) { keep.tap() }

        openTab("Stats")
        XCTAssertTrue(staticText("Packs Opened").waitForExistence(timeout: 20),
                      "stats screen never appeared")
        shot("stats-this-run-top", settle: 1.2)
        // Scroll to the Haul rates + Economy ledger (Peak Net Worth, red Net Profit).
        app.swipeUp(); app.swipeUp()
        XCTAssertTrue(staticText("Peak Net Worth").waitForExistence(timeout: 5),
                      "economy ledger never appeared")
        shot("stats-this-run-economy", settle: 1.0)
        app.swipeDown(); app.swipeDown()

        // The scope control is a segmented Picker; its segments read as buttons.
        let allTime = segment("All Time")
        XCTAssertTrue(allTime.waitForExistence(timeout: 10), "All Time segment missing")
        allTime.tap()
        // "Runs" only exists in the all-time scope, so it confirms the switch.
        XCTAssertTrue(staticText("RUNS").waitForExistence(timeout: 10),
                      "all-time scope never rendered")
        shot("stats-all-time-top", settle: 1.2)
        app.swipeUp(); app.swipeUp(); app.swipeUp()
        XCTAssertTrue(staticText("Runs Played").waitForExistence(timeout: 5),
                      "all-time runs section never appeared")
        shot("stats-all-time-runs", settle: 1.0)
    }

    // MARK: - Helpers

    private func openTab(_ name: String) {
        let inBar = app.tabBars.buttons[name]
        if inBar.waitForExistence(timeout: 5) { inBar.tap(); return }
        let loose = button(labeled: name)
        if loose.waitForExistence(timeout: 5) { loose.tap() }
    }

    private func segment(_ label: String) -> XCUIElement {
        let seg = app.segmentedControls.buttons[label]
        if seg.exists { return seg }
        return button(labeled: label)
    }

    private func button(labeled label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func staticText(_ text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label == %@", text)).firstMatch
    }

    private func shot(_ name: String, settle: TimeInterval = 0.6) {
        Thread.sleep(forTimeInterval: settle)
        let png = XCUIScreen.main.screenshot().pngRepresentation
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
