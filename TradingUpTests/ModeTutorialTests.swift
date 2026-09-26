import SwiftUI
import XCTest
@testable import TradingUp

@MainActor
final class ModeTutorialTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        super.setUp()
        suite = "ModeTutorialTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testModesStartIndependentlyAndCompletionSurvivesNewRuns() {
        let classic = ModeTutorial(mode: .classic, defaults: defaults)
        classic.prepare(hasPlayed: false)
        XCTAssertTrue(classic.needs(.classicBuy))
        classic.record(.classicBuy)
        classic.record(.classicBuy)
        XCTAssertEqual(classic.completed.count, 1)
        classic.finish()

        let nextClassic = ModeTutorial(mode: .classic, defaults: defaults)
        nextClassic.prepare(hasPlayed: false)
        XCTAssertFalse(nextClassic.isActive)
        let gauntlet = ModeTutorial(mode: .gauntlet, defaults: defaults)
        gauntlet.prepare(hasPlayed: false)
        XCTAssertTrue(gauntlet.needs(.gauntletTrainer))
    }

    func testExistingPlayersAreNotForcedThroughANewTutorial() {
        for mode in [ModeTutorial.Mode.classic, .gauntlet] {
            let tutorial = ModeTutorial(mode: mode, defaults: defaults)
            tutorial.prepare(hasPlayed: true)
            XCTAssertFalse(tutorial.isActive)
            let freshRun = ModeTutorial(mode: mode, defaults: defaults)
            freshRun.prepare(hasPlayed: false)
            XCTAssertFalse(freshRun.isActive)
        }
    }

    func testInterruptedTutorialResumesDespiteLegacyWelcomeMarker() {
        let original = ModeTutorial(mode: .classic, defaults: defaults)
        original.prepare(hasPlayed: false)
        original.record(.classicBuy)
        let resumed = ModeTutorial(mode: .classic, defaults: defaults)
        resumed.prepare(hasPlayed: true)
        XCTAssertTrue(resumed.isActive)
        resumed.resumeClassic(hasCards: true)
        XCTAssertFalse(resumed.needs(.classicBuy))
        XCTAssertFalse(resumed.needs(.classicSummary))
        XCTAssertTrue(resumed.needs(.classicCollection))
        resumed.record(.classicGrade)
        let afterGrade = ModeTutorial(mode: .classic, defaults: defaults)
        afterGrade.prepare(hasPlayed: true)
        XCTAssertFalse(afterGrade.needs(.classicGrade), "relaunch must not force another grading fee")
    }

    func testAbandonedClassicTutorialCanStartWithANewEmptyRun() {
        let tutorial = ModeTutorial(mode: .classic, defaults: defaults)
        tutorial.prepare(hasPlayed: false)
        tutorial.record(.classicBuy)
        tutorial.record(.classicSummary)
        tutorial.resumeClassic(hasCards: false)
        XCTAssertTrue(tutorial.needs(.classicBuy))
        XCTAssertTrue(tutorial.needs(.classicSummary))
    }

    func testGauntletMilestonesSurviveRelaunch() {
        let tutorial = ModeTutorial(mode: .gauntlet, defaults: defaults)
        tutorial.prepare(hasPlayed: false)
        tutorial.record(.gauntletKeep)
        tutorial.record(.gauntletSell)
        let resumed = ModeTutorial(mode: .gauntlet, defaults: defaults)
        resumed.prepare(hasPlayed: true)
        XCTAssertTrue(resumed.isActive)
        XCTAssertFalse(resumed.needs(.gauntletKeep))
        XCTAssertFalse(resumed.needs(.gauntletSell))
        XCTAssertTrue(resumed.needs(.gauntletShop))
    }

    func testSpotlightCoachNeverCoversTargetOrLeavesSafeArea() {
        for size in [CGSize(width: 320, height: 568), CGSize(width: 844, height: 390),
                     CGSize(width: 768, height: 1024)] {
            let viewport = TutorialSpotlightLayout.safeBounds(size: size, insets: EdgeInsets(
                top: 20, leading: 0, bottom: 20, trailing: 0))
            for y in [viewport.minY, viewport.midY - 22, viewport.maxY - 44] {
                let target = CGRect(x: 30, y: y, width: 160, height: 44)
                XCTAssertEqual(TutorialSpotlightLayout.visibleTarget(target, in: viewport), target)
                let region = TutorialSpotlightLayout.coachRegion(in: viewport, avoiding: target)!
                let frame = TutorialSpotlightLayout.coachFrame(in: region, contentHeight: 500, target: target)
                XCTAssertTrue(viewport.contains(frame))
                XCTAssertFalse(frame.intersects(target))
                XCTAssertGreaterThan(frame.height, 0)
            }
        }
    }

    func testOffscreenAndInvalidTargetsNeverBecomeActions() {
        let viewport = CGRect(x: 0, y: 0, width: 320, height: 568)
        XCTAssertNil(TutorialSpotlightLayout.visibleTarget(.zero, in: viewport))
        XCTAssertNil(TutorialSpotlightLayout.visibleTarget(
            CGRect(x: 10, y: 550, width: 100, height: 44), in: viewport))
    }

    func testBottomSummaryButtonsAreNotDoubleInset() {
        let viewport = TutorialSpotlightLayout.overlayViewport(
            hostFrame: CGRect(x: 0, y: 62, width: 402, height: 778),
            overlayFrame: CGRect(x: 0, y: 0, width: 402, height: 874))
        XCTAssertEqual(viewport, CGRect(x: 0, y: 62, width: 402, height: 778))
        for button in [CGRect(x: 16, y: 778, width: 370, height: 46),
                       CGRect(x: 16, y: 767.7, width: 370, height: 56.3)] {
            XCTAssertNotNil(TutorialSpotlightLayout.visibleTarget(button, in: viewport))
        }
    }
}
