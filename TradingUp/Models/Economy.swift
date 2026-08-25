import Foundation

/// All economic tuning lives here. Values scale per set (index = set - 1).
enum Economy {

    static let startingCash: Double = 100
    static let packSize = 6

    // Per-set pricing (set 1...5)
    static let packPrices: [Double] = [10, 30, 75, 160, 400]
    static let gradeFees:  [Double] = [2, 4, 6, 8, 10]

    static func packPrice(set: Int) -> Double { packPrices[clampIndex(set)] }
    static func gradeFee(set: Int) -> Double { gradeFees[clampIndex(set)] }

    /// The lowest pack price in the game — the least cash needed to buy any pack.
    /// Falling below this with no way left to raise it ends the game.
    static var cheapestPackPrice: Double { packPrices.min() ?? 0 }

    // Booster box
    static let boxPacks = 12
    static let boxGuaranteeUltras = 3
    static let boxGuaranteeFoils = 2
    static func boxPrice(set: Int) -> Double { packPrice(set: set) * 11 }

    // Sell-back spread: the shop buys duplicates back at a fraction of their market
    // value, so churning packs and dumping dupes is a net loss over time. This
    // is the main source of losing risk — filling out a set squeezes your cash.
    //
    // Calibrated against what the shop actually sells. At 65% this was survivable
    // only because booster boxes existed: their guaranteed ultras and foils were
    // the faucet that paid for the spread. With boxes off the shelf
    // (`FeatureFlags.removeBoosterBoxes`) a 65% spread bled even careful players
    // out — the harness put thoughtful play at a 27% win rate, with the skill gap
    // all but gone. 75% makes a packs-only shop work again: thoughtful play wins
    // ~59% while reckless spam-and-dump busts ~61%, a 20-point skill gap. That is
    // a deliberately tighter game than the 69% boxes-era win rate; the harness
    // floor was moved to 55% to match. Each point of sell-back is worth roughly
    // 3 points of thoughtful win rate here (0.76 → 62%, 0.77 → 66%, 0.78 → 69%),
    // so retune in small steps and re-run the harness in the same breath.
    static let sellbackRate = 0.75
    static func sellback(_ value: Double) -> Double { value * sellbackRate }

    // Set unlocking: set N stays locked until this many *unique* cards are owned.
    // Set 1 is free; each later set costs 25 more uniques (2→25, 3→50, 4→75, 5→100).
    static let uniquesToUnlockPerSet = 25
    static func uniquesToUnlock(set: Int) -> Int { max(0, (set - 1) * uniquesToUnlockPerSet) }

    // Pack composition
    static let commonsPerPack = 3
    static let uncommonsPerPack = 2
    static let ultraHitChance = 0.20   // otherwise the "hit" slot is a rare

    // Foils
    static let foilChance = 0.01
    static let foilMultiplier = 3.0

    // Bonuses
    //
    // Evolution-line completion still pays cash: it's the run's main *non-sale*
    // faucet, the thing that lets an early Show grow its holdings without dumping
    // cards at the 75% buylist. Completing a whole *set* no longer pays cash at
    // all (v1 did, at 15× pack price) — in the roguelite that's the `setMaster`
    // milestone instead (a permanent unlock + Renown), see `Milestone`.
    static func evolutionBonus(set: Int, stageCount: Int) -> Double {
        let p = packPrice(set: set)
        return stageCount >= 3 ? p * 0.5 : p * 0.25
    }

    // MARK: - The Circuit (roguelite run structure)
    //
    // A run is a *Season*: a climb through `seasonShows` Shows. Each Show sets a
    // `quota` — a net-worth bar (cash + collection value) you must reach to
    // "Make the Cut" and advance — that you have `ripsPerShow` pack-opens to
    // clear. Using net worth (not banked cash) as the bar is deliberate: opening
    // packs is ~EV-neutral, so it neither trivially clears nor tanks the bar; you
    // climb by *adding value* (grading, foils, evolution lines, relics) faster
    // than the bar rises, within a finite pull budget. Clearing Show
    // `seasonShows` wins the Season; running out of rooms to grow before the bar
    // is met busts it. Both bank Renown — death is progress.
    static let seasonShows = 8

    /// Net-worth bar for a Show, escalating geometrically from `quotaBase`.
    /// Tuned so a Set-1-only player gets a real multi-Show climb and a fully
    /// unlocked player can chase the Championship. Calibrated by the verify
    /// harness — re-run it after any change here.
    static let quotaBase: Double = 110
    static let quotaGrowth: Double = 1.12
    static func quota(show: Int) -> Double {
        let s = max(1, show)
        return (quotaBase * pow(quotaGrowth, Double(s - 1))).rounded()
    }

