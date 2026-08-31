import XCTest

/// App Store marketing screenshots for the v1.2.0 headline features — **Gauntlet
/// Mode** and the permanent **Binder** — the two things the original
/// `ScreenshotTests` playthrough (Classic only) can't reach.
///
/// Like `ScreenshotTests`, nothing here is mocked game state: the Gauntlet frames
/// come from a real run (enter a tier, rip a pack on the rail, keep the pulls,
/// watch the Aura climb), and the Binder frames come from the same seeded
/// completed collection the endgame pass uses — folded into the all-time Binder
/// on launch exactly as the shipping app does. It leans only on the DEBUG-only
/// launch hooks the rest of the suite already uses:
///
///   * `TU_FORCE_UNLOCK=1` flips the full-game entitlement so Gauntlet (gated
///     behind the one-time unlock) is reachable, the same override
///     `UIImprovementScreenshots` and the IAP capture use.
///   * `TU_TEST_GALLERY=share` renders the real `GauntletShareCard` on its own
///     for the "Gauntlet Cleared" frame, which a short run can't be made to reach
///     deterministically.
///
/// Driven by `tools/capture_screenshots.sh` (the `gauntlet` pass), which seeds the
/// completed save into the container first so the Binder is full. Attachment names
/// carry a numeric prefix so the exported PNGs sort after the Classic set.
final class GauntletBinderScreenshots: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(_ environment: [String: String]) {
        app.launchEnvironment = environment
        app.launch()
    }

    // MARK: - The Binder (permanent showcase)

    /// The all-time Binder, populated from the seeded completed collection: one
    /// slot per Spryte holding the best copy ever owned, with the headline
    /// filled/total and total-value roll-ups.
    func testBinderShowcase() {
        launch(["TU_FORCE_UNLOCK": "1"])

        let binder = app.buttons["binder"]
        XCTAssertTrue(binder.waitForExistence(timeout: 30), "main menu never appeared")
        binder.tap()

        XCTAssertTrue(staticText("Binder").waitForExistence(timeout: 10)
                        || gridCards.firstMatch.waitForExistence(timeout: 10),
                      "binder never opened")
        // Set 1 · Emberfall: a full grid of the best copy of each Spryte, foils and
        // grades and all, under the "Sprytes filled / value" header.
        shot("30-binder-emberfall", settle: 1.2)

        // Jump to set 5 · Umbral Reach — the priciest cards, so the Binder Value
        // header and the grid both read their richest.
        selectSet(5)
        shot("31-binder-umbral-reach", settle: 1.0)

        // A single slot blown up: the best copy on record, foil shimmer and PSA
        // slab intact.
        let card = gridCards.firstMatch
        if card.waitForExistence(timeout: 8), card.isHittable {
            card.tap()
            if doneButton.waitForExistence(timeout: 8) {
                shot("32-binder-card-detail", settle: 1.0)
                doneButton.tap()
            }
        }
    }

    // MARK: - Gauntlet Mode (a real run)

    /// Trainer select, tier select, then a live run: rip a pack off the rail, keep
    /// the pulls, and let the Aura climb toward the round's target.
    func testGauntletRun() {
        launch(["TU_FORCE_UNLOCK": "1"])

        let gauntlet = app.buttons["gauntletMode"]
        XCTAssertTrue(gauntlet.waitForExistence(timeout: 30), "gauntlet tile never appeared")
        gauntlet.tap()

        // A saved run from a prior launch raises the resume prompt; choose a fresh
        // run so we always land on Trainer select.
        let newRun = button(labeled: "New Run")
        if newRun.waitForExistence(timeout: 3) {
            newRun.tap()
            let confirm = button(labeled: "Start New Run")
            if confirm.waitForExistence(timeout: 5) { confirm.tap() }
        }
        // First-run how-to; "Let's Rip" advances to Trainer select.
        let letsRip = button(labeled: "Let's Rip")
        if letsRip.waitForExistence(timeout: 8) { letsRip.tap() }

        // Trainer select — the Madden-style five-skill graphs.
        XCTAssertTrue(staticText("Choose your Trainer").waitForExistence(timeout: 10),
                      "trainer select never appeared")
        shot("33-gauntlet-trainer-select", settle: 1.2)

        // Average Joe · Rookie is the always-available starter.
        let joe = button(labelContains: "Joe")
        XCTAssertTrue(joe.waitForExistence(timeout: 5), "starter trainer missing")
        joe.tap()

        // Tier select — Easy / Medium / Hard, with the run's rip and slot figures.
        XCTAssertTrue(staticText("Pick a Gauntlet").waitForExistence(timeout: 10),
                      "tier select never appeared")
        shot("34-gauntlet-tier-select", settle: 1.0)

        // Easy is always unlocked; entering opens the run screen.
        let easy = button(labelContains: "Easy")
        XCTAssertTrue(easy.waitForExistence(timeout: 5), "Easy tier missing")
        easy.tap()

        // The empty run HUD: Aura vs. target, cash, rips, and the five-set pack rail.
        XCTAssertTrue(ripTile.waitForExistence(timeout: 12), "pack rail never appeared")
        shot("35-gauntlet-run-start", settle: 1.0)

        // Rip one pack, tear it open, and step through the reveal — grabbing the
        // card-flip frame and the keep-or-sell showcase decision — then keep the
        // pulls so the Aura climbs before we drop back to the run HUD. One pack
        // keeps the Showcase clear of its 8-slot cap, so every pull offers a plain
        // "Keep" and the summary resolves cleanly.
        if ripTile.waitForExistence(timeout: 8), ripTile.isEnabled {
            ripTile.tap()

            // The rip presents a sealed pack (the shared RevealAnimation): tear it
            // open, then step through the card-by-card reveal. Grab one reveal frame
            // — preferring a rare/ultra flip or the saved-for-last hit slot.
            if staticText("Tap to open").waitForExistence(timeout: 8) { tapCenter() }
            _ = revealPrompt.waitForExistence(timeout: 8)

            var captured = false
            var guardCount = 0
            while isRevealing && guardCount < 16 {
                guardCount += 1
                let onHit = staticText("Tap to finish").exists   // last card = the hit
                if !captured, staticText("RARE").exists || staticText("ULTRA RARE").exists || onHit {
                    captured = true
                    shot("36-gauntlet-reveal", settle: 0.7)
                }
                tapCenter()
            }

            // The "Your Showcase" summary: each pull's keep-for-Aura vs.
            // sell-for-cash decision.
            if staticText("Your Showcase").waitForExistence(timeout: 8) {
                shot("37-gauntlet-keep-or-sell", settle: 1.0)
                keepEveryPull()
                let cont = button(labeled: "Continue")
                if cont.waitForExistence(timeout: 5), cont.isEnabled { cont.tap() }
            }
        }

        // Back on the run screen with a built-up Showcase and a climbing Aura.
        _ = ripTile.waitForExistence(timeout: 8)
        shot("38-gauntlet-run-building", settle: 1.2)
    }

    // MARK: - Gauntlet reward / share

    /// The "Gauntlet Cleared" share card — the run's Extended-Art prize and stats,
    /// rendered from the real `GauntletShareCard`.
    func testGauntletShareCard() {
        launch(["TU_TEST_GALLERY": "share"])
        XCTAssertTrue(staticText("Gauntlet Cleared").waitForExistence(timeout: 15),
                      "share card never rendered")
        shot("39-gauntlet-share-card", settle: 0.8)
    }

    // MARK: - Run helpers

    /// The first rippable pack tile on the rail (its accessibility label is
    /// "<Set> pack — Rip"); Emberfall is unlocked at the start of every run.
    private var ripTile: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'pack —' AND label CONTAINS[c] 'Rip'"))
            .firstMatch
    }

    /// Keep every pending pull on the summary, filling the Showcase.
    private func keepEveryPull() {
        var guardCount = 0
        while guardCount < 8 {
            let keep = button(labeled: "Keep")
            guard keep.waitForExistence(timeout: 2), keep.isHittable else { break }
            keep.tap()
            guardCount += 1
            usleep(300_000)
        }
    }

    private var isRevealing: Bool {
        staticText("Tap for next card").exists || staticText("Tap to finish").exists
    }

    /// The card-reveal prompt, used to wait for the first card after tearing a
    /// pack open (matches either the mid-reveal or the final-card label).
    private var revealPrompt: XCUIElement {
        app.staticTexts.matching(
            NSPredicate(format: "label == 'Tap for next card' OR label == 'Tap to finish'")
        ).firstMatch
    }

    // MARK: - Binder helpers

    private var gridCards: XCUIElementQuery { app.scrollViews.firstMatch.buttons }
    private var doneButton: XCUIElement { button(labeled: "Done") }

    /// The Binder's per-set segmented picker reads as buttons "1"…"5".
    private func selectSet(_ set: Int) {
        let label = "\(set)"
        let segment = app.segmentedControls.buttons[label]
        if segment.waitForExistence(timeout: 3), segment.isHittable { segment.tap(); return }
        let loose = button(labeled: label)
        if loose.exists, loose.isHittable { loose.tap() }
    }

    // MARK: - Element lookup

    private func button(labeled label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func button(labelContains text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func staticText(_ text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label == %@", text)).firstMatch
    }

    private func tapCenter() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        usleep(450_000)
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
