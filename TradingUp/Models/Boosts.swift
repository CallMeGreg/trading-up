import Foundation

// MARK: - Trainers
//
// A Trainer is the specialist you pick at the start of every Hunt. It gives the
// whole run a strategic identity. You start with just one unlocked (`.digger`)
// and buy the rest permanently with Renown at the Guild. Trainers only carry
// *identity* here — the numeric magnitudes of what they do live in `Economy`, so
// all balance stays in one file.

enum TrainerKind: String, Codable, CaseIterable, Hashable, Identifiable {
    case digger        // +Energy every Lead — more packs to rip
    case grader        // opens each Hunt with a Loupe (grading free)
    case speculator    // first pack each Lead is free (no cash, no Energy)
    case financier     // bigger stake + cheaper Bazaar rerolls
    case curator       // wider draft + a bonus starting Item
    case foilhunter    // +foil chance all Hunt, foils sell for more

    var id: String { rawValue }

    var title: String {
        switch self {
        case .digger:     return "The Digger"
        case .grader:     return "The Grader"
        case .speculator: return "The Speculator"
        case .financier:  return "The Financier"
        case .curator:    return "The Curator"
        case .foilhunter: return "The Foilhunter"
        }
    }

    var blurb: String {
        switch self {
        case .digger:     return "+\(Economy.diggerBonusEnergy) Energy every Lead — rip more packs."
        case .grader:     return "Opens each Hunt with a Loupe: grading is free."
        case .speculator: return "The first pack at each Lead is free — no cash, no Energy."
        case .financier:  return "A bigger stake (+$\(Int(Economy.financierBonusStake))) and cheaper Bazaar rerolls."
        case .curator:    return "Draft from a wider pool, and start with a bonus Item."
        case .foilhunter: return "+\(Int(Economy.foilhunterFoilBonus * 100))% foil all Hunt, and foils sell for more."
        }
    }

    /// The one Trainer every player has from the very first Hunt.
    static let starter: TrainerKind = .digger
}

// MARK: - Items
//
// Items are gear collected during a Hunt: some passive (always-on for the run),
// some one-shot (single use). Bought with cash at the Bazaar or taken free from
// the post-Lead draft. Using an item costs nothing — the only cost is the cash
// you paid. Like Trainers, prices and magnitudes live in `Economy`.

enum ItemKind: String, Codable, CaseIterable, Hashable, Identifiable {
    // Passive (engine)
    case loupe          // grading is free
    case bulkBuyer      // duplicates sell at a better rate
    case gilder         // +foil chance
    case appraiser      // every grade rolls one tier higher
    case whale          // +1 card in every pack
    case evolutionist   // evolution-line bonuses doubled
    case stipend        // +cash per unique owned, paid when you run down a Lead
    // One-shot (burst)
    case holoPress      // turn a chosen card foil
    case fastTrackGrade // grade a card free, guaranteed 8+
    case packSearch     // next pack's hit is guaranteed an ultra
    case marketTip      // instant cash, scaled to the current Lead
    case counterfeit    // add a second copy of a card you own
    case polish         // bump a graded card up two tiers

    var id: String { rawValue }

    var isPassive: Bool {
        switch self {
        case .loupe, .bulkBuyer, .gilder, .appraiser, .whale, .evolutionist, .stipend:
            return true
        case .holoPress, .fastTrackGrade, .packSearch, .marketTip, .counterfeit, .polish:
            return false
        }
    }

    /// One-shot items need a target card the player selects; passives don't.
    var needsTarget: Bool {
        switch self {
        case .holoPress, .fastTrackGrade, .counterfeit, .polish: return true
        default: return false
        }
    }

    var title: String {
        switch self {
        case .loupe:          return "Loupe"
        case .bulkBuyer:      return "Bulk Buyer"
        case .gilder:         return "Gilder"
        case .appraiser:      return "Appraiser"
        case .whale:          return "Whale"
        case .evolutionist:   return "Evolutionist"
        case .stipend:        return "Stipend"
        case .holoPress:      return "Holo Press"
        case .fastTrackGrade: return "Fast-Track Grade"
        case .packSearch:     return "Pack Search"
        case .marketTip:      return "Market Tip"
        case .counterfeit:    return "Counterfeit"
        case .polish:         return "Polish"
        }
    }

    var blurb: String {
        switch self {
        case .loupe:          return "Grading is free."
        case .bulkBuyer:      return "Duplicates sell at \(Int(Economy.bulkBuyerSellback * 100))% (vs \(Int(Economy.sellbackRate * 100))%)."
        case .gilder:         return "+\(Int(Economy.gilderFoilBonus * 100))% foil chance."
        case .appraiser:      return "Every grade rolls one tier higher."
        case .whale:          return "+1 card in every pack (7-card packs)."
        case .evolutionist:   return "Evolution-line bonuses are doubled."
        case .stipend:        return "+$\(Int(Economy.stipendPerUnique)) per unique card, paid when you run down a Lead."
        case .holoPress:      return "Turn a chosen card foil (×\(Int(Economy.foilMultiplier)) value)."
        case .fastTrackGrade: return "Grade a card free — guaranteed 8 or better."
        case .packSearch:     return "Your next pack's hit is guaranteed an ultra."
        case .marketTip:      return "Instant cash, scaled to the current Lead."
        case .counterfeit:    return "Add a second copy of a card you already own."
        case .polish:         return "Bump a graded card up two grade tiers."
        }
    }

    /// Bazaar order: passives first (engine), then one-shots (burst).
    static let bazaarOrder: [ItemKind] = [
        .loupe, .bulkBuyer, .gilder, .appraiser, .whale, .evolutionist, .stipend,
        .holoPress, .fastTrackGrade, .packSearch, .marketTip, .counterfeit, .polish,
    ]
}
