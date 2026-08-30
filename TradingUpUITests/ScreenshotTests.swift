import XCTest

/// Plays the game for real — from a fresh save — and captures App Store
/// marketing screenshots along the way.
///
/// Nothing here is mocked: the run buys packs with the $100 the game starts you
/// with, rips them card by card, sells the duplicates it pulls, grades a rare,
/// and browses the collection it actually built. Every frame is a real device
/// screenshot at native resolution, which is exactly what App Store Connect
/// wants.
///
/// Run it with `tools/capture_screenshots.sh`, which wipes the app container
/// first (so the save really is fresh), pins the status bar to 9:41, and exports
/// the attachments as numbered PNGs.
final class ScreenshotTests: XCTestCase {

    /// App Store Connect accepts at most 10 screenshots per display size; we
    /// capture a wider set to pick from, but the two passes together stay under
    /// 30 frames.
    private static let playthroughShots = 24
    private static let endgameShots = 6

    private var app: XCUIApplication!
    private var shotIndex = 0
    private var shotBase = 0
    private var shotCap = ScreenshotTests.playthroughShots

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    // MARK: - The playthrough

    func testPlaythroughCapturesAppStoreScreenshots() throws {
        try onboarding()
        try firstPack()
        try keepRippingPacks()
        try browseCollection()
        try gradeARare()
        try statsAndProgress()
        try shopAfterUnlockingSetTwo()

        XCTAssertGreaterThanOrEqual(shotIndex, 12,
                                    "expected a full marketing set, captured \(shotIndex)")
    }

    /// Late-game showcase: the win celebration, a finished set, and the PSA 10
    /// grading jackpot — the parts of the game a $100 starting bankroll can't
    /// reach in a three-minute run. `tools/capture_screenshots.sh` seeds a
    /// completed save before running this, so everything on screen is still the
    /// real app rendering real state.
    ///
    /// The booster-box pass at the end is dormant: boxes are off the shelf behind
    /// `FeatureFlags.removeBoosterBoxes`, so `buyBox` never appears and the pass
    /// no-ops. It's kept so the shots come back for free if boxes ever return.
    func testEndgameShowcaseScreenshots() throws {
        shotBase = Self.playthroughShots
        shotCap = Self.endgameShots

        // The win overlay lives inside Classic Mode, so step in from the menu.
        try enterClassicMode()

        let keep = button(labeled: "Keep My Collection")
        try XCTSkipUnless(keep.waitForExistence(timeout: 30),
                          "no completed-collection save was seeded; skipping the endgame pass")

        shot("win-master-collector", settle: 1.5)
        keep.tap()

        openTab("Collection")
        XCTAssertTrue(gridCards.firstMatch.waitForExistence(timeout: 15))
        shot("collection-set-complete", settle: 1.2)

        openTab("Shop")
        XCTAssertTrue(buyPack.waitForExistence(timeout: 15))
        shot("shop-all-sets-unlocked", settle: 1.0)

        captureGemMintGrade()

        // No-op while boxes are off the shelf; the shop never renders this button.
        let box = buyBox
        guard box.waitForExistence(timeout: 10), box.isEnabled else { return }
        box.tap()

        XCTAssertTrue(waitForSealed(), "sealed booster box never appeared")
        shot("booster-box-sealed", settle: 1.2)
        tapCenter()

        var guardCount = 0
        while isRevealing && guardCount < 12 {
            guardCount += 1
            tapCenter()
        }
        if waitForSummary() {
            shot("booster-box-summary", settle: 1.2)
            finishSummary()
        }
    }

    // MARK: Steps

    /// The first-launch explainer, then into the shop with the starting $100.
    private func onboarding() throws {
        // v2.0.0 opens on the main menu; capture it, then step into Classic Mode
        // where the welcome explainer and the game itself live.
        let classic = classicModeButton
        XCTAssertTrue(classic.waitForExistence(timeout: 30), "main menu never appeared")
        shot("main-menu", settle: 1.4)
        classic.tap()

        let start = button(labeled: "Start Collecting")
        XCTAssertTrue(start.waitForExistence(timeout: 30), "welcome screen never appeared")
        shot("welcome", settle: 1.2)

        start.tap()
        XCTAssertTrue(buyPack.waitForExistence(timeout: 15), "shop never appeared")
        shot("shop-fresh-start", settle: 1.0)

        // The locked sets further down the shop explain how the game opens up.
        app.swipeUp()
        shot("shop-locked-sets", settle: 0.8)
        app.swipeDown()
        _ = buyPack.waitForExistence(timeout: 5)
    }

