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
    static func evolutionBonus(set: Int, stageCount: Int) -> Double {
        let p = packPrice(set: set)
        return stageCount >= 3 ? p * 2.0 : p * 1.0
    }
    static func setCompletionBonus(set: Int) -> Double { packPrice(set: set) * 15 }

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
