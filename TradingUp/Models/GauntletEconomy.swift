import Foundation

// MARK: - Difficulty tier

/// The three Gauntlet run lengths. Each is unlocked by clearing the previous one
/// once (Easy → Medium → Hard). See docs/DESIGN.md §14.5.
enum GauntletTier: String, Codable, CaseIterable, Hashable {
    case easy, medium, hard

    var display: String { rawValue.capitalized }

    /// Sort / unlock order.
    var order: Int {
        switch self {
        case .easy: return 0
        case .medium: return 1
        case .hard: return 2
        }
    }

    /// The tier that must be cleared before this one unlocks (nil for Easy).
    var requires: GauntletTier? {
        switch self {
        case .easy: return nil
        case .medium: return .easy
        case .hard: return .medium
        }
    }
}

// MARK: - Run modifiers

/// The single currency every run-long buff speaks in. Trainers (their base
/// advantage and, later, perks) and attuned Catalysts each contribute a
/// `RunMods`, and the run sums them with `+` so their effects compose uniformly.
/// Additive fields stack; multiplicative fields (the `*Mult`s) multiply. This is
/// the seam the balance harness tunes against — see docs/DESIGN.md §14.2.
struct RunMods: Codable, Hashable {
    var extraRipsPerRound = 0
    var bonusRipChance = 0.0  // 0…1 chance of one *additional* rip, rolled per round
    var extraSlots = 0
    var extraCatalystSlots = 0
    var auraMult = 1.0        // global score multiplier
    var evoLineBonusBonus = 0.0    // adds to the completed-evolution-line bonus
    var foilChanceBonus = 0.0      // added to Economy.foilChance on rips
    var ultraChanceBonus = 0.0     // added to Economy.ultraHitChance on rips
    var sellbackBonus = 0.0        // added to Economy.sellbackRate (capped)
    var gradeLuckBonus = 0.0       // 0…1 chance to roll a grade with advantage
    var gradeFeeMult = 1.0         // scales the grading fee
    var startingCashBonus = 0.0
    var stipendMult = 1.0          // scales the round-clear stipend

    static let none = RunMods()

    static func + (a: RunMods, b: RunMods) -> RunMods {
        var r = RunMods()
        r.extraRipsPerRound     = a.extraRipsPerRound + b.extraRipsPerRound
        r.bonusRipChance        = a.bonusRipChance + b.bonusRipChance
        r.extraSlots            = a.extraSlots + b.extraSlots
        r.extraCatalystSlots    = a.extraCatalystSlots + b.extraCatalystSlots
        r.auraMult         = a.auraMult * b.auraMult
        r.evoLineBonusBonus     = a.evoLineBonusBonus + b.evoLineBonusBonus
        r.foilChanceBonus       = a.foilChanceBonus + b.foilChanceBonus
        r.ultraChanceBonus      = a.ultraChanceBonus + b.ultraChanceBonus
        r.sellbackBonus         = a.sellbackBonus + b.sellbackBonus
        r.gradeLuckBonus        = a.gradeLuckBonus + b.gradeLuckBonus
        r.gradeFeeMult          = a.gradeFeeMult * b.gradeFeeMult
        r.startingCashBonus     = a.startingCashBonus + b.startingCashBonus
        r.stipendMult           = a.stipendMult * b.stipendMult
        return r
    }

