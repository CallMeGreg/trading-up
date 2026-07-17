import Foundation

/// All economic tuning lives here. Values scale per set (index = set - 1).
enum Economy {

    static let startingCash: Double = 100
    static let packSize = 6

    // Per-set pricing (set 1...5)
    static let packPrices: [Double] = [10, 20, 40, 70, 120]
    static let gradeFees:  [Double] = [2, 4, 8, 14, 24]

    static func packPrice(set: Int) -> Double { packPrices[clampIndex(set)] }
    static func gradeFee(set: Int) -> Double { gradeFees[clampIndex(set)] }

    /// The lowest pack price in the game — the least cash needed to buy any pack.
    /// Falling below this with no sellable cards ends the game.
    static var cheapestPackPrice: Double { packPrices.min() ?? 0 }

    // Booster box
    static let boxPacks = 12
    static let boxGuaranteeUltras = 3
    static let boxGuaranteeFoils = 2
    static func boxPrice(set: Int) -> Double { packPrice(set: set) * 10 }

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
    static func setCompletionBonus(set: Int) -> Double { packPrice(set: set) * 50 }

    // MARK: Grading table (grade, odds %, value multiplier)
    static let gradeTable: [(grade: Int, odds: Int, mult: Double)] = [
        (1, 1, 10.0), (2, 2, 0.10), (3, 3, 0.25), (4, 4, 0.40), (5, 5, 0.55),
        (6, 10, 0.70), (7, 15, 0.85), (8, 35, 1.00), (9, 15, 2.00), (10, 10, 5.00),
    ]

    static func gradeMultiplier(_ grade: Int) -> Double {
        gradeTable.first { $0.grade == grade }?.mult ?? 1.0
    }

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
