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
/// always-on advantage that *scales with its level* — a freshly-unlocked Trainer
/// plays at its level-1 `baseMods`, and clearing runs grants XP toward levels that
/// smoothly strengthen that advantage toward its level-`maxTrainerLevel` `maxMods`
/// ceiling. The advantages are deliberately *sidegrades*, never a power
/// requirement: the balance harness proves a neutral run — and a maxed Trainer —
/// still sit inside the intended Hard curve. See docs/DESIGN.md §14.3.
struct Trainer: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let blurb: String

    /// Always-on level-1 advantage — the values a freshly-unlocked Trainer plays
    /// with, identical to what shipped before levels scaled.
    var baseMods: RunMods

    /// The level-`maxTrainerLevel` ceiling this Trainer's advantage grows toward.
    /// `nil` means the Trainer doesn't scale (the Rookie), so its advantage is flat.
    var maxMods: RunMods? = nil

    /// The milestone that unlocks this Trainer, or `nil` for the always-available
    /// Rookie.
    var unlock: TrainerUnlock? = nil

    // Meta progression (persisted across runs).
    var level: Int = 0
    var xp: Int = 0

    /// The modifiers actually in force this run: the level-1 baseline (a reasonable
    /// ~`baselineFraction` of the Trainer's max potential), smoothly interpolated up
    /// to the full `maxMods` at the level cap. Levels below 1 (how the harness
    /// constructs a fresh roster Trainer) read as that level-1 baseline, so a
    /// Trainer always starts useful and matures toward ~5× that edge.
    var activeMods: RunMods {
        guard let ceiling = maxMods else { return baseMods }
        let span = Double(max(GauntletEconomy.maxTrainerLevel - 1, 1))
        let t = Double(max(level, 1) - 1) / span
        return RunMods.lerp(baseMods, ceiling, t)
    }

    /// A level-aware, mechanical one-liner of the advantage in force at this level.
    var effectSummary: String { activeMods.effectSummary }
}

extension Trainer {

    /// Every specialist starts level 1 at this fraction of its level-`maxTrainerLevel`
    /// potential and climbs to the full amount at the cap — so a fresh Trainer is a
    /// *reasonable* baseline (~20%) with real room to grow, not either nothing or
    /// already-maxed. Each roster `baseMods` below is this fraction of its `maxMods`
    /// on the continuous levers (integer identity — the Ripper's rip, the Curator's
    /// slot — is an always-on floor, and `GauntletMetaTests` guards the relationship).
    static let baselineFraction = 0.20

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
                baseMods: { var m = RunMods.none; m.extraRipsPerRound = 1; m.bonusRipChance = 0.12; return m }(),
                maxMods: { var m = RunMods.none; m.extraRipsPerRound = 1; m.bonusRipChance = 0.60; return m }(),
                unlock: TrainerUnlock(stat: GauntletStat.packsRipped, threshold: 100,
                                      summary: "Rip 100 packs across your Gauntlet runs.",
                                      noun: "packs ripped")),

        Trainer(id: "curator", name: "Curator",
                blurb: "Reads the room. A wider Showcase and richer evolution bonuses.",
                baseMods: { var m = RunMods.none; m.extraSlots = 1; m.evoLineBonusBonus = 0.12; return m }(),
                maxMods: { var m = RunMods.none; m.extraSlots = 2; m.evoLineBonusBonus = 0.60; return m }(),
                unlock: TrainerUnlock(stat: GauntletStat.maxShowcase, threshold: 12,
                                      summary: "Build a Showcase of 12 cards in a single run.",
                                      noun: "widest Showcase")),

        // "Farmer" is the display name; the id stays "appraiser" so existing
        // Trainer level/XP saves (keyed by id in GauntletProgress) survive intact.
        Trainer(id: "appraiser", name: "Farmer",
                blurb: "Grows a richer harvest. Everything scores a little higher.",
                baseMods: { var m = RunMods.none; m.auraMult = 1.06; return m }(),
                maxMods: { var m = RunMods.none; m.auraMult = 1.30; return m }(),
                unlock: TrainerUnlock(stat: GauntletStat.bestRoundScore, threshold: 500,
                                      summary: "Reach a round Aura of 500.",
                                      noun: "best round Aura")),

        Trainer(id: "grader", name: "Grader",
                blurb: "Steady hands at the slab. Cheaper, luckier grading.",
                baseMods: { var m = RunMods.none; m.gradeFeeMult = 0.86; m.gradeLuckBonus = 0.09; return m }(),
                maxMods: { var m = RunMods.none; m.gradeFeeMult = 0.3; m.gradeLuckBonus = 0.45; return m }(),
                unlock: TrainerUnlock(stat: GauntletStat.cardsGraded, threshold: 100,
                                      summary: "Grade 100 cards across your Gauntlet runs.",
                                      noun: "cards graded")),

        Trainer(id: "merchant", name: "Merchant",
                blurb: "Works the floor. Better sell-back, fatter stipends, seed cash.",
                baseMods: { var m = RunMods.none; m.sellbackBonus = 0.032; m.stipendMult = 1.12; m.startingCashBonus = 10; return m }(),
                maxMods: { var m = RunMods.none; m.sellbackBonus = 0.16; m.stipendMult = 1.60; m.startingCashBonus = 50; return m }(),
                unlock: TrainerUnlock(stat: GauntletStat.maxCashHeld, threshold: 250,
                                      summary: "Hold $250 cash at once during a run.",
                                      noun: "most cash held")),
    ]

    static func byId(_ id: String) -> Trainer? {
        if id == neutral.id { return neutral }
        return roster.first { $0.id == id }
    }
}
