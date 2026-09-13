import XCTest
@testable import TradingUp

final class PackRipMotionTests: XCTestCase {
    private func motion(x: CGFloat, y: CGFloat = 0, width: CGFloat = 218,
                        startX: CGFloat = 0) -> PackRipMotion {
        PackRipMotion(translation: CGSize(width: x, height: y), packWidth: width, startX: startX)
    }

    func testTapsAndShortSwipesLeaveThePackSealed() {
        XCTAssertEqual(motion(x: 0).progress, 0)
        XCTAssertFalse(motion(x: 20).isComplete)
        XCTAssertFalse(motion(x: -20).isComplete)
        XCTAssertFalse(motion(x: 119).isComplete)
    }

    func testHorizontalRipCompletesInEitherDirection() {
        XCTAssertTrue(motion(x: 120).isComplete)
        XCTAssertFalse(motion(x: 120).fromRight)
        XCTAssertTrue(motion(x: -120).isComplete)
        XCTAssertTrue(motion(x: -120).fromRight)
        XCTAssertEqual(motion(x: 60).progress, motion(x: -60).progress)
    }

    func testVerticalAndDiagonalSwipesDoNotOpenThePack() {
        XCTAssertEqual(motion(x: 0, y: 200).progress, 0)
        XCTAssertEqual(motion(x: 140, y: 200).progress, 0)
        XCTAssertFalse(motion(x: -140, y: -200).isComplete)
        XCTAssertFalse(motion(x: 150, y: 150).isComplete)
        XCTAssertTrue(motion(x: 120, y: 25).isComplete, "natural finger drift is allowed")
    }

    func testProgressTracksDistanceAndClampsAtTheEnd() {
        XCTAssertEqual(motion(x: 55, width: 200).progress, 0.5, accuracy: 0.0001)
        XCTAssertEqual(motion(x: 110, width: 200).progress, 1, accuracy: 0.0001)
        XCTAssertEqual(motion(x: 1_000).progress, 1)
        XCTAssertEqual(motion(x: -1_000).progress, 1)
        XCTAssertEqual(motion(x: 100, width: 0).progress, 0)
    }

    func testReversingOrCancellingDoesNotAccumulateProgress() {
        XCTAssertGreaterThan(motion(x: 90).progress, motion(x: 30).progress)
        XCTAssertFalse(motion(x: 30).isComplete)
        XCTAssertEqual(motion(x: 0).progress, 0)
        XCTAssertFalse(motion(x: -30).isComplete)
    }

    func testThresholdScalesForPackAndBoxArt() {
        for width: CGFloat in [160, 218, 280, 296] {
            XCTAssertFalse(motion(x: width * 0.54, width: width).isComplete)
            XCTAssertTrue(motion(x: width * 0.56, width: width).isComplete)
        }
    }

    func testCutTrailTracksFingerDistanceRatherThanCompletionProgress() {
        let cut = motion(x: 55, width: 200, startX: 20)
        XCTAssertEqual(cut.progress, 0.5, accuracy: 0.0001)
        XCTAssertEqual(cut.trailStart, 20)
        XCTAssertEqual(cut.trailWidth, 55, "halfway to opening must not draw halfway across the wrapper")
        XCTAssertEqual(cut.fingerX, 75)
        XCTAssertTrue(motion(x: 110, width: 200).isComplete)
        XCTAssertFalse(motion(x: 109.9, width: 200).isComplete)
    }

    func testCutTrailFollowsRightToLeftAndReversedMotion() {
        let leftward = motion(x: -60, startX: 190)
        XCTAssertEqual(leftward.trailStart, 130)
        XCTAssertEqual(leftward.trailWidth, 60)
        XCTAssertEqual(leftward.fingerX, 130)
        XCTAssertTrue(leftward.fromRight)

        let reversed = motion(x: 30, startX: 100)
        XCTAssertEqual(reversed.trailStart, 100)
        XCTAssertEqual(reversed.trailWidth, 30)
        XCTAssertEqual(reversed.fingerX, 130)
        XCTAssertFalse(reversed.fromRight)
    }

    func testCutTrailClampsToTheWrapperRatherThanItsPaddedHitArea() {
        let fromLeftPadding = motion(x: 100, startX: -24)
        XCTAssertEqual(fromLeftPadding.trailStart, 0)
        XCTAssertEqual(fromLeftPadding.fingerX, 76)
        XCTAssertEqual(fromLeftPadding.trailWidth, 76)

        let fromRightPadding = motion(x: -100, startX: 242)
        XCTAssertEqual(fromRightPadding.trailStart, 142)
        XCTAssertEqual(fromRightPadding.fingerX, 142)
        XCTAssertEqual(fromRightPadding.trailWidth, 76)

        XCTAssertEqual(motion(x: 300, startX: 20).trailWidth, 198)
        XCTAssertEqual(motion(x: 300, startX: 20).fingerX, 218)
        XCTAssertEqual(motion(x: -300, startX: 198).trailWidth, 198)
        XCTAssertEqual(motion(x: -300, startX: 198).fingerX, 0)
    }

    func testRejectedOrCancelledDragsHaveNoCutTrail() {
        XCTAssertEqual(motion(x: 60, y: 80, startX: 20).trailWidth, 0)
        XCTAssertEqual(motion(x: 60, y: 60, startX: 20).trailWidth, 0)
        XCTAssertEqual(motion(x: 0, startX: 20).trailWidth, 0)
        XCTAssertEqual(motion(x: 60, width: 0, startX: 20).trailWidth, 0)
        XCTAssertEqual(motion(x: 60, width: 0, startX: 20).fingerX, 0)
    }
}
