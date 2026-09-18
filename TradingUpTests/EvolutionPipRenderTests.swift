import XCTest
import SwiftUI
@testable import TradingUp

@MainActor
final class EvolutionPipRenderTests: XCTestCase {
    private func middleCard(in set: Int) throws -> Card {
        try XCTUnwrap(CardDatabase.all.first { $0.set == set && $0.stage == 2 && $0.stageCount == 3 })
    }

    private func render(_ series: CardSeries, tint: Color, glow: Bool) throws -> CGImage {
        let renderer = ImageRenderer(content:
            SeriesPips(series: series, setTint: tint, s: 1, glow: glow)
                .background(Color.black)
        )
        renderer.scale = 4
        let image = try XCTUnwrap(renderer.uiImage)
        XCTAssertEqual(image.size.width, 67, accuracy: 0.01)
        XCTAssertEqual(image.size.height, 17, accuracy: 0.01)
        return try XCTUnwrap(image.cgImage)
    }

    private func pixel(_ image: CGImage, x: CGFloat, y: CGFloat = 8.5) throws -> [Double] {
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(
            data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.translateBy(x: -floor(x * 4), y: -floor(y * 4))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return bytes.prefix(3).map(Double.init)
    }

    private func assertColor(_ actual: [Double], matches expected: [Double], tolerance: Double = 3,
                             file: StaticString = #filePath, line: UInt = #line) {
        for channel in 0..<3 {
            XCTAssertEqual(actual[channel], expected[channel], accuracy: tolerance, file: file, line: line)
        }
    }

    func testFullHalfAndHollowFillsUseEverySetsTintWithoutChangingGeometry() throws {
        for set in 1...CardDatabase.setCount {
            let card = try middleCard(in: set)
            let base = CardDatabase.line(card.lineId)[0]
            let series = CardSeries.gauntlet(card, showcase: [CardInstance(cardId: base.id)],
                                            pendingCards: [CardInstance(cardId: card.id)])
            let image = try render(series, tint: Element.theme(forSet: set).badgeTint, glow: false)
            // Reference-size centers: 7pt inset + 4.5pt radius, then 22pt per stage.
            let owned = try pixel(image, x: 11.5)
            let missing = try pixel(image, x: 55.5)
            assertColor(try pixel(image, x: 32), matches: owned)
            assertColor(try pixel(image, x: 35), matches: missing)
            XCTAssertGreaterThan(zip(owned, missing).map { abs($0 - $1) }.max() ?? 0, 80)
        }
    }

    func testGoldOutlinePreservesHalfFillAndSolidOwnedDuplicates() throws {
        for set in 1...CardDatabase.setCount {
            let card = try middleCard(in: set)
            let base = CardDatabase.line(card.lineId)[0]
            for owned in [false, true] {
                let showcase = [CardInstance(cardId: base.id)]
                    + (owned ? [CardInstance(cardId: card.id)] : [])
                let series = CardSeries.gauntlet(card, showcase: showcase,
                                                pendingCards: [CardInstance(cardId: card.id)])
                let tint = Element.theme(forSet: set).badgeTint
                let flat = try render(series, tint: tint, glow: false)
                let focused = try render(series, tint: tint, glow: true)
                assertColor(try pixel(focused, x: 32), matches: try pixel(flat, x: 32), tolerance: 40)
                assertColor(try pixel(focused, x: 35), matches: try pixel(flat, x: 35), tolerance: 40)
                assertColor(try pixel(focused, x: 33.5, y: 2.4), matches: [255, 213, 74], tolerance: 12)
                XCTAssertLessThan(try pixel(flat, x: 33.5, y: 2.4)[0], 50,
                                  "settled pips must not retain the current-card ring")
            }
        }
    }

    func testActualSizeCardsRenderInEverySetColor() throws {
        let cards = try (1...CardDatabase.setCount).map { try middleCard(in: $0) }
        let preview = VStack(alignment: .leading, spacing: 16) {
            ForEach(cards) { card in
                let line = CardDatabase.line(card.lineId)
                let pending = [CardInstance(cardId: card.id)]
                let held = [CardInstance(cardId: line[0].id)]
                let series = CardSeries.gauntlet(card, showcase: held, pendingCards: pending)
                HStack(spacing: 20) {
                    Text(CardDatabase.setName(card.set))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 90, alignment: .leading)
                    CardView(card: card, instance: pending[0], width: 76, series: series)
                    CardView(card: card, instance: pending[0], width: 76,
                             series: .gauntlet(card, showcase: held + pending, pendingCards: pending))
                    SeriesPips(series: series, setTint: Element.theme(forSet: card.set).badgeTint, s: 1.5)
                }
            }
        }
        .padding(20)
        .background(Palette.bg0)
        let renderer = ImageRenderer(content: preview)
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.uiImage)
        let attachment = XCTAttachment(image: image)
        attachment.name = "half-fill-all-sets-76pt-cards-and-enlarged-pips"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
