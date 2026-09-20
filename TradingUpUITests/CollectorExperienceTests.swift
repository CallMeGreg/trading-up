import XCTest

/// The collector fixture starts with untracked, ready Mira/Rowan requests and
/// enough normal set-1 spares to trade for the missing ultra S1-050.
/// The final-card fixture holds out only S1-050 across the full collection.
final class CollectorExperienceTests: XCTestCase {
    private var app: XCUIApplication!
    private let mira = "request:1-mira-0"
    private let rowan = "request:1-rowan-0"
    private let target = "S1-050"

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
    }

    func testShopShortcutKeepsFirstPackVisibleAndReturnsToShop() {
        launch()
        XCTAssertTrue(app.buttons["buyPack"].firstMatch.isHittable,
                      "collectors must not push the first pack below the fold")
        openBoard()
        XCTAssertTrue(app.buttons["collectorsBackToShop"].isHittable)
        XCTAssertEqual(trackingCount.label, "0 of 2 tracking slots used")
        XCTAssertTrue(app.buttons["collectorSetPicker"].exists)
        shot("collectors-board")
        app.buttons["collectorsBackToShop"].tap()
        XCTAssertTrue(app.buttons["buyPack"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["buyPack"].firstMatch.isHittable)
        // iPad's floating tab items are cells rather than a TabBar's buttons.
        let standardTab = app.tabBars.buttons["Collectors"].firstMatch
        let floatingTab = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'person.2.fill' AND label == 'Collectors'")).firstMatch
        let collectorsTab = standardTab.exists ? standardTab : floatingTab
        XCTAssertTrue(collectorsTab.isHittable)
        collectorsTab.tap()
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertTrue(collectorsTab.isSelected)
    }

    func testTrackingProtectsRequestThroughPackBulkSale() {
        launch()
        openBoard()
        let expectedCopies = readySpareCount(for: mira)
        tapOfferButton("collectorTrack-\(mira)")
        XCTAssertEqual(trackingCount.label, "1 of 2 tracking slots used")
        XCTAssertTrue(app.buttons["collectorTrackedReview-\(mira)"].exists)
        app.buttons["collectorsBackToShop"].tap()
        app.buttons["buyPack"].firstMatch.tap()
        XCTAssertTrue(app.waitForSealedPack())
        app.packRipSeam.tap()
        XCTAssertTrue(app.packSummary.waitForExistence(timeout: 8))
        XCTAssertFalse(app.packCardPrompt.exists, "auto-open must still go straight to all six cards")
        let protection = element("collectorPackProtection")
        XCTAssertTrue(protection.exists)
        XCTAssertTrue(protection.label.contains("Mira"))
        XCTAssertTrue(protection.label.contains("stay out of sales"))
        let sell = app.buttons["packSellDuplicates"]
        XCTAssertTrue(sell.isHittable, "the fixture pack should include unreserved extras to sell")
        shot("collectors-protected-pack-summary")
        sell.tap()

        XCTAssertTrue(app.buttons["shopCollectors"].waitForExistence(timeout: 8))
        openBoard()
        let review = app.buttons["collectorTrackedReview-\(mira)"]
        scrollTo(review, in: board, upward: false)
        XCTAssertTrue(review.isEnabled, "bulk selling must leave every reserved request copy available")
        review.tap()
        XCTAssertTrue(app.buttons["collectorConfirm"].waitForExistence(timeout: 5))
        XCTAssertEqual(suppliedCopyCount, expectedCopies)
        app.buttons["collectorReviewCancel"].tap()
        XCTAssertEqual(trackingCount.label, "1 of 2 tracking slots used")
    }

    func testReviewCancelLeavesCashCardsAndGoalUntouched() {
        launch()
        openBoard()
        let startingCash = app.staticTexts["collectorCash"].label
        tapOfferButton("collectorReview-\(mira)")
        XCTAssertTrue(app.buttons["collectorConfirm"].waitForExistence(timeout: 5))
        let originalCopies = suppliedCopies.allElementsBoundByIndex.map(\.label).sorted()
        XCTAssertFalse(originalCopies.isEmpty)
        XCTAssertTrue(element("collectorForegoneSale").exists)
        shot("collectors-exact-copy-review")
        app.buttons["collectorReviewCancel"].tap()
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["collectorCash"].label, startingCash)
        XCTAssertEqual(trackingCount.label, "0 of 2 tracking slots used")

        tapOfferButton("collectorReview-\(mira)")
        XCTAssertTrue(app.buttons["collectorConfirm"].waitForExistence(timeout: 5))
        XCTAssertEqual(suppliedCopies.allElementsBoundByIndex.map(\.label).sorted(), originalCopies)
        app.buttons["collectorReviewCancel"].tap()
    }

    func testReturningFindsReadyLaterSetAndPreservesExplicitSelection() {
        launch("collector-final-card")
        openBoard()
        tapOfferButton("collectorReview-\(mira)")
        app.buttons["collectorConfirm"].tap()
        XCTAssertTrue(app.buttons["collectorReceiptDone"].waitForExistence(timeout: 5))
        app.buttons["collectorReceiptDone"].tap()
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        app.buttons["collectorsBackToShop"].tap()

        let teaser = app.buttons["shopCollectors"]
        let beforePack = teaser.label
        let buy = app.buttons.matching(NSPredicate(
            format: "identifier == 'buyPack' AND label CONTAINS 'Tidecaller'")).firstMatch
        scrollTo(buy, in: shop)
        buy.tap()
        XCTAssertTrue(app.waitForSealedPack())
        if teaser.exists {
            XCTAssertEqual(teaser.label, beforePack, "the reveal must not leak new collector readiness")
        }
        app.packRipSeam.tap()
        XCTAssertTrue(app.packSummary.waitForExistence(timeout: 8))
        if teaser.exists {
            XCTAssertEqual(teaser.label, beforePack, "the Shop snapshot lasts through the pack summary")
        }
        app.buttons["packKeepAll"].tap()
        XCTAssertTrue(teaser.waitForExistence(timeout: 8))
        XCTAssertNotEqual(teaser.label, beforePack, "new normal spares should make a Tidecaller request ready")

        openBoard()
        let picker = app.buttons["collectorSetPicker"]
        XCTAssertTrue(picker.label.contains("Tidecaller"),
                      "returning to the board should focus the later set with ready offers")
        XCTAssertTrue(app.buttons["collectorReview-request:2-mira-0"].exists)
        shot("collectors-ready-later-set")

        scrollTo(picker, in: board)
        picker.tap()
        let emberfall = app.buttons["collectorSet-1"]
        XCTAssertTrue(emberfall.waitForExistence(timeout: 5))
        emberfall.tap()
        XCTAssertTrue(picker.label.contains("Emberfall"))
        let elsewhere = app.buttons["collectorReadyElsewhere"]
        XCTAssertTrue(elsewhere.isHittable, "other ready sets must stay discoverable above the current offers")
        XCTAssertTrue(elsewhere.label.contains("Tidecaller"))
        shot("collectors-ready-other-sets")
        app.buttons["collectorsBackToShop"].tap()
        openBoard()
        XCTAssertTrue(picker.label.contains("Emberfall"), "an explicit set choice should survive tab changes")
        elsewhere.tap()
        let tidecaller = app.buttons["collectorReadySet-2"]
        XCTAssertTrue(tidecaller.waitForExistence(timeout: 5))
        tidecaller.tap()
        XCTAssertTrue(picker.label.contains("Tidecaller"))
    }

    func testSuccessfulRequestShowsReceiptThenNextFiniteRequest() {
        launch()
        openBoard()
        let startingCash = app.staticTexts["collectorCash"].label
        tapOfferButton("collectorTrack-\(mira)")
        tapOfferButton("collectorReview-\(mira)")
        app.buttons["collectorConfirm"].tap()
        XCTAssertTrue(app.scrollViews["collectorReceipt"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("collectorCashReceived").exists)
        XCTAssertFalse(app.buttons["collectorConfirm"].exists)
        shot("collectors-cash-receipt")
        app.buttons["collectorReceiptDone"].tap()
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertNotEqual(app.staticTexts["collectorCash"].label, startingCash)
        XCTAssertEqual(trackingCount.label, "0 of 2 tracking slots used",
                       "completing a tracked goal frees its slot")
        XCTAssertFalse(app.buttons["collectorTrack-\(mira)"].exists)
        XCTAssertTrue(app.buttons["collectorTrack-request:1-mira-1"].exists,
                      "the next finite request should replace the completed request")
    }

    func testNamedMissingCardTradeShowsBundleAndAwardsChosenCard() {
        launch()
        openBoard()
        let allowance = app.staticTexts["collectorTradesRemaining"]
        scrollTo(allowance, in: board)
        let startingTrades = leadingCount(in: allowance.label)
        chooseTradeTarget()
        XCTAssertTrue(element("collectorReward-\(target)").exists)
        let expectedCopies = readySpareCount(for: "trade:\(target)")
        tapOfferButton("collectorReview-trade:\(target)")
        XCTAssertTrue(app.buttons["collectorConfirm"].waitForExistence(timeout: 5))
        XCTAssertEqual(suppliedCopyCount, expectedCopies,
                       "the review must show every spare promised by the current model's bundle")
        XCTAssertTrue(element("collectorForegoneSale").exists)
        shot("collectors-trade-review")
        app.buttons["collectorConfirm"].tap()
        XCTAssertTrue(app.staticTexts["collectorReceived-\(target)"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Normal · Ungraded · New to your collection"].exists)
        shot("collectors-missing-card-receipt")
        app.buttons["collectorReceiptDone"].tap()
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertEqual(leadingCount(in: allowance.label), startingTrades - 1)
        XCTAssertTrue(element("collectorSetComplete").exists || element("collectorTradesExhausted").exists)
        XCTAssertFalse(app.buttons["collectorChooseTarget"].exists,
                       "the fixture's only missing card has been received, so no target remains")
        XCTAssertFalse(app.buttons["collectorReview-trade:\(target)"].exists)
    }

    func testTrackingLimitExplainsHowToFreeASlotWithoutDiscardingOffers() {
        launch()
        openBoard()
        tapOfferButton("collectorTrack-\(mira)")
        tapOfferButton("collectorTrack-\(rowan)")
        chooseTradeTarget()
        let tradeTrack = app.buttons["collectorTrack-trade:\(target)"]
        scrollTo(tradeTrack, in: board)
        XCTAssertTrue(tradeTrack.isEnabled, "full tracking slots need an explanation, not a dead button")
        tradeTrack.tap()
        let alert = app.alerts["Couldn't update this goal"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(
            format: "label CONTAINS[c] 'Untrack'")).firstMatch.exists)
        alert.buttons["OK"].tap()

        let untrack = app.buttons["collectorUntrack-\(mira)"]
        scrollTo(untrack, in: board, upward: false)
        untrack.tap()
        XCTAssertEqual(trackingCount.label, "1 of 2 tracking slots used")
        XCTAssertTrue(app.buttons["collectorTrack-\(mira)"].exists,
                      "untracking frees cards without deleting the cash offer")
        tapOfferButton("collectorTrack-trade:\(target)")
        XCTAssertEqual(trackingCount.label, "2 of 2 tracking slots used")
    }

    func testFinalCardWinWaitsUntilTradeReceiptHasDismissed() {
        launch("collector-final-card")
        openBoard()
        chooseTradeTarget()
        tapOfferButton("collectorReview-trade:\(target)")
        XCTAssertFalse(win.exists)
        app.buttons["collectorConfirm"].tap()
        XCTAssertTrue(app.staticTexts["collectorReceived-\(target)"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("collectorReceiptBonuses").exists,
                      "the receipt must include the final set-completion payout")
        let prematureWin = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: win)
        prematureWin.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [prematureWin], timeout: 1.5), .completed,
                       "a final-card celebration must never interrupt the receipt")
        XCTAssertTrue(app.buttons["collectorReceiptDone"].isHittable)
        shot("collectors-final-card-before-celebration")
        app.buttons["collectorReceiptDone"].tap()
        XCTAssertTrue(win.waitForExistence(timeout: 8))
        XCTAssertFalse(app.scrollViews["collectorReceipt"].exists)
        shot("collectors-final-card-win")
    }

    func testBoardAndExactCopyReviewRemainUsableAtLargeText() {
        launch(textSize: "UICTContentSizeCategoryXXXL")
        assertReadableBoardAndReview(suffix: "large-text")
    }

    func testBoardAndExactCopyReviewRemainUsableAtAccessibilityText() {
        launch(textSize: "UICTContentSizeCategoryAccessibilityXXXL")
        assertReadableBoardAndReview(suffix: "accessibility-text", trackGoal: true)
    }

    func testBoardAndExactCopyReviewRemainUsableInLandscape() {
        launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let rotated = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in self.app.frame.width > self.app.frame.height },
            object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 5), .completed)
        assertReadableBoardAndReview(suffix: "landscape")
    }

    private func assertReadableBoardAndReview(suffix: String, trackGoal: Bool = false) {
        openBoard()
        shot("collectors-board-\(suffix)-top")
        let picker = app.buttons["collectorSetPicker"]
        scrollTo(picker, in: board)
        XCTAssertTrue(picker.isHittable)
        shot("collectors-set-picker-\(suffix)")
        picker.tap()
        let firstSet = app.buttons["collectorSet-1"]
        XCTAssertTrue(firstSet.waitForExistence(timeout: 5))
        firstSet.tap()
        if trackGoal {
            tapOfferButton("collectorTrack-\(mira)")
            let untrack = app.buttons["collectorUntrack-\(mira)"]
            scrollTo(untrack, in: board, upward: false)
            XCTAssertEqual(trackingCount.label, "1 of 2 tracking slots used")
            shot("collectors-tracked-\(suffix)")
        }
        let review = app.buttons["collectorReview-\(mira)"]
        scrollTo(review, in: board)
        XCTAssertGreaterThanOrEqual(review.frame.height, 44)
        XCTAssertGreaterThanOrEqual(review.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(review.frame.maxX, app.frame.maxX)
        shot("collectors-board-\(suffix)")
        review.tap()
        let confirm = app.buttons["collectorConfirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertTrue(confirm.isHittable)
        XCTAssertGreaterThanOrEqual(confirm.frame.height, 44)
        XCTAssertGreaterThanOrEqual(confirm.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(confirm.frame.maxX, app.frame.maxX)
        scrollTo(element("collectorForegoneSale"), in: app.scrollViews["collectorReviewSheet"])
        shot("collectors-review-\(suffix)")
        XCTAssertTrue(app.buttons["collectorReviewCancel"].isHittable)
        app.buttons["collectorReviewCancel"].tap()
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        if trackGoal {
            let untrack = app.buttons["collectorUntrack-\(mira)"]
            scrollTo(untrack, in: board, upward: false)
            untrack.tap()
            XCTAssertEqual(trackingCount.label, "0 of 2 tracking slots used")
        }
    }

    private func launch(_ state: String = "collectors", textSize: String? = nil) {
        app.launchEnvironment = [
            "TU_TEST_STATE": state, "TU_TEST_SEED": "0",
            "TU_FORCE_UNLOCK": "1", "TU_AUDIO_DISABLED": "1"
        ]
        app.launchArguments = [
            "-tradingup_tap_to_open_packs", "YES", "-tradingup_auto_open_packs", "YES"
        ]
        if let textSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", textSize]
        }
        app.launch()
        let classic = app.buttons["classicMode"].firstMatch
        XCTAssertTrue(classic.waitForExistence(timeout: 30))
        classic.tap()
        XCTAssertTrue(app.buttons["buyPack"].firstMatch.waitForExistence(timeout: 10))
    }

    private func openBoard() {
        let shortcut = app.buttons["shopCollectors"]
        scrollTo(shortcut, in: shop)
        shortcut.tap()
        XCTAssertTrue(board.waitForExistence(timeout: 5))
    }

    private func chooseTradeTarget() {
        tapOfferButton("collectorChooseTarget")
        let list = app.scrollViews["collectorTargetList"]
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        let choice = app.buttons["collectorTarget-\(target)"]
        scrollTo(choice, in: list)
        shot("collectors-target-picker")
        choice.tap()
        XCTAssertTrue(board.waitForExistence(timeout: 5))
    }

    private func tapOfferButton(_ id: String) {
        let button = app.buttons[id]
        scrollTo(button, in: board)
        button.tap()
        if id.hasPrefix("collectorReview-") {
            XCTAssertTrue(app.buttons["collectorConfirm"].waitForExistence(timeout: 5))
        }
    }

    private func readySpareCount(for goal: String) -> Int {
        let progress = app.staticTexts["collectorOfferProgress-\(goal)"]
        scrollTo(progress, in: board)
        XCTAssertTrue(progress.label.hasPrefix("All "), "the fixture must have a ready bundle")
        return leadingCount(in: progress.label.replacingOccurrences(of: "All ", with: ""))
    }

    private func leadingCount(in label: String) -> Int {
        guard let first = label.split(separator: " ").first, let count = Int(first) else {
            XCTFail("Expected a live count in: \(label)")
            return 0
        }
        return count
    }

    private func scrollTo(_ element: XCUIElement, in scroll: XCUIElement, upward: Bool = true,
                          file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<24 {
            let viewport = visibleFrame(of: scroll)
            guard !viewport.isNull, viewport.width > 0, viewport.height > 0 else {
                XCTFail("no visible scrolling area", file: file, line: line)
                return
            }
            var scrollUp = upward
            var distance = viewport.height * 0.4
            if element.exists {
                let frame = element.frame
                // Off-screen SwiftUI menus can throw on isHittable instead of returning false.
                let visible = frame.height <= viewport.height
                    ? viewport.contains(frame)
                    : frame.intersection(viewport).height >= viewport.height / 2
                if !frame.isEmpty && visible && element.isHittable { return }
                if !frame.isEmpty {
                    scrollUp = frame.midY > viewport.midY
                    distance = min(distance, max(44, abs(frame.midY - viewport.midY)))
                }
            }
            let start = scroll.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: viewport.midX - scroll.frame.minX,
                                     dy: viewport.midY - scroll.frame.minY))
            let end = start.withOffset(CGVector(dx: 0, dy: scrollUp ? -distance : distance))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        XCTFail("element never became reachable: \(element.identifier)", file: file, line: line)
    }

    private func visibleFrame(of scroll: XCUIElement) -> CGRect {
        var frame = scroll.frame.intersection(app.frame)
        for bar in app.navigationBars.allElementsBoundByIndex + app.tabBars.allElementsBoundByIndex {
            let bounds = bar.frame
            guard bounds.intersects(frame), bounds.width >= frame.width * 0.8 else { continue }
            if bounds.midY < frame.midY {
                let bottom = frame.maxY
                frame.origin.y = max(frame.minY, bounds.maxY)
                frame.size.height = bottom - frame.minY
            } else {
                frame.size.height = min(frame.maxY, bounds.minY) - frame.minY
            }
        }
        return frame.insetBy(dx: 4, dy: 4)
    }

    // The covered main menu also exposes a scroll view in compact landscape layouts.
    private var shop: XCUIElement { app.scrollViews["classicShop"] }
    private var board: XCUIElement { app.scrollViews["collectorBoard"] }
    private var trackingCount: XCUIElement { app.staticTexts["collectorTrackingCount"] }
    private var win: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == 'Keep My Collection'")).firstMatch
    }
    private var suppliedCopies: XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'collectorSupplied-'"))
    }
    private var suppliedCopyCount: Int {
        suppliedCopies.allElementsBoundByIndex.reduce(0) { $0 + leadingCount(in: $1.label) }
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
