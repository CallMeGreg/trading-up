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
    var appraisalMult = 1.0        // global score multiplier
    var synergyPerMatchBonus = 0.0 // adds to the per-element synergy step
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
        r.appraisalMult         = a.appraisalMult * b.appraisalMult
        r.synergyPerMatchBonus  = a.synergyPerMatchBonus + b.synergyPerMatchBonus
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
        case .medium: return 5
        case .hard: return 4
        }
    }

    /// Round retries ("reprints"): a failed round can be replayed with fresh
    /// rips this many times. Hard is single-life.
    static func retries(_ tier: GauntletTier) -> Int {
        switch tier {
        case .easy: return 2
        case .medium: return 1
        case .hard: return 0
        }
    }

    static func startingSlots(_ tier: GauntletTier) -> Int {
        switch tier {
        case .easy: return 8
        case .medium: return 6
        case .hard: return 5
        }
    }

    /// Attunement capacity for Catalysts at the start of a run.
    static let baseCatalystSlots = 3

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

    // MARK: Target curve — the cumulative appraisal bar each round
    //
    // These three numbers per tier (base, growth, boss spike) are the difficulty
    // dial. The Gauntlet strategy sims in `tools/verify` peg the neutral, level-0
    // curve at roughly:
    //
    //     Easy    optimized 100% / careless 100%   (a forgiving, unlosable-if-you-try tutorial)
    //     Medium  optimized  85% / careless  32%   (skill gap ~53 pts)
    //     Hard    optimized  61% / careless   5%   (skill gap ~56 pts; boss round is the filter)
    //
    // The guardrail: a *neutral* Trainer clears Hard with optimal play (~61% > 50%),
    // so Trainers and Catalysts are gravy, never a requirement (docs/DESIGN.md §14.3).
    // Growth is steep because the appraisal engine snowballs ~3× per pack-tier jump;
    // a gentle curve lets an optimised build run away and kills the tension. Retune
    // in small steps and re-run the harness in the same breath — careless win rate is
    // very sensitive to the bar height, optimised much less so.

    /// Round-1 bar per tier. Starts inside what a tier-1 pack can produce so the
    /// opening is survivable; the ramp (below) is what makes a tier hard.
    static func baseTarget(_ tier: GauntletTier) -> Double {
        switch tier {
        case .easy: return 22
        case .medium: return 26
        case .hard: return 18
        }
    }

    /// Per-round multiplicative growth of the bar. Steep enough that a pack-tier
    /// jump (~3×) is chased down over ~2 rounds, so appraisal hugs the bar instead
    /// of running away after the opening.
    static func targetGrowth(_ tier: GauntletTier) -> Double {
        switch tier {
        case .easy: return 1.60
        case .medium: return 1.95
        case .hard: return 1.75
        }
    }

    /// The cumulative appraisal the whole standing Showcase must reach in `round`.
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

    static func roundClearStipend(_ tier: GauntletTier, round: Int, appraisal: Double) -> Double {
        let bar = target(tier, round: round)
        let overshoot = max(0, appraisal - bar)
        return bar * baseStipendRate + overshoot * overshootStipendRate
    }

    /// Interest on unspent cash, paid at each round clear — the reward for *not*
    /// spending (the third force alongside keeping and selling). Capped so banking
    /// is a lever, not a runaway engine.
    static let interestRate = 0.10
    static let interestCap: Double = 40

    static func interest(on cash: Double) -> Double {
        min(cash * interestRate, interestCap)
    }

    // MARK: Appraisal engine

    /// How much each same-element card already in the Showcase lifts a card's
    /// appraisal. Concentrating one element is the core build axis.
    static let baseSynergyPerMatch = 0.06

    /// Sell-back can be nudged up by Catalysts/Trainers but never becomes free money.
    static let maxSellbackRate = 0.95

    // MARK: Shop costs

    /// Cost to raise the pack tier you rip (unlocking a higher set's packs). Keyed
    /// by the set you're upgrading *to*; scales off Classic pack prices. Tuned so
    /// the first upgrade lands around round 2–3 and each later one paces ~2 rounds.
    static let packTierUpgradeFactor = 1.4
    static func packTierUpgradeCost(to set: Int) -> Double {
        Economy.packPrice(set: set) * packTierUpgradeFactor
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

    /// XP granted for clearing a run at each tier (Hard pays the most).
    static func clearXP(_ tier: GauntletTier) -> Int {
        switch tier {
        case .easy: return 1
        case .medium: return 2
        case .hard: return 4
        }
    }

    /// Cumulative XP required to *reach* each level (index 0 = level 1 = 0 XP). A
    /// gentle triangular ramp: ~7 Hard clears to max, proportionally more at the
    /// easier tiers.
    static let trainerLevelThresholds: [Int] = [0, 1, 2, 4, 6, 9, 12, 16, 20, 25]

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