    /// Pack one, in full: sealed wrapper, three card flips, and the summary.
    private func firstPack() throws {
        XCTAssertTrue(tapBuyPack(), "couldn't afford the very first pack")

        XCTAssertTrue(waitForSealed(), "sealed pack never appeared")
        shot("pack-sealed", settle: 1.2)
        tapThroughPack(captureFirst: 3, prefix: "pack-reveal")

        XCTAssertTrue(waitForSummary(), "pack summary never appeared")
        shot("pack-summary-all-new", settle: 1.0)
        finishSummary()
    }

    /// Packs two onward. Sells the duplicates it pulls to stretch the bankroll,
    /// and grabs the moments worth marketing when they happen: a rare or ultra
    /// flip, the tap-a-duplicate decision sheet, a completed evolution-line
    /// bonus, and the summary where some cards are new and some are extras.
    private func keepRippingPacks() throws {
        var gotHit = false
        var gotDuplicateSheet = false
        var gotMixedSummary = false
        var gotBonus = false

        for pack in 2...9 {
            guard tapBuyPack() else { break }   // out of cash for set 1 packs
            guard waitForSealed() else { break }
            tapCenter()

            // Flip through, pausing on the first rare/ultra we see.
            var guard1 = 0
            while isRevealing && guard1 < 12 {
                guard1 += 1
                if !gotHit, staticText("RARE").exists || staticText("ULTRA").exists {
                    gotHit = true
                    shot("pack-reveal-rare-hit", settle: 0.9)
                }
                tapCenter()
            }

            guard waitForSummary() else { break }

            if !gotBonus, bonusBannerVisible {
                gotBonus = true
                shot("pack-summary-evolution-bonus", settle: 1.0)
            }

            let sell = sellDuplicates
            if sell.exists {
                if !gotMixedSummary {
                    gotMixedSummary = true
                    shot("pack-summary-new-and-dupes", settle: 1.0)
                }
                if !gotDuplicateSheet {
                    gotDuplicateSheet = captureDuplicateSheet()
                }
            }
            finishSummary(preferSelling: true)

            _ = buyPack.waitForExistence(timeout: 10)
            if pack == 4 { shot("shop-collection-growing", settle: 0.8) }
            if gameOverShowing { break }
        }

        XCTAssertFalse(gameOverShowing, "went bankrupt before the collection shots")
        shot("shop-after-a-few-packs", settle: 0.8)
    }

