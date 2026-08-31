import XCTest
import SwiftUI
@testable import TradingUp

/// The Trainer difficulty ring is the accomplishment display players read at a
/// glance, so its rasterization gets a regression test — and the same pass emits
/// PNG attachments (0/1/2/3 tiers lit) used as the PR's proof screenshots.
@MainActor
final class TrainerRingRenderTests: XCTestCase {

    /// A recognisable, colourful roster member for the sample shots.
    private var sampleTrainer: Trainer {
        Trainer.roster.first { $0.id == "ripper" } ?? Trainer.roster[0]
    }

    /// The four monotonic clear states, in ladder order.
    private var states: [(name: String, caption: String, cleared: Set<GauntletTier>)] {
        [
            ("0-none", "0 / 3", []),
            ("1-easy", "1 / 3", [.easy]),
            ("2-easy-medium", "2 / 3", [.easy, .medium]),
            ("3-all-cleared", "3 / 3", [.easy, .medium, .hard]),
        ]
    }

    private func attach(_ image: UIImage?, named name: String) {
        XCTAssertNotNil(image, "\(name) must rasterize")
        guard let image else { return }
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Each clear state rendered as the real Trainer card, exactly as it appears
    /// on the "Choose your Trainer" screen.
    func testTrainerCardRingRasterizesForEveryClearState() {
        for state in states {
            let card = TrainerCard(
                trainer: sampleTrainer,
                unlocked: true,
                unlockProgress: nil,
                clearedTiers: state.cleared,
                action: {}
            )
            .frame(width: 360)
            .padding(20)
            .background(Palette.bg0)

            let renderer = ImageRenderer(content: card)
            renderer.scale = 3
            attach(renderer.uiImage, named: "ring-card-\(state.name)")
        }
    }

    /// A side-by-side strip of the ring alone at 0/1/2/3 lit — the PR hero shot.
    func testRingProgressionStripRasterizes() {
        let trainer = sampleTrainer
        let strip = HStack(spacing: 26) {
            ForEach(states, id: \.name) { state in
                VStack(spacing: 12) {
                    TrainerEmblemRing(
                        trainer: trainer,
                        unlocked: true,
                        cleared: state.cleared,
                        showRing: true
                    )
                    .scaleEffect(1.5)
                    .frame(width: 112, height: 112)
                    Text(state.caption)
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(32)
        .background(Palette.bg0)

        let renderer = ImageRenderer(content: strip)
        renderer.scale = 3
        attach(renderer.uiImage, named: "ring-strip-0-1-2-3")
    }
}
