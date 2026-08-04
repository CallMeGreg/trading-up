import Foundation

// MARK: - Collector rank

/// A letter grade for how efficiently the collection was completed — fewer packs
/// torn to reach all 250 is a better run. Mirrors the `bestRunPacks` record the
/// game already keeps, and echoes the PSA-style grading the player has been doing
/// all game. Thresholds are calibrated against a solid reference completion of
/// ~322 packs (see `tools/seed_save.py`) and are safe to tune.
enum CollectorRank: String, CaseIterable {
    case s = "S", a = "A", b = "B", c = "C", d = "D"

    var letter: String { rawValue }

    /// A word to sit beside the letter, e.g. "Rank S · Flawless".
    var word: String {
        switch self {
        case .s: return "Flawless"
        case .a: return "Masterful"
        case .b: return "Sharp"
        case .c: return "Seasoned"
        case .d: return "Relentless"
        }
    }

    static func forPacks(_ packs: Int) -> CollectorRank {
        switch packs {
        case ..<260: return .s
        case ..<360: return .a
        case ..<500: return .b
        case ..<720: return .c
        default:     return .d
        }
    }
}

// MARK: - Element flavor

extension Element {
    /// The epithet a collector earns for finishing with this element as their
    /// dominant affinity — used as the default title when no standout feat
    /// (foil/ultra luck, a huge flip) claims the card first.
    var masterTitle: String {
        switch self {
        case .fire:     return "The Emberlord"
        case .rock:     return "The Unbroken"
        case .water:    return "The Tidewarden"
        case .grass:    return "The Grovekeeper"
        case .electric: return "The Stormcaller"
        case .shadow:   return "The Nightbound"
        }
    }
}

// MARK: - Run signature

/// A personalized, shareable fingerprint of a winning run. Pure and derived
/// entirely from a finished `GameCore`, so it's deterministic and unit-testable
/// with no view or randomness in the loop. The win screen renders this as a
/// one-of-a-kind "collector card" celebrating the specific way the player won.
struct RunSignature {
    /// Earned epithet, e.g. "The Gilded" or "The Emberlord".
    let title: String
    /// One line explaining what earned the title, for the reveal.
    let accolade: String
    /// Dominant affinity (most-owned element), themes the whole card.
    let element: Element
    /// Efficiency grade from packs torn.
    let rank: CollectorRank
    /// The single most valuable card in the finished binder.
    let crownJewel: Card?
    /// The market value of that crown-jewel copy (reflects its foil/grade).
    let crownJewelValue: Double
    /// Which completed collection this is for the player (1 = their first win).
    let runNumber: Int
    /// Deterministic seed for the procedural crest, so a given run always
    /// renders the same emblem and two different runs almost never collide.
    let seed: String

    // Superlatives printed on the card.
    let packsOpened: Int
    let foilsPulled: Int
    let ultrasPulled: Int
    let bestGrade: Int
    let peakSale: Double
    let netWorth: Double

    static func make(from core: GameCore) -> RunSignature {
        let s = core.stats
        let element = dominantElement(core.instances)
        let (title, accolade) = earnedTitle(stats: s, element: element)
        let crownInst = core.instances.max { $0.currentValue < $1.currentValue }
        let seed = [s.packsOpened, s.foilsPulled, s.ultrasPulled, s.ultrasPulled &+ s.cardsPulled,
                    s.bestGrade, Int(s.peakSale.rounded()), Int(core.netWorth.rounded())]
            .map(String.init)
            .joined(separator: "-") + "-" + element.rawValue

        return RunSignature(
            title: title,
            accolade: accolade,
            element: element,
            rank: .forPacks(s.packsOpened),
            crownJewel: crownInst?.card,
            crownJewelValue: crownInst?.currentValue ?? 0,
            runNumber: max(1, core.lifetimeIncludingCurrentRun.runsWon),
            seed: seed,
            packsOpened: s.packsOpened,
            foilsPulled: s.foilsPulled,
            ultrasPulled: s.ultrasPulled,
            bestGrade: s.bestGrade,
            peakSale: s.peakSale,
            netWorth: core.netWorth
        )
    }

    // MARK: Derivation

    /// The element the player held the most copies of (dupes included), so it
    /// reflects the flavor of *this* run rather than the catalogue. Ties resolve
    /// in `Element.allCases` order for determinism.
    static func dominantElement(_ instances: [CardInstance]) -> Element {
        var counts: [Element: Int] = [:]
        for inst in instances { counts[inst.card.element, default: 0] += 1 }
        var best: Element = .fire
        var bestCount = -1
        for e in Element.allCases {
            let c = counts[e] ?? 0
            if c > bestCount { bestCount = c; best = e }
        }
        return best
    }

    /// The most notable *flavor* feat of the run becomes the card's title. Rank
    /// already owns efficiency, so titles capture a different dimension: luck and
    /// nerve. If nothing stands out — the common case — the card is themed to the
    /// player's dominant element instead, which keeps most winning cards tied to
    /// their affinity while genuinely lucky runs earn something rarer.
    ///
    /// Each candidate carries an "intensity" (how far past its bar it landed) so
    /// the strongest standout wins when several apply. Bars are tuned against the
    /// reference completion and are safe to adjust.
    static func earnedTitle(stats s: Stats, element: Element) -> (title: String, accolade: String) {
        struct Candidate { let intensity: Double; let title: String; let accolade: String }
        var candidates: [Candidate] = []

        // Foil luck: foils are ~1% of pulls, so notably more is real fortune.
        let foilRate = s.cardsPulled > 0 ? Double(s.foilsPulled) / Double(s.cardsPulled) : 0
        if foilRate >= 0.016, s.foilsPulled >= 8 {
            candidates.append(.init(intensity: (foilRate - 0.016) / 0.016,
                                    title: "The Gilded",
                                    accolade: "Pulled \(s.foilsPulled) shimmering foils"))
        }

        // Ultra luck: more ultras per pack than the drop rate should give.
        let ultraRate = s.packsOpened > 0 ? Double(s.ultrasPulled) / Double(s.packsOpened) : 0
        if ultraRate >= 0.20, s.ultrasPulled >= 10 {
            candidates.append(.init(intensity: (ultraRate - 0.20) / 0.20,
                                    title: "The Apex",
                                    accolade: "Chased down \(s.ultrasPulled) ultra rares"))
        }

        // Nerve: a single sale worth nearly as much as the best card ever held.
        if s.peakSale >= 300, s.peakCardValue > 0 {
            let ratio = s.peakSale / s.peakCardValue
            if ratio >= 0.9 {
                candidates.append(.init(intensity: ratio - 0.9,
                                        title: "The Closer",
                                        accolade: "Flipped a single card for $\(Int(s.peakSale.rounded()))"))
            }
        }

        if let best = candidates.max(by: { $0.intensity < $1.intensity }) {
            return (best.title, best.accolade)
        }
        return (element.masterTitle, "Master of every \(element.display) Spryte")
    }
}
