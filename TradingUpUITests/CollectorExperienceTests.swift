import XCTest

final class CollectorExperienceTests: XCTestCase {
    private var app: XCUIApplication!
    private let mira = "request:1-mira-0"
    private let target = "S1-050"

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
    }

    func testCollectorsUseOnlyTabsAndShowAllFiveSetPacks() {
        launch()
        XCTAssertTrue(app.buttons["buyPack"].firstMatch.isHittable)
        XCTAssertFalse(app.buttons["shopCollectors"].exists)
        openBoard()
        XCTAssertFalse(app.buttons["collectorsBackToShop"].exists)
        XCTAssertFalse(app.staticTexts["Tracked goals"].exists)
        XCTAssertFalse(app.staticTexts["Good spares. Great connections."].exists)
        XCTAssertFalse(element("collectorSafety").exists)
        for set in 1...5 {
            let pack = app.buttons["collectorSet-\(set)"]
            XCTAssertTrue(pack.exists)
            XCTAssertGreaterThanOrEqual(pack.frame.minX, app.frame.minX)
            XCTAssertLessThanOrEqual(pack.frame.maxX, app.frame.maxX)
        }
        XCTAssertTrue(app.buttons["collectorSet-1"].isSelected)
        XCTAssertFalse(app.buttons["collectorSet-5"].isEnabled)
        XCTAssertTrue(app.buttons["collectorReview-\(mira)"].isHittable)
        XCTAssertTrue(app.buttons["collectorReview-request:1-rowan-0"].isHittable,
                      "compact offers should expose both cash requests without a tracking panel")
        shot("collectors-compact-board")
        for name in ["Matthew", "Emilie", "Jonny"] {
            XCTAssertTrue(app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch.exists)
        }
        scrollTo(element("collectorTradesRemaining"), in: board)
        shot("collectors-initial-trader")
        tapTab("Shop", symbol: "bag.fill")
        XCTAssertTrue(app.buttons["buyPack"].firstMatch.waitForExistence(timeout: 5))
    }

    func testPackSelectionSurvivesTabChanges() {
        launch()
        openBoard()
        app.buttons["collectorSet-2"].tap()
        XCTAssertTrue(app.buttons["collectorSet-2"].isSelected)
        XCTAssertEqual(app.staticTexts["collectorSelectedSet"].label, "Tidecaller")
        tapTab("Shop", symbol: "bag.fill")
        openBoard()
        XCTAssertTrue(app.buttons["collectorSet-2"].isSelected)
        app.buttons["collectorSet-1"].tap()
        XCTAssertEqual(app.staticTexts["collectorSelectedSet"].label, "Emberfall")
        XCTAssertTrue(app.buttons["collectorSet-1"].isSelected)
    }

    func testReviewCancelLeavesCashCardsAndOfferUntouched() {
        launch()
        openBoard()
        let startingCash = app.staticTexts["collectorCash"].label
        tapOfferButton("collectorReview-\(mira)")
        let originalCopies = suppliedCopies.allElementsBoundByIndex.map(\.label).sorted()
        XCTAssertFalse(originalCopies.isEmpty)
        XCTAssertFalse(element("collectorForegoneSale").exists)
        shot("collectors-exact-copy-review")
        app.buttons["collectorReviewCancel"].tap()
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["collectorCash"].label, startingCash)
        tapOfferButton("collectorReview-\(mira)")
        XCTAssertEqual(suppliedCopies.allElementsBoundByIndex.map(\.label).sorted(), originalCopies)
        app.buttons["collectorReviewCancel"].tap()
    }

    func testRequestReceiptDropsBoilerplateAndAdvancesTheOffer() {
        launch()
        openBoard()
        let startingCash = app.staticTexts["collectorCash"].label
        completeRequest()
        XCTAssertTrue(element("collectorCashReceived").exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS 'normal spares exchanged'")).firstMatch.exists)
        XCTAssertFalse(app.buttons["collectorConfirm"].exists)
        shot("collectors-cash-receipt")
        closeReceipt()
        XCTAssertNotEqual(app.staticTexts["collectorCash"].label, startingCash)
        XCTAssertFalse(app.buttons["collectorReview-\(mira)"].exists)
        XCTAssertTrue(app.staticTexts["Growing collection"].exists)
    }

    func testMissingCardTradeReviewsExactBundleAndShowsCleanReceipt() {
        launch()
        openBoard()
        let allowance = app.staticTexts["collectorTradesRemaining"]
        scrollTo(allowance, in: board)
        let startingTrades = leadingCount(in: allowance.label)
        chooseTradeTarget(capture: true)
        let progress = app.staticTexts["collectorOfferProgress-trade:\(target)"]
        let expectedCopies = leadingCount(in: progress.label)
        tapOfferButton("collectorReview-trade:\(target)")
        XCTAssertEqual(suppliedCopyCount, expectedCopies)
        XCTAssertFalse(element("collectorForegoneSale").exists)
        scrollTo(element("collectorReward-\(target)"), in: app.scrollViews["collectorReviewSheet"])
        shot("collectors-trade-review")
        app.buttons["collectorConfirm"].tap()
        XCTAssertTrue(app.staticTexts["collectorReceived-\(target)"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Normal · Ungraded · New to your collection"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS 'normal spares exchanged'")).firstMatch.exists)
        shot("collectors-clean-card-receipt")
        closeReceipt()
        scrollTo(allowance, in: board)
        XCTAssertEqual(leadingCount(in: allowance.label), startingTrades - 1)
        XCTAssertTrue(element("collectorSetComplete").exists || element("collectorTradesExhausted").exists)
        XCTAssertFalse(app.buttons["collectorChooseTarget"].exists)
    }

    func testCollectorStatsShowRequestsTradesAndCashInBothScopes() {
        launch()
        openBoard()
        completeRequest()
        closeReceipt()
        chooseTradeTarget()
        tapOfferButton("collectorReview-trade:\(target)")
        app.buttons["collectorConfirm"].tap()
        XCTAssertTrue(app.staticTexts["collectorReceived-\(target)"].waitForExistence(timeout: 5))
        closeReceipt()
        tapTab("Stats", symbol: "chart.bar.fill")
        let stats = app.scrollViews["classicStats"]
        for scope in ["This Run", "All Time"] {
            let picker = app.segmentedControls["statsScope"]
            scrollTo(picker, in: stats, upward: false)
            picker.buttons[scope].tap()
            let requests = element("stat-Requests Completed")
            scrollTo(requests, in: stats)
            XCTAssertTrue(requests.label.hasSuffix("1"))
            XCTAssertTrue(element("stat-Cards Traded For").label.hasSuffix("1"))
            XCTAssertTrue(element("stat-Request Earnings").label.contains("$5"))
            shot("collector-stats-\(scope)")
        }
    }

    func testSellAllDupesConfirmsEntireSelectedSetAndCanBeCanceled() {
        launch("collection-polish")
        tapTab("Collection", symbol: "square.grid.3x3.fill")
        let sell = app.buttons["collectionSellDuplicates"]
        XCTAssertTrue(sell.waitForExistence(timeout: 5))
        let original = sell.value as? String
        XCTAssertNotNil(original)
        XCTAssertTrue(app.buttons["collectionCard-S1-001"].label.hasSuffix("3 copies"))
        shot("collection-lowered-copy-counts")
        app.buttons["Rare+"].tap()
        XCTAssertEqual(sell.value as? String, original, "filters must not silently narrow a set-wide sale")
        sell.tap()
        let cancel = app.buttons["collectionCancelSellDuplicates"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@",
            "Your cheapest copy of each card stays; other copies are sold.")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS 'Other sets are untouched'")).firstMatch.exists)
        shot("collection-confirm-sell-dupes")
        cancel.tap()
        XCTAssertTrue(sell.waitForExistence(timeout: 5))
        XCTAssertEqual(sell.value as? String, original)
        sell.tap()
        let confirm = app.buttons["collectionConfirmSellDuplicates"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(sell.waitForExistence(timeout: 5))
        XCTAssertFalse(sell.isEnabled)
        app.buttons["Rare+"].tap()
        XCTAssertTrue(app.buttons["collectionCard-S1-001"].label.hasSuffix("1 copy"))
        app.segmentedControls["collectionSetPicker"].buttons["2"].tap()
        XCTAssertTrue(sell.isEnabled, "selling set 1 must leave set 2's duplicates alone")
        XCTAssertTrue((sell.value as? String)?.hasPrefix("1 duplicate,") == true)
    }

    func testCardDetailRemembersSellAndGradeAcrossDifferentCards() {
        launch("collection-polish")
        tapTab("Collection", symbol: "square.grid.3x3.fill")
        openCard("S1-001")
        let picker = app.segmentedControls["collectionCopyAction"]
        picker.buttons["Grade"].tap()
        picker.buttons["Sell Extras"].tap()
        app.buttons["Done"].tap()
        openCard("S1-004")
        XCTAssertTrue(picker.buttons["Sell Extras"].isSelected)
        picker.buttons["Grade"].tap()
        app.buttons["Done"].tap()
        openCard("S1-001")
        XCTAssertTrue(picker.buttons["Grade"].isSelected)
        app.buttons["Done"].tap()
    }

    func testPackSummaryHasNoTrackingOrReservationChrome() {
        launch()
        app.buttons["buyPack"].firstMatch.tap()
        XCTAssertTrue(app.waitForSealedPack())
        app.packRipSeam.tap()
        XCTAssertTrue(app.packSummary.waitForExistence(timeout: 8))
        XCTAssertFalse(element("collectorPackProtection").exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH 'Saved for'")).firstMatch.exists)
        XCTAssertTrue(app.buttons["packSellDuplicates"].isHittable)
        shot("classic-pack-summary-no-tracking")
        app.buttons["packSellDuplicates"].tap()
        XCTAssertTrue(app.buttons["buyPack"].firstMatch.waitForExistence(timeout: 8))
    }

    func testNewPackBadgesAndSharedNewRunConfirmation() {
        launch()
        app.buttons["buyPack"].firstMatch.tap()
        XCTAssertTrue(app.waitForSealedPack())
        app.packRipSeam.tap()
        XCTAssertTrue(app.packSummary.waitForExistence(timeout: 8))
        app.buttons["packKeepAll"].tap()
        XCTAssertTrue(app.buttons["Home"].waitForExistence(timeout: 5))
        app.buttons["Home"].tap()
        app.buttons["classicMode"].tap()
        XCTAssertTrue(app.buttons["New Run"].waitForExistence(timeout: 5))
        app.buttons["New Run"].tap()
        XCTAssertTrue(app.buttons["Start New Run"].waitForExistence(timeout: 5))
        shot("shared-new-run-confirmation")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["classicMode"].waitForExistence(timeout: 5))
        app.buttons["classicMode"].tap()
        app.buttons["New Run"].tap()
        app.buttons["Start New Run"].tap()
        XCTAssertTrue(app.buttons["buyPack"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Start Collecting"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS 'Track two goals' OR label CONTAINS 'Tracked spares'")).firstMatch.exists)
        XCTAssertTrue(app.buttons["buyPack"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["buyPack"].firstMatch.tap()
        XCTAssertTrue(app.waitForSealedPack())
        app.packRipSeam.tap()
        XCTAssertTrue(app.packSummary.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["✦ NEW"].firstMatch.exists)
        shot("classic-raised-new-badges")
    }

    func testFinalCardWinWaitsUntilTradeReceiptHasDismissed() {
        launch("collector-final-card")
        openBoard()
        chooseTradeTarget()
        tapOfferButton("collectorReview-trade:\(target)")
        XCTAssertFalse(win.exists)
        app.buttons["collectorConfirm"].tap()
        XCTAssertTrue(app.staticTexts["collectorReceived-\(target)"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("collectorReceiptBonuses").exists)
        let prematureWin = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: win)
        prematureWin.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [prematureWin], timeout: 1.5), .completed)
        app.buttons["collectorReceiptDone"].tap()
        XCTAssertTrue(win.waitForExistence(timeout: 8))
        XCTAssertFalse(app.scrollViews["collectorReceipt"].exists)
    }

    func testBoardAndReviewRemainUsableAtLargeText() {
        launch(textSize: "UICTContentSizeCategoryXXXL")
        assertReadableBoardAndReview(suffix: "large-text")
    }

    func testBoardAndReviewRemainUsableAtAccessibilityText() {
        launch(textSize: "UICTContentSizeCategoryAccessibilityXXXL")
        assertReadableBoardAndReview(suffix: "accessibility-text")
    }

    func testBoardAndReviewRemainUsableInLandscape() {
        launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let rotated = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in self.app.frame.width > self.app.frame.height }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 5), .completed)
        assertReadableBoardAndReview(suffix: "landscape")
    }

    private func assertReadableBoardAndReview(suffix: String) {
        openBoard()
        shot("collectors-board-\(suffix)-top")
        let pack = app.buttons["collectorSet-1"]
        XCTAssertTrue(pack.isHittable)
        pack.tap()
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
        scrollTo(suppliedCopies.firstMatch, in: app.scrollViews["collectorReviewSheet"])
        shot("collectors-review-\(suffix)")
        app.buttons["collectorReviewCancel"].tap()
        XCTAssertTrue(board.waitForExistence(timeout: 5))
    }

    private func launch(_ state: String = "collectors", textSize: String? = nil) {
        app.launchEnvironment = [
            "TU_TEST_STATE": state, "TU_TEST_SEED": "0",
            "TU_FORCE_UNLOCK": "1", "TU_AUDIO_DISABLED": "1"
        ]
        app.launchArguments = [
            "-tradingup_tap_to_open_packs", "YES", "-tradingup_auto_open_packs", "YES"
        ]
        if let textSize { app.launchArguments += ["-UIPreferredContentSizeCategoryName", textSize] }
        app.launch()
        let classic = app.buttons["classicMode"].firstMatch
        XCTAssertTrue(classic.waitForExistence(timeout: 30))
        classic.tap()
        XCTAssertTrue(app.buttons["buyPack"].firstMatch.waitForExistence(timeout: 10))
    }

    private func tapTab(_ name: String, symbol: String) {
        let standard = app.tabBars.buttons[name].firstMatch
        let floating = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND label == %@", symbol, name)).firstMatch
        let tab = standard.exists ? standard : floating
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        tab.tap()
    }

    private func openBoard() {
        tapTab("Collectors", symbol: "person.2.fill")
        XCTAssertTrue(board.waitForExistence(timeout: 5))
    }

    private func openCard(_ id: String) {
        let card = app.buttons["collectionCard-\(id)"]
        scrollTo(card, in: app.scrollViews["collectionGrid"])
        card.tap()
        let picker = app.segmentedControls["collectionCopyAction"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        scrollTo(picker, in: app.scrollViews["collectionCardDetail"])
    }

    private func chooseTradeTarget(capture: Bool = false) {
        tapOfferButton("collectorChooseTarget")
        let list = app.scrollViews["collectorTargetList"]
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        if capture {
            XCTAssertTrue(app.navigationBars["Trade with Jonny"].exists)
            shot("collectors-jonny-card-trade")
        }
        let choice = app.buttons["collectorTarget-\(target)"]
        scrollTo(choice, in: list)
        choice.tap()
        XCTAssertTrue(board.waitForExistence(timeout: 5))
    }

    private func completeRequest() {
        tapOfferButton("collectorReview-\(mira)")
        app.buttons["collectorConfirm"].tap()
        XCTAssertTrue(app.scrollViews["collectorReceipt"].waitForExistence(timeout: 5))
    }

    private func closeReceipt() {
        app.buttons["collectorReceiptDone"].tap()
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

    private var board: XCUIElement { app.scrollViews["collectorBoard"] }
    private var win: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == 'Keep My Collection'")).firstMatch
    }
    private var suppliedCopies: XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'collectorSupplied-'"))
    }
    private var suppliedCopyCount: Int {
        suppliedCopies.allElementsBoundByIndex.reduce(0) { $0 + leadingCount(in: $1.label) }
    }
    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
