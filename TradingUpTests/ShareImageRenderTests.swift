import XCTest
import SwiftUI
@testable import TradingUp

/// The win screen's whole payoff is a screenshot the player wants to share, so
/// the rasterization path that produces that image gets its own regression test.
@MainActor
final class ShareImageRenderTests: XCTestCase {

    private func completedCore() -> GameCore {
        var core = GameCore()
        for c in CardDatabase.all { core.instances.append(CardInstance(cardId: c.id)) }
        _ = core.checkBonuses()
        return core
    }

    func testShareCardRasterizesToAnImage() {
        let sig = RunSignature.make(from: completedCore())
        let card = WinShareCard(
            signature: sig,
            totalCards: CardDatabase.all.count,
            ownedBySet: (1...CardDatabase.setCount).map { _ in 50 }
        )
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2

        let image = renderer.uiImage
        XCTAssertNotNil(image, "the shareable win image must rasterize")
        guard let image else { return }
        XCTAssertGreaterThan(image.size.width, 0)
        // The collector-card layout is portrait; a wider-than-tall result would
        // mean the card collapsed or clipped.
        XCTAssertGreaterThan(image.size.height, image.size.width)
    }
}
