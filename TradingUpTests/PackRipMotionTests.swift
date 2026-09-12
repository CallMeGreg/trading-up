import XCTest
@testable import TradingUp

final class PackRipMotionTests: XCTestCase {
    private func motion(x: CGFloat, y: CGFloat = 0, width: CGFloat = 218) -> PackRipMotion {
        PackRipMotion(translation: CGSize(width: x, height: y), packWidth: width)
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
        for width: CGFloat in [160, 218, 296] {
            XCTAssertFalse(motion(x: width * 0.54, width: width).isComplete)
            XCTAssertTrue(motion(x: width * 0.56, width: width).isComplete)
        }
    }
}
