import XCTest

final class GauntletExperienceTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func testSwapPreviewsExplainLossesCompletionsAndPersistTheChoice() {
        launch("swap")
        revealAll()
        shot("after-pull-decisions")
        app.buttons["gauntletSwap-S1-048"].tap()
        let breaking = app.buttons["gauntletReplace-0"]
        XCTAssertTrue(breaking.waitForExistence(timeout: 5))
        XCTAssertTrue(breaking.label.contains("-14.82 Aura"))
        XCTAssertTrue(breaking.label.contains("Breaks a completed evolution line"))
        XCTAssertFalse(app.buttons["gauntletConfirmSwap"].isEnabled)
        shot("after-informed-swaps")
        button("Cancel").tap()
        XCTAssertTrue(app.buttons["gauntletSwap-S1-048"].exists, "cancel preserves the incoming card")

        app.buttons["gauntletSwap-S1-048"].tap()
        app.buttons["gauntletReplace-5"].tap()
        app.buttons["gauntletConfirmSwap"].tap()
        XCTAssertTrue(app.buttons["gauntletSwap-S1-006"].waitForExistence(timeout: 5))
        app.buttons["gauntletSwap-S1-006"].tap()
        let completing = app.buttons["gauntletReplace-5"]
        XCTAssertTrue(completing.waitForExistence(timeout: 5))
        XCTAssertTrue(completing.label.contains("Completes an evolution line"))
        completing.tap()
        shot("after-completing-a-line")
        app.buttons["gauntletConfirmSwap"].tap()
        app.buttons["gauntletFinishPack"].tap()
        XCTAssertTrue(app.buttons["gauntletPack-1"].waitForExistence(timeout: 5))
        XCTAssertEqual(aura.label, "Aura 60 of 92")
        button("Home").tap()
        enterGauntlet(resume: true)
        XCTAssertTrue(app.buttons["gauntletPack-1"].waitForExistence(timeout: 5))
        XCTAssertEqual(aura.label, "Aura 60 of 92", "the real swap survives Home / Continue")
    }

    func testShopKeepsEarningsStableAndExplainsPurchases() {
        launch("shop")
        XCTAssertTrue(app.staticTexts["Round 1 Cleared!"].waitForExistence(timeout: 5))
        let cash = app.staticTexts["gauntletShopCash"]
        let earnings = app.staticTexts["gauntletLastEarnings"]
        XCTAssertTrue(cash.waitForExistence(timeout: 5))
        let originalCash = cash.label
        let originalEarnings = earnings.label
        let buy = button("Buy Tidecaller packs for $42.00")
        XCTAssertTrue(buy.isHittable, "the first pack unlock must be visible without scrolling")
        XCTAssertTrue(app.buttons["gauntletNextRound"].label.contains("Bank Round 2"))
        shot("after-shop-overview")
        buy.tap()
        XCTAssertTrue(element("gauntletUnlockedPack-2").waitForExistence(timeout: 5))
        XCTAssertNotEqual(cash.label, originalCash)
        XCTAssertEqual(earnings.label, originalEarnings, "spending must not rewrite payout history")
        XCTAssertFalse(button("Buy Verdspire packs for $105.00").isEnabled)
        let details = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Earned last round'")).firstMatch
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        details.tap()
        XCTAssertTrue(app.staticTexts["Round payout"].waitForExistence(timeout: 5))
        shot("after-purchase-ledger")
        let savedCash = cash.label
        button("Home").tap()
        enterGauntlet(resume: true)
        XCTAssertTrue(cash.waitForExistence(timeout: 5))
        XCTAssertEqual(cash.label, savedCash)
        XCTAssertTrue(element("gauntletUnlockedPack-2").exists)
        XCTAssertEqual(earnings.label, originalEarnings)
    }

    func testLastRipCanBeSavedAndRescuedByGrading() {
        launch("last-pack", seed: "0")
        settleLastPack()
        shot("after-last-chance")
        button("Home").tap()
        app.terminate()
        app.launchEnvironment = ["TU_FORCE_UNLOCK": "1", "TU_TEST_SEED": "0"]
        app.launch()
        enterGauntlet(resume: true)
        XCTAssertTrue(app.buttons["gauntletReviewGrade"].waitForExistence(timeout: 5))
        gradeLastChance()
        XCTAssertEqual(app.staticTexts["gauntletGradeResult"].label, "+12.30 Aura")
        shot("after-last-chance-grade")
        app.buttons["gauntletFinishGrade"].tap()
        XCTAssertTrue(app.staticTexts["Round 1 Cleared!"].waitForExistence(timeout: 5))
    }

    func testLastChanceIsOptionalAndFailedGradesEndCleanly() {
        launch("last-pack", seed: "7")
        settleLastPack()
        app.buttons["gauntletEndRun"].tap()
        XCTAssertTrue(app.alerts["End this run?"].waitForExistence(timeout: 5))
        app.alerts.buttons["Keep Playing"].tap()
        XCTAssertTrue(app.buttons["gauntletReviewGrade"].exists)
        gradeLastChance()
        XCTAssertTrue(app.staticTexts["gauntletGradeResult"].label.hasPrefix("-"))
        app.buttons["gauntletFinishGrade"].tap()
        XCTAssertTrue(app.staticTexts["Run Over"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["FINAL AURA"].exists)
        shot("after-run-summary")

        launch("last-pack")
        settleLastPack()
        app.buttons["gauntletEndRun"].tap()
        app.alerts.buttons["End Run"].tap()
        XCTAssertTrue(app.staticTexts["Run Over"].waitForExistence(timeout: 5))
    }

    func testShopRemainsUsableAtLargeText() {
        launch("shop", largeText: true)
        let buy = button("Buy Tidecaller packs for $42.00")
        scrollTo(buy, in: app.scrollViews["gauntletShopOffers"])
        XCTAssertTrue(buy.isHittable)
        XCTAssertTrue(app.buttons["gauntletNextRound"].isHittable)
        shot("after-shop-large-text")
        buy.tap()
        XCTAssertTrue(element("gauntletUnlockedPack-2").waitForExistence(timeout: 5))
    }

    func testPlaysAFreshEasyRunThroughTheBinderReward() {
        launch("fresh", seed: "0")
        let trainer = app.buttons["gauntletTrainer-neutral"]
        XCTAssertTrue(trainer.waitForExistence(timeout: 5))
        trainer.tap()
        app.buttons["gauntletTier-easy"].tap()
        XCTAssertTrue(app.buttons["gauntletPack-1"].waitForExistence(timeout: 5))
        shot("after-fresh-run")

        for _ in 0..<60 {
            if app.staticTexts["Claim Extended Art"].exists {
                shot("after-playtested-reward")
                let reward = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'gauntletReward-'")).firstMatch
                XCTAssertTrue(reward.exists)
                reward.tap()
                XCTAssertTrue(app.staticTexts["Gauntlet Complete"].waitForExistence(timeout: 5))
                shot("after-playtested-win")
                return
            }
            XCTAssertFalse(app.staticTexts["Run Over"].exists, "the scripted Easy run should remain winnable")
            if app.buttons["gauntletNextRound"].exists {
                let buys = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Buy ' AND label CONTAINS ' packs for ' AND enabled == true"))
                for _ in 0..<4 {
                    let buy = buys.firstMatch
                    if !buy.exists { break }
                    scrollTo(buy, in: app.scrollViews["gauntletShopOffers"])
                    buy.tap()
                }
                app.buttons["gauntletNextRound"].tap()
                continue
            }
            if app.buttons["gauntletReviewGrade"].exists {
                gradeLastChance()
                app.buttons["gauntletFinishGrade"].tap()
                continue
            }
            let packs = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'gauntletPack-' AND enabled == true"))
            XCTAssertGreaterThan(packs.count, 0)
            packs.element(boundBy: packs.count - 1).tap()
            revealAll()
            resolvePull()
            app.buttons["gauntletFinishPack"].tap()
        }
        XCTFail("Easy playthrough exceeded its bounded action budget")
    }

    private func launch(_ scenario: String, seed: String = "0", largeText: Bool = false) {
        app.launchArguments = largeText
            ? ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL"] : []
        app.launchEnvironment = ["TU_FORCE_UNLOCK": "1", "TU_TEST_GAUNTLET": scenario,
                                 "TU_TEST_SEED": seed]
        app.launch()
        enterGauntlet(resume: scenario != "fresh")
    }

    private func enterGauntlet(resume: Bool) {
        let gauntlet = app.buttons["gauntletMode"]
        XCTAssertTrue(gauntlet.waitForExistence(timeout: 30))
        gauntlet.tap()
        if resume {
            let continueButton = button("Continue")
            XCTAssertTrue(continueButton.waitForExistence(timeout: 5))
            continueButton.tap()
        }
    }

    private func revealAll() {
        let reveal = app.buttons["gauntletRevealAll"]
        XCTAssertTrue(reveal.waitForExistence(timeout: 5))
        reveal.tap()
        XCTAssertTrue(app.staticTexts["Build your Showcase"].waitForExistence(timeout: 5))
    }

    private func settleLastPack() {
        revealAll()
        app.buttons["gauntletSell-S1-001"].tap()
        XCTAssertTrue(app.buttons["gauntletFinishPack"].label.contains("Review last chance"))
        app.buttons["gauntletFinishPack"].tap()
        XCTAssertTrue(app.buttons["gauntletReviewGrade"].waitForExistence(timeout: 5))
    }

    private func gradeLastChance() {
        app.buttons["gauntletReviewGrade"].tap()
        let grade = app.buttons["gauntletGradeCard"]
        scrollTo(grade, in: app.scrollViews["gauntletCardDetails"])
        XCTAssertTrue(grade.isHittable)
        grade.tap()
        let finish = app.buttons["gauntletFinishGrade"]
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        scrollTo(finish, in: app.scrollViews["gauntletCardDetails"])
    }

    private func resolvePull() {
        let summary = app.scrollViews["gauntletSummaryScroll"]
        for _ in 0..<8 {
            if app.buttons["gauntletFinishPack"].isEnabled { return }
            let keep = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'gauntletKeep-'")).firstMatch
            if keep.exists {
                scrollTo(keep, in: summary)
                keep.tap()
                continue
            }
            let swap = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'gauntletSwap-'")).firstMatch
            if swap.exists {
                let cardId = String(swap.identifier.dropFirst("gauntletSwap-".count))
                scrollTo(swap, in: summary)
                swap.tap()
                let choices = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'gauntletReplace-'"))
                let best = choices.firstMatch
                XCTAssertTrue(best.waitForExistence(timeout: 5))
                if best.label.contains("+") {
                    best.tap()
                    app.buttons["gauntletConfirmSwap"].tap()
                } else {
                    button("Cancel").tap()
                    let sell = app.buttons["gauntletSell-\(cardId)"]
                    scrollTo(sell, in: summary)
                    sell.tap()
                }
                continue
            }
            let attune = button("Attune")
            if attune.exists {
                scrollTo(attune, in: summary)
                attune.tap()
            } else {
                let sell = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Sell '")).firstMatch
                XCTAssertTrue(sell.exists, "every unresolved item needs an available decision")
                scrollTo(sell, in: summary)
                sell.tap()
            }
        }
        XCTAssertTrue(app.buttons["gauntletFinishPack"].isEnabled)
    }

    private func scrollTo(_ target: XCUIElement, in scroll: XCUIElement) {
        for _ in 0..<5 {
            if target.exists && target.isHittable { return }
            scroll.swipeUp()
        }
    }

    private var aura: XCUIElement { element("gauntletAura") }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func button(_ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func shot(_ name: String) {
        Thread.sleep(forTimeInterval: 0.5)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
