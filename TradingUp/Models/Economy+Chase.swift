import Foundation

// MARK: - The Chase (v2.0) — grail-hunter balance
//
// All Chase tuning lives in this Economy extension (split into its own file so
// the v1 Economy stays compilable on its own). The chase_verify harness owns the
// whole balance surface, exactly like v1. Values are illustrative starting
// points; the harness asserts a real bust rate for weak play and a healthy win
// rate for strong play, and is the source of truth for retuning.
extension Economy {

    // Starting stake per Hunt (up from v1's $100 — varied Asks add early friction,
    // so a slightly bigger cushion keeps Leads 1–2 gentle). Guild-upgradable.
    static let baseStake: Double = 150
    static let stakePerUpgrade: Double = 40

    // Energy — the per-Lead pack-ripping budget (1 Energy + cash per pack).
    static let baseEnergyPerLead = 5
    static let bossEnergyBonus = 1        // boss Leads grant a little extra room
    static let scoreEnergyBonus = 4       // the Score gives room to assemble the Grail

    // The Chase leans on foils as *objectives* (Grails/Asks), so it needs a
    // higher working foil rate than v1's 1% lottery — otherwise a "hold a foil"
    // Grail is unwinnable without luck. This is a Chase-only base (v1's shared
    // `Economy.foilChance` is left at 1%); Gilder/Foilhunter stack on top, and
    // Holo Press is the guaranteed fallback path.
    static let chaseFoilChance = 0.08

    // How high a set a Hunt lets you rip, by Grail tier. Packs get expensive fast
    // ($10 → $400 across sets), so the rip ceiling is tied to the Grail's tier to
    // keep packs affordable against the stake and to stop the generator handing
    // out set-5 Asks in a $120 run. Ascension can raise this later.
    static func grailMaxSet(tier: GrailTier) -> Int {
        switch tier {
        case .easy:   return 1
        case .medium: return 2
        case .hard:   return 3
        }
    }

    // Hunt shape: how many Leads (including the final Score) by Grail tier.
    static func huntLeads(tier: GrailTier) -> Int {
        switch tier {
        case .easy:   return 4
        case .medium: return 5
        case .hard:   return 6
        }
    }

    // Cash Asks scale ~×1.5 per Lead from a low base, comfortably under the stake
    // at Lead 1 so the opener breathes. Non-cash Asks interleave (engine picks).
    static func cashAsk(lead: Int) -> Double {
        let raw = 80.0 * pow(1.5, Double(max(0, lead - 1)))
        return (raw / 10).rounded() * 10
    }

    // Value Ask target (own one card worth ≥ X). Owning a *single* card at a bar
    // is strictly harder than banking the same cash (which aggregates all stock),
    // so this is a gentler, flatter curve than the cash Ask — otherwise "own a
    // card worth $X" dominates the bust rate.
    static func valueAsk(lead: Int) -> Double {
        let raw = 35.0 * pow(1.24, Double(max(0, lead - 1)))
        return max(30, (raw / 5).rounded() * 5)
    }

    // Grail price at the Score, by tier × set × condition. Tuned against the
    // harness: a Hunt banks only a couple hundred dollars of *cash* by the Score
    // (most stock has been liquidated to clear cash Asks), and paying the price
    // is at 100¢ while liquidating stock to raise it loses the sell-back spread —
    // so prices sit near what strong play can actually muster, not the card's
    // fantasy market value. Easy ≈ $110–160, Hard ≈ $600–900.
    static func grailPrice(tier: GrailTier, setId: Int, requireFoil: Bool, gradeMin: Int) -> Double {
        let base: Double = { switch tier { case .easy: return 78; case .medium: return 195; case .hard: return 440 } }()
        let set = 1.0 + 0.12 * Double(max(0, setId - 1))
        let foil = requireFoil ? 1.15 : 1.0
        let grade = 1.0 + 0.03 * Double(max(0, gradeMin))
        let raw = base * set * foil * grade
        return (raw / 10).rounded() * 10
    }

    // Renown — the only lasting spend. Earned per Hunt.
    static let renownPerLead: Double = 3
    static func grailBounty(tier: GrailTier) -> Double {
        switch tier { case .easy: return 8; case .medium: return 16; case .hard: return 30 }
    }
    static func discoveryRenown(_ d: Discovery) -> Double {
        switch d {
        case .masterCollector: return 200
        case .centurion:       return 60
        case .firstGrail:      return 25
        case .setMaster, .deepChase: return 20
        default:               return 10
        }
    }

    // Guild upgrade costs (Renown), per current level.
    static func guildCost(_ u: GuildUpgrade, level: Int) -> Double {
        func at(_ table: [Double]) -> Double { level >= 0 && level < table.count ? table[level] : .infinity }
        switch u {
        case .trainerSlot:  return at([25, 40, 60, 85, 115])
        case .stake:        return at([30, 45, 65, 90, 120])
        case .energy:       return at([25, 40, 60, 85, 115])
        case .bazaarReroll: return at([20, 35, 55])
        case .ascension:    return 150
        }
    }

    /// Trainers unlock in this order via the Guild's Recruit Trainer upgrade.
    /// `.digger` is free from the first Hunt, so it leads the list.
    static let trainerUnlockOrder: [TrainerKind] =
        [.digger, .grader, .speculator, .financier, .curator, .foilhunter]

    // Bazaar
    static let baseRerollCost: Double = 20
    static let rerollDiscountPerLevel: Double = 5
    static let rerollFloor: Double = 5
    static let financierRerollDiscount: Double = 8   // Trainer perk
    static let bazaarSlots = 3

    static func itemPrice(_ k: ItemKind) -> Double {
        switch k {
        case .loupe:          return 55
        case .bulkBuyer:      return 65
        case .gilder:         return 45
        case .appraiser:      return 70
        case .whale:          return 80
        case .stipend:        return 50
        case .holoPress:      return 40
        case .fastTrackGrade: return 35
        case .packSearch:     return 30
        case .marketTip:      return 25
        case .counterfeit:    return 40
        case .polish:         return 45
        }
    }

    /// Market Tip's instant cash, scaled to the current Lead's cash bar.
    static func marketTipPayout(lead: Int) -> Double {
        (cashAsk(lead: lead) * 0.5 / 5).rounded() * 5
    }

    // Item / Trainer effect magnitudes (kept beside the economy they tune).
    static let diggerBonusEnergy = 2
    static let financierBonusStake: Double = 60
    static let foilhunterFoilBonus = 0.05
    static let foilhunterFoilSellBonus = 0.15   // foils sell for more with the Foilhunter
    static let bulkBuyerSellback = 0.90
    static let gilderFoilBonus = 0.05
    static let stipendPerUnique: Double = 2
    static let fastTrackGradeFloor = 8          // guaranteed grade from Fast-Track / boss-safe

    // Draft
    static let draftSize = 3
    static let curatorDraftSize = 4
    static let draftEnergyChunk = 2             // Energy option offered in drafts
}
