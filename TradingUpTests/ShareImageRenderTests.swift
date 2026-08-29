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

    func testGauntletRunShareCardRasterizesToAnImage() {
        let showcase = Array(CardDatabase.all.prefix(6)).map { CardInstance(cardId: $0.id, foil: true) }
        let attuned = Array(Catalyst.roster.prefix(2))
        let card = GauntletShareCard(
            trainer: Trainer.roster[0],
            tier: .medium,
            showcase: showcase,
            attuned: attuned,
            showcaseAura: 1234,
            prize: GauntletRewardOption(cardId: CardDatabase.all[0].id)
        )
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2

        let image = renderer.uiImage
        XCTAssertNotNil(image, "the shareable gauntlet run image must rasterize")
        guard let image else { return }
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, image.size.width)
    }

    func testGauntletConsolationShareCardRasterizes() {
        // The complete-catalogue win offers no prize card; the card must still render.
        let card = GauntletShareCard(
            trainer: Trainer.roster[0],
            tier: .hard,
            showcase: [],
            attuned: [],
            showcaseAura: 999,
            prize: nil
        )
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        XCTAssertNotNil(renderer.uiImage, "the consolation gauntlet image must rasterize")
    }
}
