#if DEBUG
import SwiftUI

/// A DEBUG-only harness that renders individual, otherwise hard-to-reach visual
/// components on their own so they can be screenshotted and eyeballed without
/// grinding a whole Gauntlet run to reach them (the win-only share card) or
/// waiting on a random Catalyst drop. It is the visual analogue of
/// `DebugLaunchState`: gated entirely behind `#if DEBUG` and a launch
/// environment variable, so a shipped build has no way to reach it.
///
/// Drive it from a UI test:
///
///     app.launchEnvironment["TU_TEST_GALLERY"] = "share"   // or "catalyst"
///
enum DebugGallery {
    static let key = "TU_TEST_GALLERY"

    enum Selection: String {
        case catalyst
        case share
    }

    static var selection: Selection? {
        guard let raw = ProcessInfo.processInfo.environment[key] else { return nil }
        return Selection(rawValue: raw.lowercased())
    }
}

struct DebugGalleryView: View {
    let selection: DebugGallery.Selection

    var body: some View {
        ZStack {
            Palette.bg0.ignoresSafeArea()
            switch selection {
            case .catalyst:
                CatalystCardView(catalyst: sampleCatalyst, width: 280)
                    .accessibilityIdentifier("galleryCatalyst")
            case .share:
                GauntletShareCard(
                    trainer: sampleTrainer,
                    tier: .easy,
                    showcase: sampleShowcase,
                    attuned: sampleAttuned,
                    showcaseAura: 1240,
                    prize: samplePrize
                )
                .accessibilityIdentifier("galleryShare")
            }
        }
    }

    // MARK: Sample data

    private var sampleCatalyst: Catalyst {
        Catalyst.roster.first { $0.element == .fire } ?? Catalyst.roster[0]
    }

    private var sampleTrainer: Trainer { Trainer.roster[0] }

    private var sampleAttuned: [Catalyst] { Array(Catalyst.roster.prefix(2)) }

    private var sampleShowcase: [CardInstance] {
        Array(CardDatabase.all.prefix(6)).enumerated().map { idx, card in
            CardInstance(cardId: card.id, foil: idx % 3 == 0)
        }
    }

    private var samplePrize: GauntletRewardOption {
        let cardId = CardDatabase.all.first { $0.rarity == .ultra }?.id
            ?? CardDatabase.all.first?.id ?? ""
        return GauntletRewardOption(cardId: cardId)
    }
}
#endif
