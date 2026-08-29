import XCTest

/// Screenshots for the Classic & Gauntlet UI-improvement PR.
///
/// Unlike `ScreenshotTests` (the App Store marketing set), this class exists to
/// document a specific batch of UI changes: it walks to each screen a change
/// touched and attaches a PNG. It leans on the DEBUG-only launch hooks
/// (`TU_FORCE_UNLOCK`, `TU_TEST_STATE`, `TU_TEST_GALLERY`) so every shot is
/// deterministic and needs no manual grinding. It is part of `TradingUpUITests`,
/// which CI does not run, so it never gates a build.
///
/// Capture them with:
///
///     xcodebuild test -project TradingUp.xcodeproj -scheme TradingUp \
///       -destination 'platform=iOS Simulator,name=iPhone 17' \
///       -only-testing:TradingUpUITests/UIImprovementScreenshots \
///       -resultBundlePath /tmp/tu_ui.xcresult CODE_SIGNING_ALLOWED=NO
///
/// then export the attachments:
///
///     xcrun xcresulttool export attachments --path /tmp/tu_ui.xcresult \
///       --output-path /tmp/tu_ui_shots
final class UIImprovementScreenshots: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(_ environment: [String: String]) {
        app.launchEnvironment = environment
        app.launch()
    }

    // MARK: - Main menu & Settings (req 3: resets removed)

    func testMenuAndSettings() {
        launch(["TU_FORCE_UNLOCK": "1", "TU_TEST_STATE": "almost-won"])

        XCTAssertTrue(app.buttons["classicMode"].waitForExistence(timeout: 30),
                      "main menu never appeared")
        shot("01-main-menu")

        let gear = app.buttons["settings"]
        XCTAssertTrue(gear.waitForExistence(timeout: 5))
        gear.tap()

        XCTAssertTrue(staticText("Settings").waitForExistence(timeout: 5),
                      "settings never opened")
        shot("02-settings-no-resets")
    }

    // MARK: - Gauntlet flow (req 2, 4, 5, 8)

    func testGauntletFlow() {
        launch(["TU_FORCE_UNLOCK": "1", "TU_TEST_STATE": "almost-won"])

        let gauntlet = app.buttons["gauntletMode"]
        XCTAssertTrue(gauntlet.waitForExistence(timeout: 30), "gauntlet tile never appeared")
        gauntlet.tap()

        // A gauntlet run may already be saved from a prior launch, which raises the
        // resume prompt instead of entering fresh. Choose New Run so we always land
        // on Trainer select for the shot.
        let resumeNewRun = button(labeled: "New Run")
        if resumeNewRun.waitForExistence(timeout: 3) {
            resumeNewRun.tap()
            let startNew = button(labeled: "Start New Run")
            if startNew.waitForExistence(timeout: 5) { startNew.tap() }
        }

        // The first-run how-to. "Let's Rip" advances to Trainer select. It only
        // shows until the intro's been seen once, so tapping it is optional.
        let letsRip = button(labeled: "Let's Rip")
        if letsRip.waitForExistence(timeout: 8) { letsRip.tap() }

        // Trainer select: info button aligned with Home (req 2), no locked helper
        // text (req 8).
        XCTAssertTrue(staticText("Choose your Trainer").waitForExistence(timeout: 8),
                      "trainer select never appeared")
        shot("03-gauntlet-trainer-select")

        // Joe is the always-available starter, so his card is enabled.
        let joe = button(labelContains: "Joe")
        XCTAssertTrue(joe.waitForExistence(timeout: 5), "starter trainer card missing")
        joe.tap()

        // Tier select: rip/slot figures now reflect the trainer (req 5).
        XCTAssertTrue(staticText("Pick a Gauntlet").waitForExistence(timeout: 8),
                      "tier select never appeared")
        shot("04-gauntlet-tier-select")

        // Easy is always unlocked; entering it opens the run screen.
        let easy = button(labelContains: "Easy")
        XCTAssertTrue(easy.waitForExistence(timeout: 5), "Easy tier card missing")
        easy.tap()

        // Run screen: Home square + full-width HUD row (req 4).
        Thread.sleep(forTimeInterval: 1.0)
        shot("05-gauntlet-run-topbar")
    }

    // MARK: - Classic pack summary (req 1) + New Run prompt (req 3)

    func testClassicSummaryAndNewRunPrompt() {
        launch(["TU_TEST_STATE": "almost-won"])

        let classic = app.buttons["classicMode"]
        XCTAssertTrue(classic.waitForExistence(timeout: 30), "main menu never appeared")
        classic.tap()

        // Buy and rip one pack. Owning 249/250 cards means the pull is nearly all
        // duplicates, so the summary shows the new inline Keep / Sell buttons.
        let buy = app.buttons["buyPack"]
        XCTAssertTrue(buy.waitForExistence(timeout: 15), "shop never appeared")
        // The wallet header now shows the cash number without a "$" medallion.
        shot("11-classic-top-bar")
        buy.tap()

        tapCenter()                       // tear the wrapper
        var guardCount = 0
        while isRevealing && guardCount < 14 {
            guardCount += 1
            tapCenter()
        }

        XCTAssertTrue(summaryShowing, "pack summary never appeared")
        shot("06-classic-pack-summary-keep-sell")

        // Finish and bank the pull, which counts a pack opened.
        for label in ["Keep All", "Add to Collection", "Keep My Collection"] {
            let b = button(labeled: label)
            if b.exists { b.tap(); break }
        }

        // Back to the menu, then re-enter Classic — now with progress, so the
        // Continue / New Run prompt is raised instead of a Settings reset.
        let home = button(labeled: "Home")
        if home.waitForExistence(timeout: 8) { home.tap() }

        let classicAgain = app.buttons["classicMode"]
        XCTAssertTrue(classicAgain.waitForExistence(timeout: 10), "menu never came back")
        classicAgain.tap()

        let newRun = button(labeled: "New Run")
        XCTAssertTrue(newRun.waitForExistence(timeout: 8), "resume prompt never appeared")
        shot("07-classic-new-run-prompt")

        // Choosing New Run must be confirmed, because it throws the run away.
        newRun.tap()
        let confirm = button(labeled: "Start New Run")
        XCTAssertTrue(confirm.waitForExistence(timeout: 8), "new-run confirm never appeared")
        shot("08-classic-new-run-confirm")
    }

    // MARK: - Component galleries (req 6, 7)

    func testCatalystCardGallery() {
        launch(["TU_TEST_GALLERY": "catalyst"])
        XCTAssertTrue(app.otherElements["galleryCatalyst"].waitForExistence(timeout: 10)
                      || app.images["galleryCatalyst"].waitForExistence(timeout: 2)
                      || app.staticTexts.firstMatch.waitForExistence(timeout: 5),
                      "catalyst gallery never rendered")
        Thread.sleep(forTimeInterval: 0.6)
        shot("09-catalyst-card-no-sell-tag")
    }

    func testShareCardGallery() {
        launch(["TU_TEST_GALLERY": "share"])
        XCTAssertTrue(staticText("Gauntlet Cleared").waitForExistence(timeout: 10),
                      "share card never rendered")
        Thread.sleep(forTimeInterval: 0.6)
        shot("10-gauntlet-share-card")
    }

    // MARK: - Element helpers

    private func button(labeled label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func button(labelContains text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func staticText(_ text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label == %@", text)).firstMatch
    }

    private var isRevealing: Bool {
        staticText("Tap for next card").exists || staticText("Tap to finish").exists
    }

    private var summaryShowing: Bool {
        button(labeled: "Keep All").exists
            || button(labeled: "Add to Collection").exists
            || app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Sell '")).firstMatch.exists
    }

    private func tapCenter() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        usleep(450_000)
    }

    // MARK: - Capture

    private func shot(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = "\(name).png"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
