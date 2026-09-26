import XCTest
import UIKit

final class GauntletExperienceTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func testSwapPreviewsExplainLossesCompletionsAndPersistTheChoice() {
        launch("swap")
        revealPack()
        XCTAssertEqual(rips.label, "2 rips left")
        shot("after-pull-decisions")
        app.buttons["gauntletSwap-S1-048"].tap()
        let breaking = app.buttons["gauntletReplace-0"]
        XCTAssertTrue(breaking.waitForExistence(timeout: 5))
        XCTAssertTrue(breaking.label.contains("-14.82 Aura"))
        assertConciseSwapCopy()
        XCTAssertTrue(breaking.label.contains("3 of 3 stages in Showcase"))
        XCTAssertTrue(breaking.label.contains("series complete"))
        XCTAssertTrue(breaking.label.contains("Current price $0.36"))
        XCTAssertFalse(breaking.label.contains("Sell"))
        XCTAssertEqual(element("gauntletSwapIncomingSeries").label, "Single card")
        XCTAssertFalse(app.buttons["gauntletConfirmSwap"].isEnabled)
        scrollTo(breaking, in: app.scrollViews["gauntletSwapOptions"])
        shot("after-informed-swaps")
        button("Cancel").tap()
        XCTAssertTrue(app.buttons["gauntletSwap-S1-048"].exists, "cancel preserves the incoming card")