    /// The collection tab: the grid of what you own against what you don't,
    /// the filters, and a single card blown up with its evolution line.
    private func browseCollection() throws {
        openTab("Collection")
        XCTAssertTrue(gridCards.firstMatch.waitForExistence(timeout: 15),
                      "collection grid never appeared")
        shot("collection-grid", settle: 1.2)

        app.swipeUp()
        shot("collection-locked-silhouettes", settle: 0.8)
        app.swipeDown()

        tapFilter("Dupes")
        shot("collection-filter-dupes", settle: 0.9)
        tapFilter("Dupes")

        tapFilter("Rare+")
        shot("collection-filter-rare", settle: 0.9)

        let card = gridCards.firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "no owned rare to open")
        card.tap()
        XCTAssertTrue(doneButton.waitForExistence(timeout: 10), "card detail never opened")
        shot("card-detail-evolution-line", settle: 1.2)
    }

    /// Grading: pay the fee on a rare and roll a PSA score. The reveal overlay
    /// is the single most game-y moment in the app, so it earns a screenshot.
    private func gradeARare() throws {
        let grade = button(labelStartingWith: "Grade")
        if grade.waitForExistence(timeout: 5), grade.isEnabled {
            grade.tap()
            let cont = button(labeled: "Continue")
            if cont.waitForExistence(timeout: 10) {
                shot("grading-psa-reveal", settle: 1.2)
                cont.tap()
            }
            shot("card-detail-graded-copy", settle: 1.0)
        }
        if doneButton.exists { doneButton.tap() }
        tapFilter("Rare+")   // clear the filter again
    }

    /// The grading jackpot, played for rather than staged. PSA 10 is a 10% roll,
    /// so the one card the playthrough grades almost never lands on it — but the
    /// ×5 payoff is the reason grading exists, and the marketing strip wants to
    /// show it. From the seeded collection (every card owned, $4,200 banked)
    /// this grades ungraded rares one after another and shoots the reveal the
    /// first time a 10 comes up. It is bounded on both ends — attempts and cards
    /// tried — so a cold streak costs a minute, not the pass: if no 10 turns up,
    /// the shot is simply skipped rather than faked.
    private func captureGemMintGrade(maxAttempts: Int = 30) {
        openTab("Collection")
        guard gridCards.firstMatch.waitForExistence(timeout: 15) else { return }
        tapFilter("Rare+")

        var attempts = 0
        // The set picker is the app's own source of truth for how many sets
        // there are, so this doesn't need updating if a sixth ever ships.
        let setCount = max(app.segmentedControls.firstMatch.buttons.count, 1)
        for set in 1...setCount where attempts < maxAttempts {
            selectSet(set)
            guard gridCards.firstMatch.waitForExistence(timeout: 10) else { continue }

            for index in 0..<gridCards.count where attempts < maxAttempts {
                let card = gridCards.element(boundBy: index)
                guard card.exists, card.isHittable else { continue }
                card.tap()
                guard doneButton.waitForExistence(timeout: 10) else { continue }

                let grade = button(labelStartingWith: "Grade")
                if grade.waitForExistence(timeout: 2), grade.isEnabled {
                    attempts += 1
                    grade.tap()
                    let cont = button(labeled: "Continue")
                    if cont.waitForExistence(timeout: 10) {
                        if staticText("PSA 10").exists {
                            shot("grading-gem-mint", settle: 1.0)
                            cont.tap()
                            if doneButton.exists { doneButton.tap() }
                            return
                        }
                        cont.tap()
                    }
                }
                if doneButton.exists { doneButton.tap() }
                _ = gridCards.firstMatch.waitForExistence(timeout: 5)
            }
        }
    }

    /// The stats tab — run totals, per-set progress and the all-time record.
    private func statsAndProgress() throws {
        openTab("Stats")
        XCTAssertTrue(staticText("Packs Opened").waitForExistence(timeout: 15),
                      "stats screen never appeared")
        shot("stats-run-summary", settle: 1.2)
        app.swipeUp()
        shot("stats-set-progress", settle: 0.9)
    }

    /// Back to the shop, where crossing 25 unique cards has opened up set 2 and
    /// its pricier packs.
    private func shopAfterUnlockingSetTwo() throws {
        openTab("Shop")
        XCTAssertTrue(buyPack.waitForExistence(timeout: 15), "shop never came back")
        app.swipeUp()
        shot("shop-set-two-unlocked", settle: 1.0)
    }

    // MARK: - Pack helpers

    /// From the main menu, open Classic Mode and wait for it to settle.
    private func enterClassicMode() throws {
        let classic = classicModeButton
        XCTAssertTrue(classic.waitForExistence(timeout: 30), "main menu never appeared")
        classic.tap()
    }

    @discardableResult
    private func tapBuyPack() -> Bool {
        let b = buyPack
        guard b.waitForExistence(timeout: 10), b.isEnabled else { return false }
        b.tap()
        return true
    }

    /// Taps through every card in the pack, screenshotting the first `captureFirst`.
    private func tapThroughPack(captureFirst: Int, prefix: String) {
        tapCenter()   // tear open the wrapper
        var captured = 0
        var guardCount = 0
        while isRevealing && guardCount < 12 {
            guardCount += 1
            if captured < captureFirst {
                captured += 1
                shot("\(prefix)-\(captured)", settle: 0.9)
            }
            tapCenter()
        }
    }

    /// Dismisses a summary. `preferSelling` takes the shop's buylist offer on
    /// the pack's extras, which is what keeps the run solvent long enough to
    /// reach the collection screens.
    private func finishSummary(preferSelling: Bool = false) {
        if preferSelling, sellDuplicates.exists { sellDuplicates.tap(); return }
        for label in ["Add to Collection", "Keep All"] {
            let b = button(labeled: label)
            if b.exists { b.tap(); return }
        }
        if sellDuplicates.exists { sellDuplicates.tap() }
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
            usleep(250_000)
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

    private var bonusBannerVisible: Bool {
        app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'evolution' OR label CONTAINS[c] 'set complete'")
        ).firstMatch.exists
    }

    private var gameOverShowing: Bool {
        app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'game over' OR label CONTAINS[c] 'went broke'")
        ).firstMatch.exists
    }

    /// A pulled card that's still awaiting a keep-or-sell decision. Summary
    /// cards aren't buttons — they're plain views with a tap gesture — so the
    /// per-card rarity chip is used as a handle to tap the card itself. New
    /// cards ignore the tap, so walking the grid finds a duplicate.
    @discardableResult
    private func captureDuplicateSheet() -> Bool {
        let chips = app.staticTexts.matching(
            NSPredicate(format: "label IN {'COMMON', 'UNCOMMON', 'RARE', 'ULTRA RARE'}")
        )
        for index in 0..<min(chips.count, 6) {
            let chip = chips.element(boundBy: index)
            guard chip.exists else { continue }
            chip.tap()
            if button(labelStartingWith: "Sell for").waitForExistence(timeout: 3) {
                shot("duplicate-keep-or-sell", settle: 0.8)
                // Dismiss by keeping the copy — the "Sell N Duplicates" button
                // below still offers the rest, so the run's cash isn't affected.
                let keep = button(labeled: "Keep in collection")
                if keep.exists { keep.tap() } else { button(labelStartingWith: "Sell for").tap() }
                _ = summaryButtonsSettled()
                return true
            }
        }
        return false
    }

    /// Waits for the summary's bottom buttons to come back after the
    /// keep-or-sell sheet closes.
    private func summaryButtonsSettled() -> Bool {
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline {
            if summaryShowing { return true }
            usleep(200_000)
        }
        return false
    }

    // MARK: - Element lookup

    private var buyPack: XCUIElement { app.buttons["buyPack"].firstMatch }
    private var buyBox: XCUIElement { app.buttons["buyBox"].firstMatch }
    /// The main-menu tile into the original game.
    private var classicModeButton: XCUIElement { app.buttons["classicMode"].firstMatch }
    /// Anchored on "Duplicate" so it can't collide with the keep-or-sell
    /// sheet's "Sell for $x" button while that sheet is open.
    private var sellDuplicates: XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Sell ' AND label CONTAINS 'Duplicate'")
        ).firstMatch
    }
    private var doneButton: XCUIElement { button(labeled: "Done") }
    private var gridCards: XCUIElementQuery { app.scrollViews.firstMatch.buttons }

    private func button(labeled label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func button(labelStartingWith prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    private func staticText(_ text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label == %@", text)).firstMatch
    }

    private func tapFilter(_ title: String) {
        let chip = button(labeled: title)
        if chip.waitForExistence(timeout: 5) { chip.tap() }
    }

    /// Switches the collection's set picker. It's a segmented `Picker`, which
    /// reads as buttons "1"-"5" inside a segmented control on iPhone but can
    /// surface as loose buttons elsewhere, so try both.
    private func selectSet(_ set: Int) {
        let label = "\(set)"
        let segment = app.segmentedControls.buttons[label]
        if segment.waitForExistence(timeout: 3), segment.isHittable { segment.tap(); return }
        let loose = button(labeled: label)
        if loose.exists, loose.isHittable { loose.tap() }
    }

    /// The tab bar is a floating pill on iPad and a classic bar on iPhone, so
    /// fall back to a plain button lookup rather than assuming either.
    private func openTab(_ name: String) {
        let inBar = app.tabBars.buttons[name]
        if inBar.waitForExistence(timeout: 5) { inBar.tap(); return }
        let loose = button(labeled: name)
        if loose.waitForExistence(timeout: 5) { loose.tap() }
    }

    private func tapCenter() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        usleep(450_000)   // let the flip animation land before the next tap
    }

    // MARK: - Capture

    /// Attaches a full-resolution PNG of the whole screen. The name carries the
    /// order, so the exported files sort into playthrough sequence.
    private func shot(_ name: String, settle: TimeInterval = 0.6) {
        guard shotIndex < shotCap else { return }
        Thread.sleep(forTimeInterval: settle)
        shotIndex += 1
        let png = XCUIScreen.main.screenshot().pngRepresentation
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = String(format: "%02d-%@", shotBase + shotIndex, name)
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
