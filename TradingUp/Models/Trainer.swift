import Foundation

/// The Gauntlet milestone a specialist Trainer is unlocked by. The Rookie (the
/// neutral starter) has none — it's always available — but every specialist is
/// earned by hitting a lifetime stat tracked in `GauntletProgress.stats`, so
/// meta progression is about *earning the roster*. (The mystery Trainer's reveal
/// isn't a single stat either — see `GauntletProgress`.)
struct TrainerUnlock: Codable, Hashable {
    /// Which `GauntletStat` gates this Trainer.
    let stat: String
    /// The value of `stat` at which the Trainer unlocks.
    let threshold: Int
    /// A one-line requirement shown on the locked card.
    let summary: String
    /// The unit for the progress line, e.g. "packs ripped" → "12 / 25 packs ripped".
    let noun: String
}

/// A Trainer's five-skill profile — a Madden-style dot graph, 1…5 pips each. The
/// scores *are* the Trainer's identity: they derive its run advantage (via
/// `runMods`) instead of a hand-written bundle, so a Trainer's card and its
/// mechanics can never drift apart. `3` is the neutral baseline — the Rookie is a
/// flat 3 across the board; above 3 is a specialty, below 3 a real weakness. The
/// model is symmetric, so a spiky Trainer trades strength for weakness rather than
/// being a strict upgrade. See docs/DESIGN.md §14.3.
struct TrainerSkills: Codable, Hashable {
    var energy: Int       // pack rips per round
    var aura: Int         // default Aura each card scores
    var selling: Int      // cash returned when you sell a card
    var grading: Int      // grading luck & fee
    var inventory: Int    // Showcase + Catalyst capacity

    /// The Rookie's balanced profile, and the neutral point the whole model pivots
    /// around: a flat 3 confers exactly `RunMods.none`.
    static let neutral = TrainerSkills(energy: 3, aura: 3, selling: 3, grading: 3, inventory: 3)

    /// This profile's score on a given axis — lets the card iterate the five axes
    /// generically.
    func score(_ axis: TrainerSkillAxis) -> Int {
        switch axis {
        case .energy:    return energy
        case .aura:      return aura
        case .selling:   return selling
        case .grading:   return grading
        case .inventory: return inventory
        }
    }

    /// Raw pip total — a rough balance read only (Energy and Aura are worth more per
    /// pip, so the design budget is weighted; this is not that budget).
    var total: Int { energy + aura + selling + grading + inventory }

    /// The run advantage these scores confer, assembled from the symmetric per-pip
    /// model in `GauntletSkillTuning` (the balance seam, kept in `GauntletEconomy`).
    var runMods: RunMods { GauntletSkillTuning.runMods(for: self) }

    /// A human phrase for every skill that sits off the neutral 3, in card order —
    /// the concrete run effect each pip actually confers, so the card, the balance
    /// harness, and the docs can all show a Trainer's real edge and weaknesses.
    /// Empty for the flat-3 Rookie.
    var effectLines: [(axis: TrainerSkillAxis, text: String)] {
        TrainerSkillAxis.allCases.compactMap { axis in
            GauntletSkillTuning.effect(axis, score: score(axis)).map { (axis, $0) }
        }
    }
}

/// The five Trainer skills, in card display order, each with the SF Symbol its
/// row uses. SF Symbol *names* are plain strings, so this stays Foundation-only
/// like the rest of `Models/`; the view turns them into images.
enum TrainerSkillAxis: String, CaseIterable, Codable, Hashable {
    case energy, aura, selling, grading, inventory

    var title: String {
        switch self {
        case .energy:    return "Energy"
        case .aura:      return "Aura"
        case .selling:   return "Selling"
        case .grading:   return "Grading"
        case .inventory: return "Inventory"
        }
    }

    /// What the skill governs, for the card sub-label and the docs.
    var detail: String {
        switch self {
        case .energy:    return "Pack rips each round"
        case .aura:      return "Aura every card scores"
        case .selling:   return "Cash back when you sell"
        case .grading:   return "Grading luck and fees"
        case .inventory: return "Showcase & Catalyst slots"
        }
    }

    /// The SF Symbol the card draws beside the skill name. Inventory's icon was an
    /// explicit ask — the display-case grid glyph.
    var symbol: String {
        switch self {
        case .energy:    return "bolt.fill"
        case .aura:      return "sparkles"
        case .selling:   return "dollarsign.circle.fill"
        case .grading:   return "checkmark.seal.fill"
        case .inventory: return "square.grid.2x2.fill"
        }
    }
}