        app.buttons["gauntletSwap-S1-048"].tap()
        app.buttons["gauntletReplace-5"].tap()
        XCTAssertTrue(app.buttons["gauntletConfirmSwap"].label.contains("No cash paid"))
        XCTAssertFalse(app.buttons["gauntletConfirmSwap"].label.contains("sell"))
        app.buttons["gauntletConfirmSwap"].tap()
        XCTAssertTrue(app.buttons["gauntletSwap-S1-006"].waitForExistence(timeout: 5))
        app.buttons["gauntletSwap-S1-006"].tap()
        let completing = app.buttons["gauntletReplace-5"]
        XCTAssertTrue(completing.waitForExistence(timeout: 5))
        assertConciseSwapCopy()
        XCTAssertTrue(completing.label.contains("Single card"))
        XCTAssertTrue(element("gauntletSwapIncomingSeries").label
            .contains("Stage 3 of 3, 2 of 3 stages in Showcase"))
        XCTAssertFalse(element("gauntletSwapIncomingSeries").label.contains("Gold pip"))
        XCTAssertFalse(app.staticTexts["Gold pip = incoming stage"].exists)
        let linemates = element("gauntletSwapLinemates")
        XCTAssertTrue(linemates.waitForExistence(timeout: 5))
        XCTAssertTrue(linemates.label.contains("Pebblit"))
        XCTAssertTrue(linemates.label.contains("Boulderkin"))
        let matchingOption = app.buttons["gauntletReplace-3"]
        XCTAssertTrue(matchingOption.label.contains("SAME LINE"))
        XCTAssertFalse(completing.label.contains("SAME LINE"))
        scrollTo(matchingOption, in: app.scrollViews["gauntletSwapOptions"])
        shot("gauntlet-swap-line-cue")
        scrollTo(completing, in: app.scrollViews["gauntletSwapOptions"])
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
        XCTAssertEqual(app.buttons["gauntletNextRound"].label, "Bank Round 2")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS 'interest at the next clear'")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Round 2 ahead"].exists)
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
        XCTAssertTrue(app.staticTexts["Interest"].exists, "earned interest still belongs in the payout history")
        XCTAssertFalse(app.staticTexts["Already included in your cash. Purchases don't change this payout."].exists)
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
        app.launchEnvironment = ["TU_FORCE_UNLOCK": "1", "TU_TEST_SEED": "0",
                                 "TU_AUDIO_DISABLED": "1"]
        app.launch()
        enterGauntlet(resume: true)
        XCTAssertTrue(app.buttons["gauntletEndRun"].waitForExistence(timeout: 5))
        gradeLastChance()
        XCTAssertEqual(app.staticTexts["gradeResultValue"].label, "PSA 9")
        XCTAssertTrue(app.staticTexts["Was"].exists)
        XCTAssertTrue(app.staticTexts["Now"].exists)
        shot("after-last-chance-grade")
        app.buttons["gradeResultContinue"].tap()
        XCTAssertTrue(app.staticTexts["Round 1 Cleared!"].waitForExistence(timeout: 5))
    }

    func testLastChanceIsOptionalAndFailedGradesEndCleanly() {
        launch("last-pack", seed: "7")
        settleLastPack()
        app.buttons["gauntletEndRun"].tap()
        XCTAssertTrue(app.alerts["End this run?"].waitForExistence(timeout: 5))
        app.alerts.buttons["Keep Playing"].tap()
        XCTAssertTrue(app.buttons["gauntletShowcase-0"].isHittable)
        gradeLastChance()
        XCTAssertEqual(app.staticTexts["gradeResultValue"].label, "PSA 7")
        app.buttons["gradeResultContinue"].tap()
        XCTAssertTrue(app.staticTexts["Run Over"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["FINAL AURA"].exists)
        XCTAssertFalse(app.staticTexts["TARGET"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH 'Your best pulls'")).firstMatch.exists)
        XCTAssertTrue(button("New Run").isHittable)
        XCTAssertTrue(button("Back to Menu").isHittable)
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

    func testSwapPricesReflectGradesAndFoilsInsteadOfSaleProceeds() {
        launch("graded-swap")
        revealPack()
        app.buttons["gauntletSwap-S1-048"].tap()
        let discounted = app.buttons["gauntletReplace-0"]
        XCTAssertTrue(discounted.waitForExistence(timeout: 5))
        XCTAssertTrue(discounted.label.contains("Current price $0.09"))
        XCTAssertTrue(discounted.label.contains("PSA 3"))
        let boosted = app.buttons["gauntletReplace-2"]
        XCTAssertTrue(boosted.label.contains("Current price $6.80"))
        XCTAssertTrue(boosted.label.contains("PSA 9"))
        let foil = app.buttons["gauntletReplace-5"]
        XCTAssertTrue(foil.label.contains("Current price $0.87"))
        XCTAssertTrue(foil.label.contains("Foil"))
        scrollTo(boosted, in: app.scrollViews["gauntletSwapOptions"])
        shot("after-graded-swap-prices")
    }

    func testSwapSeriesAndConfirmationRemainUsableAtLargeText() {
        launch("swap", largeText: true)
        revealPack()
        let swap = app.buttons["gauntletSwap-S1-006"]
        scrollTo(swap, in: app.scrollViews["gauntletSummaryScroll"])
        swap.tap()
        let choice = app.buttons["gauntletReplace-5"]
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        assertConciseSwapCopy()
        scrollTo(choice, in: app.scrollViews["gauntletSwapOptions"])
        choice.tap()
        let confirm = app.buttons["gauntletConfirmSwap"]
        XCTAssertTrue(confirm.isEnabled)
        XCTAssertTrue(confirm.isHittable)
        XCTAssertTrue(confirm.label.contains("No cash paid"))
        shot("after-swap-large-text")
        confirm.tap()
        XCTAssertTrue(app.buttons["gauntletSell-S1-048"].waitForExistence(timeout: 5))
    }

    func testCatalystIsTheFirstDecisionInThePackSummary() {
        launch("catalyst")
        revealPack()
        let attune = app.buttons["gauntletAttuneCatalyst"]
        let keep = app.buttons["gauntletKeep-S1-002"]
        XCTAssertTrue(attune.waitForExistence(timeout: 5))
        XCTAssertTrue(attune.isHittable, "the Catalyst decision should be visible without scrolling")
        XCTAssertLessThan(attune.frame.minY, keep.frame.minY)
        XCTAssertFalse(app.buttons["gauntletFinishPack"].isEnabled)
        shot("after-catalyst-first")
        attune.tap()
        XCTAssertFalse(attune.exists)
        XCTAssertFalse(app.buttons["gauntletSellCatalyst"].exists)
        XCTAssertTrue(keep.exists, "attuning does not decide any of the remaining cards")
        XCTAssertFalse(app.buttons["gauntletFinishPack"].isEnabled)
    }

    func testSummaryPipsTurnSolidWhenAPendingLinemateIsKept() {
        launch("catalyst")
        revealPack()
        let initial = app.descendants(matching: .any).matching(NSPredicate(
            format: "label == %@",
            "Evolution line, 1 of 3 stages in Showcase, 2 additional stages in pack. "
                + "Emberpup: in Showcase. Cinderhound: in pack, this card. Pyrewolf: in pack"
        )).firstMatch
        XCTAssertTrue(initial.waitForExistence(timeout: 5))
        app.buttons["gauntletAttuneCatalyst"].tap()
        let inspect = app.buttons["gauntletInspect-S1-003"]
        XCTAssertTrue(inspect.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(inspect.frame.width, 84)
        XCTAssertLessThan(inspect.frame.width, 94)
        shot("gauntlet-larger-summary-cards")
        app.buttons["gauntletKeep-S1-002"].tap()
        let updated = app.descendants(matching: .any).matching(NSPredicate(
            format: "label == %@",
            "Evolution line, 2 of 3 stages in Showcase, 1 additional stage in pack. "
                + "Emberpup: in Showcase. Cinderhound: in Showcase. Pyrewolf: in pack, this card"
        )).firstMatch
        scrollTo(app.buttons["gauntletKeep-S1-003"], in: app.scrollViews["gauntletSummaryScroll"])
        XCTAssertTrue(updated.waitForExistence(timeout: 5))
        inspect.tap()
        let detail = app.scrollViews["gauntletPendingCardDetails"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["EVOLUTION LINE"].exists)
        XCTAssertTrue(app.staticTexts["Emberpup"].exists)
        XCTAssertTrue(app.staticTexts["Cinderhound"].exists)
        XCTAssertTrue(app.staticTexts["Pyrewolf"].exists)
        XCTAssertFalse(app.buttons["gauntletGradeCard"].exists)
        shot("gauntlet-expanded-pull")
        app.buttons["gauntletClosePendingDetail"].tap()
        XCTAssertTrue(app.buttons["gauntletKeep-S1-003"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["gauntletKeep-S1-002"].exists)
        XCTAssertFalse(app.buttons["gauntletFinishPack"].isEnabled)
        shot("half-fill-linemate-kept")
    }

    func testSummaryPipsBecomeMissingWhenAPendingLinemateIsSold() {
        launch("catalyst")
        revealPack()
        app.buttons["gauntletAttuneCatalyst"].tap()
        app.buttons["gauntletSell-S1-002"].tap()
        let updated = app.descendants(matching: .any).matching(NSPredicate(
            format: "label == %@",
            "Evolution line, 1 of 3 stages in Showcase, 1 additional stage in pack. "
                + "Emberpup: in Showcase. Cinderhound: missing. Pyrewolf: in pack, this card"
        )).firstMatch
        scrollTo(app.buttons["gauntletKeep-S1-003"], in: app.scrollViews["gauntletSummaryScroll"])
        XCTAssertTrue(updated.waitForExistence(timeout: 5))
        shot("half-fill-linemate-sold")
    }

    @MainActor
    func testPlaysAFreshEasyRunThroughTheBinderReward() {
        startFreshEasyRun()
        shot("after-fresh-run")

        for _ in 0..<60 {
            if app.staticTexts["Claim Extended Art"].exists {
                shot("after-playtested-reward")
                let reward = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'gauntletReward-'")).firstMatch
                XCTAssertTrue(reward.exists)
                reward.tap()
                XCTAssertTrue(app.staticTexts["Gauntlet Complete"].waitForExistence(timeout: 5))
                shot("after-playtested-win")
                let share = app.buttons["gauntletShareRun"]
                XCTAssertTrue(share.isEnabled)
                share.tap()
                let copy = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Copy'")).firstMatch
                XCTAssertTrue(copy.waitForExistence(timeout: 10), "the image opens the system share sheet")
                shot("after-image-only-sharing")
                copy.tap()
                XCTAssertTrue(share.isHittable)
                XCTAssertTrue(UIPasteboard.general.hasImages, "the real share activity receives the image")
                XCTAssertFalse(UIPasteboard.general.hasStrings, "the share must not add a Trading Up text message")
                return
            }
            XCTAssertFalse(app.staticTexts["Run Over"].exists, "the scripted Easy run should remain winnable")
            if app.buttons["gauntletNextRound"].exists {
                let nextRound = app.buttons["gauntletNextRound"]
                if nextRound.label.contains("Championship") {
                    XCTAssertEqual(nextRound.label, "Enter the Championship")
                    shot("after-championship")
                } else {
                    XCTAssertNotNil(nextRound.label.range(of: "^(Bank|Start) Round [0-9]+$", options: .regularExpression))
                }
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
            if app.buttons["gauntletEndRun"].exists {
                gradeLastChance()
                app.buttons["gradeResultContinue"].tap()
                let close = button("Close card")
                if close.exists && close.isHittable { close.tap() }
                continue
            }
            let packs = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'gauntletPack-' AND enabled == true"))
            XCTAssertGreaterThan(packs.count, 0)
            packs.element(boundBy: packs.count - 1).tap()
            revealPack()
            resolvePull()
            app.buttons["gauntletFinishPack"].tap()
        }
        XCTFail("Easy playthrough exceeded its bounded action budget")
    }

    func testRipsRemainProminentThroughoutPackOpening() {
        startFreshEasyRun()
        XCTAssertEqual(rips.label, "6 rips left")
        XCTAssertTrue(rips.isHittable)
        shot("after-round-rips")

        app.buttons["gauntletPack-1"].tap()
        app.assertPackIsSealed()
        XCTAssertEqual(rips.label, "5 rips left", "opening one pack spends exactly one rip")
        XCTAssertFalse(app.buttons["gauntletRevealAll"].exists)
        shot("after-sealed-rips")
        XCTAssertTrue(rips.isHittable)

        app.ripOpenPack()
        XCTAssertTrue(app.staticTexts["Tap for next card"].waitForExistence(timeout: 5))
        XCTAssertEqual(rips.label, "5 rips left")
        XCTAssertTrue(rips.isHittable)
        shot("after-reveal-rips")

        revealPack()
        XCTAssertEqual(rips.label, "5 rips left", "card reveals don't spend additional rips")
        XCTAssertTrue(rips.isHittable)
        shot("after-summary-rips")

        revealPack()
        XCTAssertEqual(rips.label, "5 rips left", "an already-visible summary must not open another pack")
        XCTAssertTrue(app.buttons["gauntletFinishPack"].exists)

        startFreshEasyRun(largeText: true)
        XCTAssertEqual(rips.label, "6 rips left")
        XCTAssertTrue(rips.isHittable)
        shot("after-round-rips-large-text")
    }

    func testGauntletPackRequiresSeamSwipeLeftToRightWithoutExtraRips() {
        verifyGauntletPackOpening(direction: .leftToRight)
    }

    func testGauntletPackRequiresSeamSwipeRightToLeftWithoutExtraRips() {
        verifyGauntletPackOpening(direction: .rightToLeft)
    }

    private func verifyGauntletPackOpening(direction: PackRipDirection) {
        launch("swap")
        app.assertPackIsSealed()
        XCTAssertEqual(rips.label, "2 rips left")
        shot("gauntlet-sealed-\(direction.rawValue)")

        app.assertPackRejectsInvalidGestures(direction: direction) {
            XCTAssertEqual(self.rips.label, "2 rips left", "rejected gestures must not spend another rip")
            XCTAssertFalse(self.app.staticTexts["Build your Showcase"].exists)
        }
        shot("gauntlet-partial-rip-reset-\(direction.rawValue)")

        app.ripOpenPack(direction: direction)
        XCTAssertFalse(app.packRipSeam.exists)
        XCTAssertTrue(app.staticTexts["Tap for next card"].waitForExistence(timeout: 5))
        XCTAssertEqual(rips.label, "2 rips left")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["Tap to finish"].waitForExistence(timeout: 5),
                      "tapping the first of the two seeded cards must advance to the last")
        XCTAssertEqual(rips.label, "2 rips left")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["Build your Showcase"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.packCardPrompt.exists)
        XCTAssertEqual(rips.label, "2 rips left")

        revealPack()
        XCTAssertTrue(app.buttons["gauntletSwap-S1-048"].exists)
        XCTAssertTrue(app.buttons["gauntletSwap-S1-006"].exists)
        XCTAssertEqual(rips.label, "2 rips left", "revisiting the summary must not re-rip the pack")
    }

    private func launch(_ scenario: String, seed: String = "0", largeText: Bool = false) {
        app.launchArguments = largeText
            ? ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL"] : []
        app.launchEnvironment = ["TU_FORCE_UNLOCK": "1", "TU_TEST_GAUNTLET": scenario,
                                 "TU_TEST_SEED": seed, "TU_AUDIO_DISABLED": "1"]
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

    private func startFreshEasyRun(largeText: Bool = false) {
        launch("fresh", seed: "0", largeText: largeText)
        let trainer = app.buttons["gauntletTrainer-neutral"]
        XCTAssertTrue(trainer.waitForExistence(timeout: 5))
        trainer.tap()
        app.buttons["gauntletTier-easy"].tap()
        XCTAssertTrue(app.buttons["gauntletPack-1"].waitForExistence(timeout: 5))
    }

    private func revealPack() {
        let summary = app.staticTexts["Build your Showcase"]
        let prompt = app.packCardPrompt
        XCTAssertFalse(app.buttons["gauntletRevealAll"].exists)
        let ready = NSPredicate { _, _ in
            summary.exists || prompt.exists
                || (self.app.packRipSeam.exists && self.app.packRipSeam.isHittable
                    && self.app.packRipSeam.value as? String == "Sealed")
        }
        guard XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: app)],
                            timeout: 5) == .completed else {
            XCTFail("expected a sealed pack, a revealed card, or the summary")
            return
        }
        if summary.exists { return }
        if !prompt.exists { app.ripOpenPack() }

        for _ in 0..<12 {
            if summary.exists { return }
            let next = NSPredicate { _, _ in summary.exists || prompt.exists }
            guard XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: next, object: app)],
                                timeout: 5) == .completed else {
                XCTFail("every revealed card must offer its next tap or the summary")
                return
            }
            if summary.exists { return }
            prompt.tap()
        }
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
    }

    private func settleLastPack() {
        revealPack()
        app.buttons["gauntletSell-S1-001"].tap()
        XCTAssertTrue(app.buttons["gauntletFinishPack"].label.contains("Review last chance"))
        app.buttons["gauntletFinishPack"].tap()
        let endRun = app.buttons["gauntletEndRun"]
        XCTAssertTrue(endRun.waitForExistence(timeout: 5))
        XCTAssertTrue(endRun.isHittable)
        XCTAssertEqual(endRun.frame.midX, app.frame.midX, accuracy: 1)
        XCTAssertEqual(rips.label, "0 rips left")
        XCTAssertFalse(app.buttons["gauntletReviewGrade"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH 'Need ' AND label CONTAINS 'more Aura'")).firstMatch.exists)
    }

    private func gradeLastChance() {
        app.buttons["gauntletShowcase-0"].tap()
        let grade = app.buttons["gauntletGradeCard"]
        scrollTo(grade, in: app.scrollViews["gauntletCardDetails"])
        XCTAssertTrue(grade.isHittable)
        grade.tap()
        XCTAssertTrue(app.staticTexts["gradeResultValue"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["gradeResultContinue"].exists)
        XCTAssertFalse(app.staticTexts["Round 1 Cleared!"].exists, "the result must be shown before advancing")
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
            let attune = app.buttons["gauntletAttuneCatalyst"]
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

    private func assertConciseSwapCopy() {
        for text in [
            "Breaks a completed evolution line",
            "Completes an evolution line",
            "Compare total Aura and series progress",
            "No series"
        ] {
            XCTAssertFalse(app.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch.exists,
                "The swap comparison should not repeat: \(text)")
        }
    }

    private func scrollTo(_ target: XCUIElement, in scroll: XCUIElement) {
        for _ in 0..<5 {
            if target.exists && target.isHittable { return }
            scroll.swipeUp()
        }
    }

    private var aura: XCUIElement { element("gauntletAura") }

    private var rips: XCUIElement {
        // The full-screen reveal keeps the covered round HUD in the accessibility tree.
        let matches = app.descendants(matching: .any).matching(identifier: "gauntletRipsRemaining")
        return matches.allElementsBoundByIndex.first { $0.isHittable } ?? matches.firstMatch
    }

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
