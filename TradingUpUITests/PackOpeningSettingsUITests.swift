import XCTest

final class PackOpeningSettingsUITests: XCTestCase {
    private enum Mode: CaseIterable {
        case classic, gauntlet

        var direction: PackRipDirection { self == .classic ? .leftToRight : .rightToLeft }
    }

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app.terminate()
        app.launchEnvironment = ["TU_AUDIO_DISABLED": "1"]
        app.launch()
        openSettings()
        setSwitch("tapToOpenPacks", enabled: false)
        setSwitch("autoOpenPacks", enabled: false)
        app.terminate()
    }

    func testSettingsAreIndependentAndSurviveRelaunch() {
        app.launchEnvironment = ["TU_AUDIO_DISABLED": "1"]
        app.launch()
        openSettings()
        setSwitch("tapToOpenPacks", enabled: false)
        setSwitch("autoOpenPacks", enabled: false)

        setSwitch("tapToOpenPacks", enabled: true)
        XCTAssertEqual(app.switches["autoOpenPacks"].value as? String, "0")
        app.terminate()
        app.launch()
        openSettings()
        XCTAssertEqual(app.switches["tapToOpenPacks"].value as? String, "1")
        XCTAssertEqual(app.switches["autoOpenPacks"].value as? String, "0")

        setSwitch("autoOpenPacks", enabled: true)
        setSwitch("tapToOpenPacks", enabled: false)
        app.terminate()
        app.launch()
        openSettings()
        XCTAssertEqual(app.switches["tapToOpenPacks"].value as? String, "0")
        XCTAssertEqual(app.switches["autoOpenPacks"].value as? String, "1")
        setSwitch("autoOpenPacks", enabled: false)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Pack opening settings, both off"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testTapOpensTheWrapperAndKeepsEveryCardRevealInBothModes() {
        for mode in Mode.allCases {
            launch(mode, tap: true, auto: false)
            wrapperBody.tap()
            finishEveryCardReveal(in: mode)
            assertSummaryNeedsDecisions(in: mode)
        }
    }

    func testAutoOpenStillRequiresACompleteSwipeWhenTapIsOffInBothModes() {
        for mode in Mode.allCases {
            launch(mode, tap: false, auto: true)
            app.assertPackRejectsInvalidGestures(direction: mode.direction)
            app.ripOpenPack(direction: mode.direction, expectingSummary: true)
            assertSummaryNeedsDecisions(in: mode)
        }
    }

    func testTapAndAutoOpenGoStraightToSummaryWithoutResolvingThePull() {
        for mode in Mode.allCases {
            launch(mode, tap: true, auto: true)
            app.packRipSeam.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            assertSummaryNeedsDecisions(in: mode)

            switch mode {
            case .classic:
                app.buttons["Keep All"].tap()
                XCTAssertTrue(app.buttons["Keep My Collection"].waitForExistence(timeout: 8),
                              "auto-open must still defer the win until after the summary decision")
                XCTAssertFalse(app.packSummary.exists)
            case .gauntlet:
                app.buttons["gauntletAttuneCatalyst"].tap()
                XCTAssertFalse(app.buttons["gauntletAttuneCatalyst"].exists)
                XCTAssertTrue(app.buttons["gauntletKeep-S1-002"].exists)
                XCTAssertFalse(app.buttons["gauntletFinishPack"].isEnabled,
                               "attuning a Catalyst must not auto-decide any cards")
                XCTAssertEqual(rips.label, "3 rips left")
            }
        }
    }

    func testEnablingTapStillAllowsSwipingInBothModes() {
        for mode in Mode.allCases {
            launch(mode, tap: true, auto: false)
            app.ripOpenPack(direction: mode.direction)
            XCTAssertTrue(app.staticTexts["Tap for next card"].exists)
            XCTAssertFalse(app.packSummary.exists)
        }
    }

    private func launch(_ mode: Mode, tap: Bool, auto: Bool) {
        app.terminate()
        app.launchEnvironment = ["TU_AUDIO_DISABLED": "1", "TU_FORCE_UNLOCK": "1",
                                 "TU_TEST_SEED": "62"]
        switch mode {
        case .classic:
            app.launchEnvironment["TU_TEST_STATE"] = "almost-won"
            app.launchEnvironment["TU_TEST_MISSING"] = "S1-047"
        case .gauntlet:
            app.launchEnvironment["TU_TEST_GAUNTLET"] = "catalyst"
        }
        app.launch()
        openSettings()
        setSwitch("tapToOpenPacks", enabled: tap)
        setSwitch("autoOpenPacks", enabled: auto)
        app.buttons["exitToMenu"].tap()

        switch mode {
        case .classic:
            app.buttons["classicMode"].tap()
            let buy = app.buttons["buyPack"].firstMatch
            XCTAssertTrue(buy.waitForExistence(timeout: 10))
            buy.tap()
        case .gauntlet:
            app.buttons["gauntletMode"].tap()
            let resume = app.buttons["Continue"]
            XCTAssertTrue(resume.waitForExistence(timeout: 5))
            resume.tap()
        }
        app.assertPackIsSealed()
    }

    private func openSettings() {
        let settings = app.buttons["settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        settings.tap()
        XCTAssertTrue(app.switches["tapToOpenPacks"].waitForExistence(timeout: 5))
    }

    private func setSwitch(_ identifier: String, enabled: Bool) {
        let toggle = app.switches[identifier]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        for _ in 0..<4 {
            if toggle.isHittable { break }
            let scroll = app.scrollViews.firstMatch
            if toggle.frame.midY < scroll.frame.minY {
                scroll.swipeDown()
            } else {
                scroll.swipeUp()
            }
        }
        XCTAssertTrue(toggle.isHittable)
        if toggle.value as? String != (enabled ? "1" : "0") { toggle.tap() }
        XCTAssertEqual(toggle.value as? String, enabled ? "1" : "0")
    }

    private var wrapperBody: XCUICoordinate {
        let seam = app.packRipSeam
        return seam.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .withOffset(CGVector(dx: 0, dy: seam.frame.height * 2))
    }

    private var rips: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "gauntletRipsRemaining").firstMatch
    }

    private func finishEveryCardReveal(in mode: Mode) {
        // Both fixtures contain six reveal items; Gauntlet's last one is a Catalyst.
        for index in 0..<6 {
            let prompt = app.staticTexts[index == 5 ? "Tap to finish" : "Tap for next card"]
            XCTAssertTrue(prompt.waitForExistence(timeout: 5))
            XCTAssertFalse(app.packSummary.exists)
            XCTAssertFalse(app.buttons["Keep My Collection"].exists)
            if mode == .gauntlet {
                XCTAssertEqual(rips.label, "3 rips left")
            }
            prompt.tap()
        }
    }

    private func assertSummaryNeedsDecisions(in mode: Mode) {
        XCTAssertTrue(app.packSummary.waitForExistence(timeout: 5))
        XCTAssertFalse(app.packCardPrompt.exists)
        XCTAssertFalse(app.packRipSeam.exists)
        switch mode {
        case .classic:
            XCTAssertTrue(app.buttons["Keep All"].isEnabled)
            XCTAssertTrue(app.buttons.matching(NSPredicate(
                format: "label BEGINSWITH 'Sell ' AND label CONTAINS 'Duplicate'")).firstMatch.isEnabled)
            XCTAssertFalse(app.buttons["Keep My Collection"].exists,
                           "a pending win must not cover the keep/sell summary")
        case .gauntlet:
            XCTAssertEqual(rips.label, "3 rips left")
            XCTAssertTrue(app.staticTexts["5 cards + 1 Catalyst left to decide"].exists)
            XCTAssertTrue(app.buttons["gauntletAttuneCatalyst"].isHittable)
            XCTAssertTrue(app.buttons["gauntletSellCatalyst"].exists)
            XCTAssertTrue(app.buttons["gauntletKeep-S1-002"].exists)
            XCTAssertFalse(app.buttons["gauntletFinishPack"].isEnabled)
        }
    }
}