/// A Gauntlet "Trainer": the character a player picks for a run. Each is defined
/// by a five-skill profile (`TrainerSkills`) that both draws its card graph and
/// derives its always-on run advantage (`mods`). The advantages are deliberately
/// *sidegrades*, never a power requirement: the balance harness proves a neutral
/// run still sits inside the intended Hard curve. See docs/DESIGN.md §14.3.
struct Trainer: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let blurb: String

    /// The five-skill profile that defines this Trainer — its card graph *and* its
    /// mechanics.
    var skills: TrainerSkills

    /// The milestone that unlocks this Trainer, or `nil` for the always-available
    /// Rookie and for the mystery Trainer (whose reveal condition isn't a single
    /// stat — see `GauntletProgress.isMysteryTrainerEarned`).
    var unlock: TrainerUnlock? = nil

    /// A hidden challenger whose name and skills stay concealed ("???") on the
    /// locked card until it's earned. Only Red sets this.
    var mysteryUntilUnlocked: Bool = false

    /// The modifiers this Trainer contributes to a run, derived from `skills`.
    /// Attuned Catalysts add to this in `GauntletRun.mods`.
    var mods: RunMods { skills.runMods }
}

extension Trainer {

    /// A Trainer with no edge at all — the balanced 3/3/3/3/3 Rookie. The harness
    /// uses it to prove the mode is winnable on pure skill, so real Trainers stay
    /// gravy rather than gates.
    static let neutral = Trainer(
        id: "neutral", name: "Average Joe",
        blurb: "No specialty and no weakness — a balanced three across the board.",
        skills: .neutral)

    /// The mystery Trainer, hidden as "???" until the player has beaten Hard with
    /// every other Trainer. Overwhelming Energy and Aura and a roomy Showcase, but
    /// the bare minimum in Selling and Grading. Kept out of `roster` iteration order
    /// below only by convention; it *is* included so it renders (concealed) and unlocks.
    static let red = Trainer(
        id: "red", name: "Ash",
        blurb: "A silent challenger. Overwhelming Energy and Aura and a roomy Showcase — but no head for selling or grading.",
        skills: TrainerSkills(energy: 5, aura: 5, selling: 1, grading: 1, inventory: 4),
        mysteryUntilUnlocked: true)

    /// The shipped roster. Each leans into a different pair of skills so builds
    /// diverge from the Trainer up, and each is unlocked by playing into that same
    /// lane, so the milestones teach the mode. Profiles are symmetric around the
    /// neutral 3 (Energy, Aura, Selling, Grading, Inventory), roughly balanced on a
    /// weighted budget: strength in a specialty is paid for with weakness
    /// elsewhere. The Rookie is the free starter; these are earned. The mystery
    /// Red sits last and stays concealed until it's earned.
    static let roster: [Trainer] = [
        Trainer(id: "ripper", name: "Jack the Ripper",
                blurb: "Lives for the tear — boundless Energy, but no patience for the fine print.",
                skills: TrainerSkills(energy: 5, aura: 2, selling: 2, grading: 1, inventory: 4),
                unlock: TrainerUnlock(stat: GauntletStat.packsRipped, threshold: 100,
                                      summary: "Rip 100 packs across your Gauntlet runs.",
                                      noun: "packs ripped")),

        Trainer(id: "curator", name: "Curator Curtis",
                blurb: "Builds wide and deep — an unmatched Showcase and a sharp eye for Aura.",
                skills: TrainerSkills(energy: 2, aura: 4, selling: 1, grading: 3, inventory: 5),
                unlock: TrainerUnlock(stat: GauntletStat.maxShowcase, threshold: 12,
                                      summary: "Build a Showcase of 12 cards in a single run.",
                                      noun: "widest Showcase")),

        // "Fred the Farmer" is the display name; the id stays "appraiser" so
        // existing Trainer progress saves (keyed by id in GauntletProgress) survive intact.
        Trainer(id: "appraiser", name: "Fred the Farmer",
                blurb: "Grows a richer harvest — everything radiates a little more Aura.",
                skills: TrainerSkills(energy: 2, aura: 5, selling: 2, grading: 2, inventory: 3),
                unlock: TrainerUnlock(stat: GauntletStat.bestRoundScore, threshold: 500,
                                      summary: "Reach a round Aura of 500.",
                                      noun: "best round Aura")),

        Trainer(id: "grader", name: "Lucky Lucy",
                blurb: "Steady hands at the slab — grading is an art she has mastered.",
                skills: TrainerSkills(energy: 2, aura: 3, selling: 2, grading: 5, inventory: 3),
                unlock: TrainerUnlock(stat: GauntletStat.cardsGraded, threshold: 100,
                                      summary: "Grade 100 cards across your Gauntlet runs.",
                                      noun: "cards graded")),

        Trainer(id: "merchant", name: "Sally the Seller",
                blurb: "Works the floor — nobody turns a card into cash faster.",
                skills: TrainerSkills(energy: 3, aura: 2, selling: 5, grading: 2, inventory: 3),
                unlock: TrainerUnlock(stat: GauntletStat.maxCashHeld, threshold: 250,
                                      summary: "Hold $250 cash at once during a run.",
                                      noun: "most cash held")),

        red,
    ]

    static func byId(_ id: String) -> Trainer? {
        if id == neutral.id { return neutral }
        return roster.first { $0.id == id }
    }
}