    /// A concise, mechanical description of what this bundle does, derived straight
    /// from its fields so displayed text always matches the real effect. Used by
    /// Catalysts (Trainers show a skill graph instead). Empty when the bundle is
    /// neutral.
    var effectSummary: String {
        func pct(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }
        var parts: [String] = []
        if extraRipsPerRound != 0 {
            parts.append("+\(extraRipsPerRound) rip\(extraRipsPerRound == 1 ? "" : "s") every round")
        }
        if bonusRipChance != 0 { parts.append("\(pct(bonusRipChance)) chance of a bonus rip") }
        if extraSlots != 0 {
            parts.append("+\(extraSlots) showcase slot\(extraSlots == 1 ? "" : "s")")
        }
        if extraCatalystSlots != 0 {
            parts.append("+\(extraCatalystSlots) catalyst slot\(extraCatalystSlots == 1 ? "" : "s")")
        }
        if foilChanceBonus != 0 { parts.append("+\(pct(foilChanceBonus)) foil chance") }
        if ultraChanceBonus != 0 { parts.append("+\(pct(ultraChanceBonus)) ultra chance") }
        if gradeLuckBonus != 0 { parts.append("+\(pct(gradeLuckBonus)) grading luck") }
        if sellbackBonus != 0 { parts.append("+\(pct(sellbackBonus)) sell-back") }
        if auraMult != 1 { parts.append("+\(pct(auraMult - 1)) Aura") }
        if evoLineBonusBonus != 0 { parts.append("+\(pct(evoLineBonusBonus)) evolution bonus") }
        if gradeFeeMult != 1 { parts.append("\(pct(gradeFeeMult))-cost grading") }
        if stipendMult != 1 { parts.append("+\(pct(stipendMult - 1)) round payout") }
        if startingCashBonus != 0 { parts.append("+" + String(format: "$%.0f", startingCashBonus) + " seed cash") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Trainer skills → run advantage (docs/DESIGN.md §14.3)

/// Turns a Trainer's five-skill profile into the `RunMods` it plays with. The
/// model is **symmetric**: a score of 3 is neutral (identical to `RunMods.none`),
/// each pip above 3 grants a bonus and each pip below 3 an equal-shaped penalty —
/// so a spiky Trainer trades strength in its specialty for real weakness
/// elsewhere, never a strict upgrade. *Which* lever each skill drives is fixed
/// here; the per-pip magnitudes are the balance knobs.
///
/// - TODO(balance): every per-pip step below is intentionally `0`, so today every
///   Trainer resolves to `RunMods.none` (mechanically the Rookie). The graphs are
///   wired but unmagnituded. A dedicated tuning pass sets these numbers and
///   re-runs `tools/verify` to keep the intended Hard curve — a spiky Trainer must
///   stay a sidegrade, never a gate — plus, where the design calls for it, two new
///   downside levers (low Energy risking a lost rip, low Grading rolling with
///   disadvantage). Until then the wiring is real and honest; only the numbers are
///   pending.
enum GauntletSkillTuning {
    /// The pivot score: a flat 3 confers no advantage and no penalty.
    static let neutralScore = 3

    /// Whole pips a score sits above (+) or below (−) neutral.
    static func steps(_ score: Int) -> Int { score - neutralScore }

    /// A symmetric per-pip delta: `steps` scaled by `up` above neutral, `down`
    /// below. With both magnitudes 0 this is 0 everywhere (the current state).
    static func delta(_ score: Int, up: Double, down: Double) -> Double {
        let s = steps(score)
        return s >= 0 ? Double(s) * up : Double(s) * down
    }

    // Per-pip magnitudes — all 0 pending the balance pass (see the note above).
    // Energy → chance of a bonus rip (a guaranteed extra rip is a future capstone).
    static let bonusRipUp = 0.0,  bonusRipDown = 0.0
    // Aura → global score multiplier, symmetric around ×1.
    static let auraUp = 0.0,      auraDown = 0.0
    // Selling → sell-back rate, round stipend, and seed cash.
    static let sellbackUp = 0.0,  sellbackDown = 0.0
    static let stipendUp = 0.0,   stipendDown = 0.0
    static let seedCashUp = 0.0,  seedCashDown = 0.0
    // Grading → luck (roll-with-advantage chance) and fee multiplier.
    static let gradeLuckUp = 0.0, gradeLuckDown = 0.0
    static let gradeFeeUp = 0.0,  gradeFeeDown = 0.0
    // Inventory → Showcase slots (a Catalyst slot is a future capstone).
    static let slotStep = 0

    /// Assemble the run advantage for a profile. Each skill drives its lever(s)
    /// symmetrically around the neutral 3.
    static func runMods(for s: TrainerSkills) -> RunMods {
        var m = RunMods.none
        m.bonusRipChance    = delta(s.energy,  up: bonusRipUp,  down: bonusRipDown)
        m.auraMult          = 1 + delta(s.aura, up: auraUp,     down: auraDown)
        m.sellbackBonus     = delta(s.selling, up: sellbackUp,  down: sellbackDown)
        m.stipendMult       = 1 + delta(s.selling, up: stipendUp, down: stipendDown)
        m.startingCashBonus = delta(s.selling, up: seedCashUp,  down: seedCashDown)
        m.gradeLuckBonus    = delta(s.grading, up: gradeLuckUp, down: gradeLuckDown)
        m.gradeFeeMult      = 1 + delta(s.grading, up: gradeFeeUp, down: gradeFeeDown)
        m.extraSlots        = steps(s.inventory) * slotStep
        return m
    }
}

// MARK: - Gauntlet economy knobs

/// Every Gauntlet balance number lives here, mirroring `Economy` for Classic.
/// The shape (three resources, rising cumulative targets, sell-to-upgrade shop)
/// is fixed by the design; these magnitudes are what `tools/verify` tunes so an
/// optimised build clears Hard, careless play busts, and grinding is never
/// required. See docs/DESIGN.md §14.
enum GauntletEconomy {

    // MARK: Run shape (per tier) — docs/DESIGN.md §14.5

    static func rounds(_ tier: GauntletTier) -> Int {
        switch tier {
        case .easy: return 5
        case .medium: return 7
        case .hard: return 9
        }
    }

    static func ripsPerRound(_ tier: GauntletTier) -> Int {
        switch tier {
        case .easy: return 6
        case .medium: return 6
        case .hard: return 4
        }
    }

    static func startingSlots(_ tier: GauntletTier) -> Int {
        switch tier {
        case .easy: return 8
        case .medium: return 6
        case .hard: return 5
        }
    }

    /// Attunement capacity for Catalysts at the start of a run. Extra slots are
    /// bought in the shop or granted by Trainer mods. (req 4)
    static let baseCatalystSlots = 1

    /// The Hard finale is a boss round: fewer normal rips but a spiked target.
    static func isBossRound(_ tier: GauntletTier, round: Int) -> Bool {
        tier == .hard && round == rounds(tier)
    }

    static let bossExtraRips = 1
    static let bossTargetSpike = 1.65

    /// Rips available in a round before Trainer/Catalyst bonuses.
    static func ripBudget(_ tier: GauntletTier, round: Int) -> Int {
        ripsPerRound(tier) + (isBossRound(tier, round: round) ? bossExtraRips : 0)
    }

    // MARK: Target curve — the cumulative Aura bar each round
    //
    // These three numbers per tier (base, growth, boss spike) are the difficulty
    // dial. The Gauntlet strategy sims in `tools/verify` peg the neutral, level-0
    // curve at roughly:
    //
    //     Easy    optimized ~99% / careless ~99%   (a forgiving, unlosable-if-you-try tutorial)
    //     Medium  optimized ~66% / careless ~37%   (skill gap ~29 pts)
    //     Hard    optimized ~56% / careless ~11%   (skill gap ~45 pts; boss round is the filter)
    //
    // (These sit lower than the old synergy-era curve on purpose: batch-4 replaced the
    // reliable same-element synergy multiplier with an evolution-line completion bonus,
    // which is RNG-gated — you have to pull a line's whole chain — so it can't prop up
    // optimised Aura every round the way synergy did. Medium/Hard optimised win
    // rates fell ~13/~3 pts as a result; the skill *gap* is preserved by grading and
    // shop play, which is where an optimised run really separates from a careless one.)
    //
    // Rounds are single-life — a missed bar ends the run at any tier (no reprints).
    // Medium leans on an extra rip/round rather than a retry to stay winnable.
    // The guardrail: a *neutral* Trainer clears Hard with optimal play (~56% > 45%),
    // so Trainers and Catalysts are gravy, never a requirement (docs/DESIGN.md §14.3).
    // Growth is steep because the Aura engine snowballs ~3× per pack-tier jump;
    // a gentle curve lets an optimised build run away and kills the tension. Retune
    // in small steps and re-run the harness in the same breath — careless win rate is
    // very sensitive to the bar height, optimised much less so.

    /// Round-1 bar per tier. Starts inside what a tier-1 pack can produce so the
    /// opening is survivable; the ramp (below) is what makes a tier hard.
    static func baseTarget(_ tier: GauntletTier) -> Double {
        switch tier {
        case .easy: return 20
        case .medium: return 26
        case .hard: return 18
        }
    }

    /// Per-round multiplicative growth of the bar. Steep enough that a pack-tier
    /// jump (~3×) is chased down over ~2 rounds, so Aura hugs the bar instead
    /// of running away after the opening.
    static func targetGrowth(_ tier: GauntletTier) -> Double {
        switch tier {
        case .easy: return 1.60
        case .medium: return 1.88
        case .hard: return 1.67
        }
    }

    /// The cumulative Aura the whole standing Showcase must reach in `round`.
    static func target(_ tier: GauntletTier, round: Int) -> Double {
        var t = baseTarget(tier) * pow(targetGrowth(tier), Double(round - 1))
        if isBossRound(tier, round: round) { t *= bossTargetSpike }
        return t
    }

    // MARK: Cash — starting stake, stipend, interest

    static let startingCash: Double = 15

    /// A round clear pays a base stipend plus a share of how far you overshot the
    /// bar — so pushing *past* the target, not stopping on it, funds the shop.
    static let baseStipendRate = 0.10   // of the round's target
    static let overshootStipendRate = 0.25

    static func roundClearStipend(_ tier: GauntletTier, round: Int, aura: Double) -> Double {
        let bar = target(tier, round: round)
        let overshoot = max(0, aura - bar)
        return bar * baseStipendRate + overshoot * overshootStipendRate
    }

    /// Interest on unspent cash, paid at each round clear — the reward for *not*
    /// spending (the third force alongside keeping and selling). Capped so banking
    /// is a lever, not a runaway engine.
    static let interestRate = 0.20
    static let interestCap: Double = 40

    static func interest(on cash: Double) -> Double {
        min(cash * interestRate, interestCap)
    }

    /// Unused rips don't evaporate at a clear — they're cashed out. Each rip left
    /// on the table is worth `leftoverRipRate × round`, so a rip banked in a later
    /// (richer) round is worth more, and clearing a round *early* with rips to spare
    /// is rewarded rather than wasted (docs/DESIGN.md §14). This is why the round
    /// auto-resolves the instant the bar is met — the leftover rips pay out.
    static let leftoverRipRate: Double = 5

    static func leftoverRipValue(round: Int, rips: Int) -> Double {
        Double(max(0, rips)) * leftoverRipRate * Double(round)
    }

    // MARK: Aura engine

    /// How much *completing a full evolution line* in the Showcase lifts the value
    /// of that line's cards. Chasing a line to its final stage — not just hoarding
    /// singles — is the core build axis (docs/DESIGN.md §14.4). A line counts as
    /// complete when every one of its stages is present in the Showcase.
    static let baseEvoLineBonus = 1.25

    /// Sell-back can be nudged up by Catalysts/Trainers but never becomes free money.
    static let maxSellbackRate = 0.95

    // MARK: Shop costs

    /// Cost to unlock a single element set's packs this run. Each set is priced
    /// **independently** off its Classic pack price, so a run can buy any locked
    /// set open in any order (not a forced sequential ladder) — richer sets simply
    /// cost more. Returns `nil` for the always-open starter (set 1) or an id off
    /// the rail. Tuned so the first unlock lands around round 2–3 and the top set
    /// stays a late-run investment; the harness holds the difficulty curve.
    static let packUnlockFactor = 1.4
    static func packUnlockCost(set: Int) -> Double? {
        guard set >= 2, set <= maxPackTier else { return nil }
        return Economy.packPrice(set: set) * packUnlockFactor
    }

    /// Cost of the next Showcase slot, given how many have already been bought.
    static let slotCostBase: Double = 30
    static let slotCostGrowth = 1.6
    static func slotCost(purchased: Int) -> Double {
        slotCostBase * pow(slotCostGrowth, Double(purchased))
    }

    /// Cost of the next Catalyst attunement slot.
    static let catalystSlotCostBase: Double = 45
    static let catalystSlotCostGrowth = 1.7
    static func catalystSlotCost(purchased: Int) -> Double {
        catalystSlotCostBase * pow(catalystSlotCostGrowth, Double(purchased))
    }

    /// The highest pack tier a run can reach (mirrors the 5 Classic sets).
    static let maxPackTier = 5

    // MARK: Catalyst faucet

    /// Chance an individual rip also surfaces a Catalyst card to attune or sell.
    static let catalystDropChance = 0.14

    // MARK: Win reward (docs/DESIGN.md §14.6)

    /// The Extended-Art reward rarity for clearing a tier: Easy → common,
    /// Medium → uncommon, Hard → rare with a 20% chance to promote to ultra
    /// (reusing `Economy.ultraHitChance`).
    static func rewardRarity<G: RandomNumberGenerator>(_ tier: GauntletTier, using rng: inout G) -> Rarity {
        switch tier {
        case .easy:   return .common
        case .medium: return .uncommon
        case .hard:   return Double.random(in: 0..<1, using: &rng) < Economy.ultraHitChance ? .ultra : .rare
        }
    }

    /// How many Extended-Art options a win offers — the reward is choose-1-of-3.
    static let rewardOptionCount = 3
}
