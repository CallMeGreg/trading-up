import Foundation

/// The Gauntlet milestone a specialist Trainer is unlocked by. The Rookie (the
/// neutral starter) has none — it's always available — but every specialist is
/// earned by hitting a lifetime stat tracked in `GauntletProgress.stats`, so
/// meta progression is about *earning the roster*, not just levelling it.
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

/// A Gauntlet "Trainer": the character a player picks for a run. Each has one
/// always-on base advantage (its level-0 `mods`) and a meta-progression track —
/// clearing runs grants XP toward levels, and levels offer sidegrade perks
/// (modelled later). The base advantages are deliberately *sidegrades*, never a
/// power requirement: the balance harness proves a neutral, level-0 run still
/// clears Hard. See docs/DESIGN.md §14.3.
struct Trainer: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let blurb: String

    /// Always-on level-0 advantage.
    var baseMods: RunMods

    /// The milestone that unlocks this Trainer, or `nil` for the always-available
    /// Rookie.
    var unlock: TrainerUnlock? = nil

    // Meta progression (persisted across runs).
    var level: Int = 0
    var xp: Int = 0

    /// The modifiers actually in force this run. For now this is just the base
    /// advantage; perk contributions will fold in here as levels are designed.
    var activeMods: RunMods { baseMods }
}

extension Trainer {

    /// A Trainer with no advantage at all — used by the harness to prove the mode
    /// is winnable on pure skill, so real Trainers stay gravy rather than gates.
    static let neutral = Trainer(
        id: "neutral", name: "Rookie",
        blurb: "No edge — just you, the packs, and the bar.",
        baseMods: .none)

    /// The shipped roster. Each leans into a different strategic lane so builds
    /// diverge from the Trainer up — and each is unlocked by playing into that same
    /// lane, so the milestones teach the mode. The Rookie is the free starter; these
    /// five are earned. Thresholds are tunable meta pacing, not a difficulty knob.
    static let roster: [Trainer] = [
        Trainer(id: "ripper", name: "Ripper",
                blurb: "Lives for the tear. One extra rip every round.",
                baseMods: { var m = RunMods.none; m.extraRipsPerRound = 1; return m }(),
                unlock: TrainerUnlock(stat: GauntletStat.packsRipped, threshold: 100,
                                      summary: "Rip 100 packs across your Gauntlet runs.",
                                      noun: "packs ripped")),

        Trainer(id: "curator", name: "Curator",
                blurb: "Reads the room. A wider Showcase and richer evolution bonuses.",
                baseMods: { var m = RunMods.none; m.extraSlots = 1; m.evoLineBonusBonus = 0.20; return m }(),
                unlock: TrainerUnlock(stat: GauntletStat.maxShowcase, threshold: 12,
                                      summary: "Build a Showcase of 12 cards in a single run.",
                                      noun: "widest Showcase")),

        Trainer(id: "appraiser", name: "Appraiser",
                blurb: "Sees value others miss. Everything scores a little higher.",
                baseMods: { var m = RunMods.none; m.appraisalMult = 1.10; return m }(),
                unlock: TrainerUnlock(stat: GauntletStat.bestRoundScore, threshold: 500,
                                      summary: "Reach a round Aura of 500.",
                                      noun: "best round Aura")),

        Trainer(id: "grader", name: "Grader",
                blurb: "Steady hands at the slab. Cheaper, luckier grading.",
                baseMods: { var m = RunMods.none; m.gradeFeeMult = 0.5; m.gradeLuckBonus = 0.12; return m }(),
                unlock: TrainerUnlock(stat: GauntletStat.cardsGraded, threshold: 100,
                                      summary: "Grade 100 cards across your Gauntlet runs.",
                                      noun: "cards graded")),

        Trainer(id: "merchant", name: "Merchant",
                blurb: "Works the floor. Better sell-back, fatter stipends, seed cash.",
                baseMods: { var m = RunMods.none; m.sellbackBonus = 0.08; m.stipendMult = 1.25; m.startingCashBonus = 20; return m }(),
                unlock: TrainerUnlock(stat: GauntletStat.maxCashHeld, threshold: 250,
                                      summary: "Hold $250 cash at once during a run.",
                                      noun: "most cash held")),
    ]

    static func byId(_ id: String) -> Trainer? {
        if id == neutral.id { return neutral }
        return roster.first { $0.id == id }
    }
}
