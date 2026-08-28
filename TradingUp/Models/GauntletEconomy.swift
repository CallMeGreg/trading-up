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

    // MARK: Meta progression — Trainer XP & levels (docs/DESIGN.md §14.3)

    /// Trainers cap at 10 levels. XP is earned per cleared run and scales with tier
    /// (Hard pays the most), so a Trainer matures over a handful of wins rather than
    /// a grind. These magnitudes are tunable; the *shape* — perks are sidegrades and
    /// a level-0 Trainer can already clear Hard — is the guardrail the harness holds.
    static let maxTrainerLevel = 10

    /// XP granted per round cleared, by tier (Hard pays the most). Every cleared
    /// round is banked — even on a run that later busts — so partial progress still
    /// matures a Trainer. See `runXP`.
    static func roundClearXP(_ tier: GauntletTier) -> Int {
        switch tier {
        case .easy: return 2
        case .medium: return 3
        case .hard: return 5
        }
    }

    /// A one-off bonus for actually *winning* the whole Gauntlet at a tier, on top
    /// of the per-round XP.
    static func completionBonus(_ tier: GauntletTier) -> Int {
        switch tier {
        case .easy: return 3
        case .medium: return 6
        case .hard: return 10
        }
    }

    /// XP a finished run banks: `roundsCleared` per-round XP plus a completion bonus
    /// on a win. A run that doesn't get past round 1 (0 rounds cleared) banks
    /// nothing, so XP always reflects real progress.
    static func runXP(tier: GauntletTier, roundsCleared: Int, won: Bool) -> Int {
        guard roundsCleared >= 1 else { return 0 }
        return roundsCleared * roundClearXP(tier) + (won ? completionBonus(tier) : 0)
    }

    /// XP for a full clear (win) at each tier — every round plus the completion
    /// bonus. Hard pays the most. This is the headline number the results screen
    /// and tests speak in.
    static func clearXP(_ tier: GauntletTier) -> Int {
        runXP(tier: tier, roundsCleared: rounds(tier), won: true)
    }

    /// Cumulative XP required to *reach* each level (index 0 = level 1 = 0 XP). The
    /// gaps grow ~1.4× per level, so each level is meaningfully harder to earn than
    /// the last — a Trainer climbs fast early and matures over many runs. Partial
    /// runs feed the same pool, so progress is always moving. Reaching the cap is a
    /// real commitment (≈8 Hard wins), not a formality.
    static let trainerLevelThresholds: [Int] = [0, 10, 24, 44, 72, 110, 160, 225, 320, 460]

    /// The level a Trainer is at for a given lifetime XP total (clamped to the cap).
    static func trainerLevel(forXP xp: Int) -> Int {
        var level = 1
        for (i, need) in trainerLevelThresholds.enumerated() where xp >= need { level = i + 1 }
        return min(level, maxTrainerLevel)
    }

    /// XP still needed to reach the next level, or nil once a Trainer is maxed.
    static func xpToNextLevel(fromXP xp: Int) -> Int? {
        let lvl = trainerLevel(forXP: xp)
        guard lvl < maxTrainerLevel, lvl < trainerLevelThresholds.count else { return nil }
        return trainerLevelThresholds[lvl] - xp
    }

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
