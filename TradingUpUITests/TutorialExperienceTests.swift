import XCTest

final class TutorialExperienceTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
    }

    func testClassicGuidesRealActionsAndKeepsReferenceAfterCompletion() {
        launchFresh()
        enter("classicMode")
        let buy = guide("classic-buy-1")
        XCTAssertTrue(buy.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Start Collecting"].exists)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.1)).tap()
        XCTAssertTrue(buy.exists, "outside taps cannot advance or dismiss the tutorial")
        screenshot("classic-first-tap")
        buy.tap()
        openPack()
        tapGuide("classic-keep")
        tapGuide("tab-Collection")
        tapGuide(prefix: "classic-card-")
        tapGuide(prefix: "classic-grade-")
        let gradeContinue = app.buttons["gradeResultContinue"]
        XCTAssertTrue(gradeContinue.waitForExistence(timeout: 10))
        gradeContinue.tap()
        tapGuide("classic-sell-tab")
        tapGuide("classic-detail-done")
        tapGuide("tab-Collectors")
        tapGuide("classic-choose-trade")
        tapGuide(prefix: "classic-trade-")
        tapGuide("tab-Shop")
        app.tabBars.buttons["Collectors"].tap()
        let changeTarget = app.buttons["collectorChooseTarget"]
        XCTAssertTrue(changeTarget.waitForExistence(timeout: 10))
        XCTAssertTrue(changeTarget.label.contains("Change card"), "the tutorial's trade goal must survive normal tabs")
        app.tabBars.buttons["Shop"].tap()
        let info = app.buttons["classicInfo"]
        XCTAssertTrue(info.waitForExistence(timeout: 10))
        info.tap()
        XCTAssertTrue(app.buttons["Back to Game"].waitForExistence(timeout: 5))
        app.buttons["Back to Game"].tap()
        app.buttons["Home"].tap()
        app.terminate()
        relaunch()
        enter("classicMode", resume: true)
        XCTAssertTrue(app.buttons["classicInfo"].waitForExistence(timeout: 10))
        XCTAssertFalse(anyGuide.exists, "completed tutorial must not replay")
    }

    func testSpotlightBlocksUnrelatedControls() {
        launchFresh()
        enter("classicMode")
        XCTAssertTrue(guide("classic-buy-1").waitForExistence(timeout: 10))
        let info = app.buttons["classicInfo"]
        XCTAssertFalse(info.isHittable)
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: info.frame.midX, dy: info.frame.midY)).tap()
        XCTAssertTrue(guide("classic-buy-1").exists)
        XCTAssertFalse(app.buttons["Back to Game"].exists)
    }

    func testClassicInterruptedPackResumesWithoutAnotherPurchase() {
        launchFresh()
        enter("classicMode")
        tapGuide("classic-buy-1")
        XCTAssertTrue(app.descendants(matching: .any)["packRipSeam"].firstMatch.waitForExistence(timeout: 10))
        app.terminate()
        relaunch()
        enter("classicMode", resume: true)
        XCTAssertTrue(guide(prefix: "classic-card-").waitForExistence(timeout: 10))
        XCTAssertFalse(guide("classic-buy-1").exists)
        tapGuide(prefix: "classic-card-")
        tapGuide(prefix: "classic-grade-")
        XCTAssertTrue(app.buttons["gradeResultContinue"].waitForExistence(timeout: 10))
        app.terminate()
        relaunch()
        enter("classicMode", resume: true)
        tapGuide(prefix: "classic-card-")
        XCTAssertTrue(guide("classic-sell-tab").waitForExistence(timeout: 10))
        XCTAssertFalse(guide(prefix: "classic-grade-").exists, "do not charge to re-teach a completed grade")
    }

    func testGauntletGuidesKeepSellGradeAndFirstShop() {
        launchFresh(seed: "15")
        enter("gauntletMode")
        XCTAssertFalse(app.buttons["Let's Rip"].exists)
        tapGuide("gauntlet-trainer-neutral")
        tapGuide("gauntlet-tier-easy")
        screenshot("gauntlet-first-rip")
        tapGuide("gauntlet-pack-1")
        openPack()
        tapGuide("gauntlet-attune")
        tapGuide(prefix: "gauntlet-keep-")
        tapGuide(prefix: "gauntlet-sell-")
        settlePull()
        tapGuide("gauntlet-showcase-0")
        tapGuide("gauntlet-grade")
        XCTAssertTrue(app.buttons["gradeResultContinue"].waitForExistence(timeout: 10))
        app.buttons["gradeResultContinue"].tap()
        tapGuide("gauntlet-detail-done")
        tapGuide("gauntlet-finish-pack")
        for _ in 0..<6 {
            if guide("gauntlet-buy-slot").exists { break }
            if guide("gauntlet-next-round").waitForExistence(timeout: 2) { break }
            let pack = app.buttons["gauntletPack-1"]
            XCTAssertTrue(pack.waitForExistence(timeout: 5))
            pack.tap()
            openPack()
            if guide("gauntlet-attune").waitForExistence(timeout: 1) { tapGuide("gauntlet-attune") }
            settlePull()
            app.buttons["gauntletFinishPack"].tap()
        }
        screenshot("gauntlet-first-shop")
        if guide("gauntlet-buy-slot").exists { tapGuide("gauntlet-buy-slot") }
        tapGuide("gauntlet-next-round")
        XCTAssertFalse(anyGuide.exists)
        waitUntilHittable(app.buttons["gauntletPack-1"])
        app.buttons["Home"].tap()
        enter("gauntletMode", resume: true)
        XCTAssertFalse(anyGuide.exists, "Gauntlet teaching is durable independently of Classic")
    }

    func testGauntletInterruptedDecisionResumesWithoutRepeatingActions() {
        launchFresh(seed: "15")
        enter("gauntletMode")
        tapGuide("gauntlet-trainer-neutral")
        tapGuide("gauntlet-tier-easy")
        tapGuide("gauntlet-pack-1")
        openPack()
        tapGuide("gauntlet-attune")
        tapGuide(prefix: "gauntlet-keep-")
        app.terminate()
        relaunch()
        enter("gauntletMode", resume: true)
        openPack()
        tapGuide(prefix: "gauntlet-sell-")
        XCTAssertFalse(guide(prefix: "gauntlet-keep-").exists)
        settlePull()
        tapGuide("gauntlet-showcase-0")
        XCTAssertTrue(guide("gauntlet-grade").waitForExistence(timeout: 10))
    }

    func testGauntletTargetsRemainReachableInLandscapeAndLargeText() {
        launchFresh(largeText: true, seed: "15")
        XCUIDevice.shared.orientation = .landscapeLeft
        enter("gauntletMode")
        tapGuide("gauntlet-trainer-neutral")
        tapGuide("gauntlet-tier-easy")
        tapGuide("gauntlet-pack-1")
        openPack()
        tapGuide("gauntlet-attune")
        tapGuide(prefix: "gauntlet-keep-")
        tapGuide(prefix: "gauntlet-sell-")
        settlePull()
        tapGuide("gauntlet-showcase-0")
        tapGuide("gauntlet-grade")
    }

    func testFirstTargetsRemainReachableInLandscapeAndLargeText() {
        launchFresh(largeText: true)
        XCUIDevice.shared.orientation = .landscapeLeft
        enter("classicMode")
        let target = guide("classic-buy-1")
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        XCTAssertTrue(target.isHittable)
        screenshot("classic-landscape-large-text")
        target.tap()
        openPack()
        tapGuide("classic-keep")
        tapGuide("tab-Collection")
        tapGuide(prefix: "classic-card-")
        tapGuide(prefix: "classic-grade-")
    }

    private func launchFresh(largeText: Bool = false, seed: String = "0") {
        app.launchArguments = ["-tradingup_tap_to_open_packs", "YES", "-tradingup_auto_open_packs", "YES"]
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launchEnvironment = ["TU_TEST_TUTORIAL": "fresh", "TU_FORCE_UNLOCK": "1",
                                 "TU_TEST_SEED": seed, "TU_AUDIO_DISABLED": "1"]
        app.launch()
    }

    private func relaunch() {
        app.launchEnvironment.removeValue(forKey: "TU_TEST_TUTORIAL")
        app.launch()
    }

    private func enter(_ mode: String, resume: Bool = false) {
        waitUntilHittable(app.buttons[mode])
        app.buttons[mode].tap()
        if resume {
            XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 5))
            app.buttons["Continue"].tap()
        }
    }

    private func waitUntilHittable(_ element: XCUIElement) {
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 15), .completed)
    }

    private var anyGuide: XCUIElement { guide(prefix: "") }

    private func guide(_ id: String) -> XCUIElement { app.buttons["tutorialTarget-\(id)"] }

    private func guide(prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "tutorialTarget-\(prefix)")).firstMatch
    }

    private func tapGuide(_ id: String) {
        let target = guide(id)
        XCTAssertTrue(target.waitForExistence(timeout: 10), "Missing tutorial target \(id)")
        XCTAssertTrue(target.isHittable)
        target.tap()
    }

    private func tapGuide(prefix: String) {
        let target = guide(prefix: prefix)
        XCTAssertTrue(target.waitForExistence(timeout: 10), "Missing tutorial target \(prefix)")
        XCTAssertTrue(target.isHittable)
        target.tap()
    }

    private func openPack() {
        let seam = app.descendants(matching: .any)["packRipSeam"].firstMatch
        XCTAssertTrue(seam.waitForExistence(timeout: 10))
        seam.tap()
    }

    private func settlePull() {
        for _ in 0..<7 {
            if guide("gauntlet-showcase-0").exists { return }
            let keep = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'gauntletKeep-'")).firstMatch
            let sell = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'gauntletSell-'")).firstMatch
            let action = keep.exists ? keep : sell
            if !action.exists { return }
            let scroll = app.scrollViews["gauntletSummaryScroll"]
            for _ in 0..<8 {
                if action.isHittable { break }
                scroll.swipeUp()
            }
            action.tap()
        }
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
