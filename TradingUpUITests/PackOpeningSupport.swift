import XCTest

enum PackRipDirection: String {
    case leftToRight = "left-to-right"
    case rightToLeft = "right-to-left"

    var startX: CGFloat { self == .leftToRight ? 0.1 : 0.9 }
    var endX: CGFloat { self == .leftToRight ? 0.9 : 0.1 }
    var shortEndX: CGFloat { self == .leftToRight ? 0.3 : 0.7 }
}

extension XCUIApplication {
    var packRipSeam: XCUIElement { buttons["packRipSeam"].firstMatch }

    var packRipInstruction: XCUIElement { staticTexts["Swipe to rip open"].firstMatch }

    var packCardPrompt: XCUIElement {
        staticTexts.matching(NSPredicate(
            format: "label IN %@", ["Tap for next card", "Tap to finish"])).firstMatch
    }

    func waitForSealedPack(timeout: TimeInterval = 15) -> Bool {
        let ready = NSPredicate { _, _ in
            self.packRipSeam.exists && self.packRipSeam.isHittable
                && self.packRipSeam.value as? String == "Sealed"
                && self.packRipInstruction.exists && self.packRipInstruction.isHittable
        }
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: self)],
                             timeout: timeout) == .completed
    }

    func assertPackIsSealed(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(waitForSealedPack(timeout: 5), "the wrapper should be sealed and ready",
                      file: file, line: line)
        XCTAssertEqual(descendants(matching: .any).matching(identifier: "packRipSeam").count, 1,
                       "only the top seam should be an accessible rip surface", file: file, line: line)
        XCTAssertEqual(packRipSeam.value as? String, "Sealed", file: file, line: line)
        XCTAssertTrue(packRipInstruction.isHittable, file: file, line: line)
        XCTAssertFalse(packCardPrompt.exists, "a rejected gesture must not reveal a card",
                       file: file, line: line)
    }

    func ripOpenPack(direction: PackRipDirection = .leftToRight,
                     file: StaticString = #filePath, line: UInt = #line) {
        guard waitForSealedPack() else {
            XCTFail("sealed pack and swipe instruction never appeared", file: file, line: line)
            return
        }
        let start = packRipSeam.coordinate(withNormalizedOffset: CGVector(dx: direction.startX, dy: 0.5))
        let end = packRipSeam.coordinate(withNormalizedOffset: CGVector(dx: direction.endX, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(packCardPrompt.waitForExistence(timeout: 5),
                      "a complete seam swipe should reveal the first card without another tap",
                      file: file, line: line)
    }

    func assertPackRejectsInvalidGestures(direction: PackRipDirection,
                                         afterRejection: () -> Void = {},
                                         file: StaticString = #filePath, line: UInt = #line) {
        let seam = packRipSeam
        let center = seam.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let start = seam.coordinate(withNormalizedOffset: CGVector(dx: direction.startX, dy: 0.5))
        let end = seam.coordinate(withNormalizedOffset: CGVector(dx: direction.endX, dy: 0.5))
        let shortEnd = seam.coordinate(withNormalizedOffset: CGVector(dx: direction.shortEndX, dy: 0.5))
        let bodyOffset = CGVector(dx: 0, dy: seam.frame.height * 2)
        let verticalEnd = center.withOffset(CGVector(dx: 0, dy: seam.frame.width * 0.8))

        // Coordinate taps exercise pointer input, not the assistive-tech Rip open action.
        let gestures: [(String, () -> Void)] = [
            ("tap on the seam", { center.tap() }),
            ("tap on the wrapper body", { center.withOffset(bodyOffset).tap() }),
            ("horizontal swipe below the seam", {
                start.withOffset(bodyOffset).press(forDuration: 0.05, thenDragTo: end.withOffset(bodyOffset))
            }),
            ("vertical swipe on the seam", { center.press(forDuration: 0.05, thenDragTo: verticalEnd) }),
            ("short seam swipe", { start.press(forDuration: 0.05, thenDragTo: shortEnd) })
        ]
        for (name, gesture) in gestures {
            XCTContext.runActivity(named: "Reject \(name)") { _ in
                gesture()
                assertPackIsSealed(file: file, line: line)
                afterRejection()
            }
        }
    }
}
