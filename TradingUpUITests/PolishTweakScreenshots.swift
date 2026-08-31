import XCTest

/// Screenshots for the UI-polish PR: three small, targeted tweaks.
///
/// Like `UIImprovementScreenshots`, this class documents a specific batch of UI
/// changes rather than the App Store set — it walks to each touched screen and
/// attaches a PNG. It leans on the DEBUG-only launch hooks (`TU_FORCE_UNLOCK`,
/// `TU_TEST_STATE`) so every shot is deterministic. It lives in
/// `TradingUpUITests`, which CI does not run, so it never gates a build.
///
/// The three changes captured here:
///   1. Gauntlet trainer select — a locked Trainer's unlock text is no longer
///      dimmed with the rest of the card.
///   2. Classic Collection — an individual card's evolution pips read as flat
///      set-colour pips (the glow is reserved for pack rips / summaries).
///   3. Classic Stats — the "By Set" breakdown is dropped from the All Time
///      scope and kept only in This Run.
///
/// Capture them with:
///
///     xcodebuild test -project TradingUp.xcodeproj -scheme TradingUp \
///       -destination 'platform=iOS Simulator,name=iPhone 16' \
///       -only-testing:TradingUpUITests/PolishTweakScreenshots \
///       -resultBundlePath /tmp/tu_polish.xcresult CODE_SIGNING_ALLOWED=NO
///
/// then export the attachments:
///
///     xcrun xcresulttool export attachments --path /tmp/tu_polish.xcresult \
///       --output-path /tmp/tu_polish_shots
final class PolishTweakScreenshots: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(_ environment: [String: String]) {
        app.launchEnvironment = environment
        app.launch()
    }

    // MARK: - 1. Gauntlet: locked Trainer unlock text stays bright

    func testGauntletLockedTrainerUnlockText() {
        launch(["TU_FORCE_UNLOCK": "1", "TU_TEST_STATE": "almost-won"])

        let gauntlet = app.buttons["gauntletMode"]
        XCTAssertTrue(gauntlet.waitForExistence(timeout: 30), "gauntlet tile never appeared")
        gauntlet.tap()

        // A saved run raises a resume prompt; take New Run so we always land on
        // Trainer select fresh.
        let resumeNewRun = button(labeled: "New Run")
        if resumeNewRun.waitForExistence(timeout: 3) {
            resumeNewRun.tap()
            let startNew = button(labeled: "Start New Run")
            if startNew.waitForExistence(timeout: 5) { startNew.tap() }
        }

        // The first-run how-to only shows until seen once, so tapping it is optional.
        let letsRip = button(labeled: "Let's Rip")
        if letsRip.waitForExistence(timeout: 8) { letsRip.tap() }

        XCTAssertTrue(staticText("Choose your Trainer").waitForExistence(timeout: 8),
                      "trainer select never appeared")
        shot("01-gauntlet-trainer-select-top")

        // Scroll so a locked Trainer card (unlocked ones sort first) sits in view
        // with its unlock requirement — the text that must read at full strength.
        app.swipeUp()
        shot("02-gauntlet-locked-trainer-unlock-text")
        app.swipeUp()
        shot("03-gauntlet-locked-trainer-unlock-text-more")
    }

    // MARK: - 2. Classic Collection: flat (non-glowing) evolution pips

    func testCollectionCardPips() {
        launch(["TU_TEST_STATE": "almost-won"])

        enterClassic()

        openTab("Collection")
        // The set picker + progress header are always present at the top.
        XCTAssertTrue(staticText("BY SET").waitForExistence(timeout: 5)
                      || app.scrollViews.buttons.firstMatch.waitForExistence(timeout: 10),
                      "collection grid never appeared")
        shot("04-collection-grid-pips", settle: 1.0)

        // Open the first owned card (locked cards aren't buttons, so the first
        // scroll-view button is always an owned card) for the big-pip detail.
        let firstCard = app.scrollViews.buttons.element(boundBy: 0)
        if firstCard.waitForExistence(timeout: 8) {
            firstCard.tap()
            XCTAssertTrue(button(labeled: "Done").waitForExistence(timeout: 8),
                          "card detail never appeared")
            shot("05-collection-card-detail-pips", settle: 1.0)
        }
    }

    // MARK: - 3. Classic Stats: "By Set" only in This Run, not All Time

    func testStatsBySetScopes() {
        launch(["TU_TEST_STATE": "almost-won"])

        enterClassic()

        openTab("Stats")
        XCTAssertTrue(staticText("BY SET").waitForExistence(timeout: 20),
                      "This Run stats never showed the By Set breakdown")
        shot("06-stats-this-run-by-set", settle: 1.2)

        // Switch to All Time — the By Set breakdown should be gone; "RUNS" is the
        // all-time-only section that confirms the scope actually flipped.
        let allTime = segment("All Time")
        XCTAssertTrue(allTime.waitForExistence(timeout: 10), "All Time segment missing")
        allTime.tap()
        XCTAssertTrue(staticText("RUNS").waitForExistence(timeout: 10),
                      "all-time scope never rendered")
        XCTAssertFalse(staticText("BY SET").exists,
                       "By Set breakdown should be absent from the All Time scope")
        shot("07-stats-all-time-no-by-set", settle: 1.2)
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