    /// Pack-opens allowed per Show before the room closes. Flat by default;
    /// Trainers and Guild upgrades add to it. The clock that stops a Show from
    /// being ground out.
    static let baseRipsPerShow = 7
    static func ripsPerShow(bonus: Int = 0) -> Int { baseRipsPerShow + bonus }

    // Energy powers the single-use Power-Ups. A small persistent pool per Season,
    // refilled only by Energy cards and a few Trainers — never automatically —
    // so spending it is a real choice.
    static let startingEnergy = 2
    static let baseMaxEnergy = 6

    /// Instant cash paid by the Market Tip Power-Up, scaled to the Show so it
    /// stays relevant as the bar climbs (roughly a tenth of the Show's bar).
    static func marketTipCash(show: Int) -> Double { (quota(show: show) * 0.10).rounded() }

    /// The starting bankroll of a fresh Season, including any Guild "Stake"
    /// upgrade the player has bought with Renown.
    static func startingStake(stakeLevel: Int) -> Double {
        startingCash + Double(stakeLevel) * stakeUpgradeStep
    }

    // MARK: - Renown (meta-currency)
    static let renownPerShowCleared = 2
    static let renownChampionBonus = 6
    /// Total Renown a finished Season pays out from its progress alone
    /// (milestone Renown is awarded separately, once ever, as each fires).
    static func seasonRenown(showsCleared: Int, champion: Bool) -> Int {
        showsCleared * renownPerShowCleared + (champion ? renownChampionBonus : 0)
    }

    // MARK: - Bazaar
    static let draftChoices = 3
    static let bazaarSlots = 3
    /// Reroll price for the Bazaar's stock, rising each time within a visit.
    static func rerollCost(rerolls: Int) -> Double { Double(6 + rerolls * 6) }

    // MARK: - Collectors' Guild (Renown-purchased permanent upgrades)
    //
    // Each upgrade is a capped ladder; `guildCost` is the Renown price of the
    // *next* level. Effects are read where they apply (starting stake, rip/energy
    // budgets, Trainer slots).
    static let stakeUpgradeStep: Double = 30      // +$30 starting cash per level
    static let baseTrainerSlots = 3

    static func guildMaxLevel(_ u: GuildUpgrade) -> Int {
        switch u {
        case .stake:       return 5
        case .trainerSlot: return 3
        case .rip:         return 4
        case .energy:      return 4
        }
    }
    static func guildCost(_ u: GuildUpgrade, currentLevel: Int) -> Int {
        let n = currentLevel + 1
        switch u {
        case .stake:       return 2 * n
        case .trainerSlot: return 5 * n
        case .rip:         return 4 * n
        case .energy:      return 3 * n
        }
    }

    // MARK: Grading table (grade, odds %, value multiplier)
    static let gradeTable: [(grade: Int, odds: Int, mult: Double)] = [
        (1, 1, 10.0), (2, 2, 0.10), (3, 3, 0.25), (4, 4, 0.40), (5, 5, 0.55),
        (6, 10, 0.70), (7, 15, 0.85), (8, 35, 1.00), (9, 15, 2.00), (10, 10, 5.00),
    ]

    static func gradeMultiplier(_ grade: Int) -> Double {
        gradeTable.first { $0.grade == grade }?.mult ?? 1.0
    }

    /// The luckiest grade a card can roll *by value* — which is PSA 1, the 10×
    /// "authentic oddity", not PSA 10. Used to judge whether a duplicate is
    /// worth grading before it's sold.
    static var luckiestGrade: Int { (gradeTable.max { $0.mult < $1.mult })?.grade ?? 10 }

    static func gradeLabel(_ grade: Int) -> String {
        switch grade {
        case 10: return "GEM MINT"
        case 9: return "MINT"
        case 8: return "NM-MINT"
        case 6...7: return "EX-MINT"
        case 3...5: return "PLAYED"
        case 2: return "POOR"
        case 1: return "AUTHENTIC ODDITY"
        default: return "GRADED"
        }
    }

    static func rollGrade<G: RandomNumberGenerator>(using rng: inout G) -> Int {
        let roll = Int.random(in: 1...100, using: &rng)
        var acc = 0
        for row in gradeTable {
            acc += row.odds
            if roll <= acc { return row.grade }
        }
        return 8
    }

    // MARK: Value
    static func value(base: Double, foil: Bool, grade: Int?) -> Double {
        var v = base
        if foil { v *= foilMultiplier }
        if let g = grade { v *= gradeMultiplier(g) }
        return v
    }

    private static func clampIndex(_ set: Int) -> Int {
        min(max(set - 1, 0), packPrices.count - 1)
    }
}
