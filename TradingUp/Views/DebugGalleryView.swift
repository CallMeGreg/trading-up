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
        /// A Gauntlet Showcase grid of graded, multi-stage cards — the deterministic
        /// stand-in for a real run, used to shoot the PSA-grade-over-artwork placement
        /// without grinding a Gauntlet to reach a graded Showcase card.
        case showcase
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
            case .showcase:
                showcaseGrid
                    .accessibilityIdentifier("galleryShowcase")
            }
        }
    }

    // MARK: Showcase (grade-over-artwork placement)

    /// A Gauntlet Showcase grid: several graded, multi-stage cards so the header
    /// stage pips and the PSA grade slab appear together — the exact case the
    /// grade slab was moved off the pips to serve.
    private var showcaseGrid: some View {
        let showcase = sampleGradedShowcase
        return VStack(alignment: .leading, spacing: 12) {
            Text("Showcase \(showcase.count)/\(showcase.count)")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(Palette.subtle)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 12) {
                ForEach(showcase) { inst in
                    CardView(card: inst.card, instance: inst, width: 96,
                             series: .gauntlet(inst.card, showcase: showcase),
                             pipsGlow: false)
                }
            }
        }
        .padding(20)
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

    /// Cards standing in the sample Showcase: the first two evolution lines kept
    /// whole, so every card's header pips read as a full solid progression, with
    /// graded copies alternating through so the PSA slab sits in the art corner
    /// beside those pips — the exact case the slab was moved off the pips to serve.
    /// Grades are fixed, not random, so the render is reproducible.
    private var sampleGradedShowcase: [CardInstance] {
        let lines = CardDatabase.evolutionLines.sorted { $0.key < $1.key }
        let gradeCycle: [Int?] = [10, nil, 9, nil, 8, nil]
        var out: [CardInstance] = []
        var i = 0
        for line in lines.prefix(2).map(\.value) {
            for card in line {
                let grade = gradeCycle[i % gradeCycle.count]
                out.append(CardInstance(cardId: card.id, foil: grade == nil, grade: grade))
                i += 1
            }
        }
        // Fall back to any cards if the catalogue somehow ships no evolution lines.
        if out.isEmpty {
            out = Array(CardDatabase.all.prefix(4)).enumerated().map { idx, card in
                CardInstance(cardId: card.id, foil: idx.isMultiple(of: 2), grade: idx.isMultiple(of: 2) ? nil : 9)
            }
        }
        return out
    }
}
#endif
