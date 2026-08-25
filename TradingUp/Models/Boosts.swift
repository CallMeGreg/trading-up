import Foundation

// MARK: - Boost kinds
//
// The three run-scoped, non-collectible card types the Circuit adds on top of
// the Sprytes. None of these are ever pulled from a pack, none count toward the
// 250-card collection, and none persist past the Season — they exist only to
// shape the current run. All balance for them lives here and in `Economy`.

enum BoostKind: String, Codable, Hashable, CaseIterable {
    case trainer, powerUp, energy

    var display: String {
        switch self {
        case .trainer: return "Trainer"
        case .powerUp: return "Power-Up"
        case .energy:  return "Energy"
        }
    }

    var symbol: String {
        switch self {
        case .trainer: return "person.text.rectangle.fill"
        case .powerUp: return "bolt.fill"
        case .energy:  return "battery.100.bolt"
        }
    }
}

// MARK: - Trainers (passive relics)

/// A Trainer is a passive relic that stays active for the whole Season. The
/// player holds a limited number (`Economy.baseTrainerSlots` plus Guild
/// upgrades). Effects are plain data — a set of modifiers `GameCore` folds in at
/// the point each applies — so they stack into builds and stay trivially
/// testable with no behaviour buried in a closure.
struct Trainer: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let blurb: String
    let cost: Double
    /// Milestone id that must be unlocked before this Trainer appears in pools.
    /// `nil` = always available.
    var requires: String? = nil

    // Modifiers (all default to "no effect").
    var gradingFree = false            // Loupe: grading costs no fee
    var sellbackBonus = 0.0            // Bulk Buyer: added to the 0.75 buylist rate
    var bonusRips = 0                  // Hot Hands: extra pack-opens each Show
    var bonusFoilChance = 0.0          // Gilder: added foil probability per card
    var gradeBump = 0                  // Appraiser: every grade rolls this many tiers higher
    var bonusPackCards = 0             // Whale: extra hit-slot cards per pack
    var evoBonusMultiplier = 1.0       // Evolutionist: scales evolution-line cash
    var firstPackFree = false          // Speculator: first pack each Show is free (no cash, no rip)
    var cashPerUniqueOnCut = 0.0       // Patron: cash per unique card owned, paid on Make the Cut
    var energyPerShow = 0              // Dynamo: Energy granted at the start of each Show
}

// MARK: - Power-Ups (active consumables)

enum PowerUpEffect: String, Codable, Hashable {
    case holoPress        // turn a chosen card foil
    case fastTrackGrade   // grade a chosen card free, guaranteed PSA 8+
    case packSearch       // next pack's hit is guaranteed an ultra
    case marketTip        // instant cash, scaled to the current Show
    case counterfeit      // add a second copy of a chosen card
    case polish           // bump a chosen graded card up two tiers
}

/// A single-use consumable played by spending Energy. Some need a target card
/// (`needsTarget`), others fire immediately. Copies can stack in a run.
struct PowerUp: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let blurb: String
    let cost: Double
    let energyCost: Int
    let effect: PowerUpEffect
    var requires: String? = nil

    /// Whether playing it requires the player to pick a card copy to act on.
    var needsTarget: Bool {
        switch effect {
        case .holoPress, .fastTrackGrade, .counterfeit, .polish: return true
        case .packSearch, .marketTip: return false
        }
    }
}

// MARK: - Energy cards

/// Grants Energy — either a one-off top-up (`energy`) or a permanent lift to the
/// run's Energy ceiling (`maxBonus`), or both. Applied the instant it's acquired.
struct EnergyCard: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let blurb: String
    let cost: Double
    let energy: Int
    let maxBonus: Int
    var requires: String? = nil
}

// MARK: - Unified boost card (for drafts / the Bazaar)

/// A single offer in a draft or the Bazaar. Encodes to a compact tagged form and
/// is only ever *referenced by id* from a save (see `RunState`), so a boost
/// leaving the catalogue later degrades gracefully instead of breaking saves.
enum BoostCard: Codable, Hashable, Identifiable {
    case trainer(Trainer)
    case powerUp(PowerUp)
    case energy(EnergyCard)

    var id: String {
        switch self {
        case .trainer(let t): return t.id
        case .powerUp(let p): return p.id
        case .energy(let e):  return e.id
        }
    }

    var kind: BoostKind {
        switch self {
        case .trainer: return .trainer
        case .powerUp: return .powerUp
        case .energy:  return .energy
        }
    }

    var name: String {
        switch self {
        case .trainer(let t): return t.name
        case .powerUp(let p): return p.name
        case .energy(let e):  return e.name
        }
    }

    var blurb: String {
        switch self {
        case .trainer(let t): return t.blurb
        case .powerUp(let p): return p.blurb
        case .energy(let e):  return e.blurb
        }
    }

    var cost: Double {
        switch self {
        case .trainer(let t): return t.cost
        case .powerUp(let p): return p.cost
        case .energy(let e):  return e.cost
        }
    }

    var requires: String? {
        switch self {
        case .trainer(let t): return t.requires
        case .powerUp(let p): return p.requires
        case .energy(let e):  return e.requires
        }
    }
}

// MARK: - Twists (per-Show modifiers)

/// A per-Show rule change that forces the player to adapt. Kept as plain data so
/// the model applies it and the harness can reason about it; only a couple are
/// wired into the UI in this release, the rest are staged.
struct Twist: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let blurb: String
    var sellbackDelta = 0.0      // Cold Snap: temporary buylist penalty
    var foilsDisabled = false    // Counterfeits: no foils pull this Show
    var ripDelta = 0             // Rush: fewer rips
    var quotaMultiplier = 1.0    // Bull Market / Rush: bar re-scaled
}

// MARK: - Guild upgrades (permanent, Renown-bought)

enum GuildUpgrade: String, Codable, Hashable, CaseIterable, Identifiable {
    case stake, trainerSlot, rip, energy
    var id: String { rawValue }

    var name: String {
        switch self {
        case .stake:       return "Bigger Stake"
        case .trainerSlot: return "Trainer Slot"
        case .rip:         return "Extra Rip"
        case .energy:      return "Energy Cell"
        }
    }

    var blurb: String {
        switch self {
        case .stake:       return "Start every Season with more cash."
        case .trainerSlot: return "Hold one more Trainer at a time."
        case .rip:         return "One more pack-open every Show."
        case .energy:      return "More starting and maximum Energy."
        }
    }
}

// MARK: - Milestones (one-time permanent unlocks)

/// A once-ever achievement. Firing it banks Renown and can unlock new content
/// (Trainers/Power-Ups gated behind its id via `requires`). Conditions are
/// evaluated against the live `GameCore`, so they read naturally and are covered
/// directly by unit tests.
enum Milestone: String, Codable, Hashable, CaseIterable, Identifiable {
    case firstCut, setMaster, hoarder, gemHolo, aceGrader
    case deepRun, seasonChampion, ultraHunter, centurion, masterCollector
    var id: String { rawValue }

    var name: String {
        switch self {
        case .firstCut:        return "First Cut"
        case .setMaster:       return "Set Master"
        case .hoarder:         return "Hoarder"
        case .gemHolo:         return "Gem Holo"
        case .aceGrader:       return "Ace Grader"
        case .deepRun:         return "Deep Run"
        case .seasonChampion:  return "Season Champion"
        case .ultraHunter:     return "Ultra Hunter"
        case .centurion:       return "Centurion"
        case .masterCollector: return "Master Collector"
        }
    }

    var detail: String {
        switch self {
        case .firstCut:        return "Make the Cut at your first Show."
        case .setMaster:       return "Complete a full 50-card set in one run."
        case .hoarder:         return "Hold 8 copies of a single card."
        case .gemHolo:         return "Own a foil graded PSA 10."
        case .aceGrader:       return "Grade three cards PSA 9 or better in one run."
        case .deepRun:         return "Reach Show 5 in a single Season."
        case .seasonChampion:  return "Win a Season at the Masters Invitational."
        case .ultraHunter:     return "Pull 10 ultra rares (all-time)."
        case .centurion:       return "Own 100 unique cards at once."
        case .masterCollector: return "Own all 250 cards at once."
        }
    }

    /// Renown paid the first (and only) time this fires.
    var renown: Int {
        switch self {
        case .firstCut:        return 1
        case .setMaster:       return 5
        case .hoarder:         return 3
        case .gemHolo:         return 4
        case .aceGrader:       return 3
        case .deepRun:         return 4
        case .seasonChampion:  return 8
        case .ultraHunter:     return 3
        case .centurion:       return 5
        case .masterCollector: return 20
        }
    }
}

// MARK: - Catalog

/// The curated content pool. Everything the draft and Bazaar can ever offer is
/// defined here, once, and referenced by id elsewhere. Deliberately hand-tuned
/// and modest in size for this release; new entries slot in without touching the
/// run/save machinery.
enum BoostCatalog {
    static let trainers: [Trainer] = [
        Trainer(id: "loupe", name: "Jeweler's Loupe",
                blurb: "Grading is free.", cost: 90, gradingFree: true),
        Trainer(id: "bulk-buyer", name: "Bulk Buyer",
                blurb: "The shop buys your dupes at 90%.", cost: 110, sellbackBonus: 0.15),
        Trainer(id: "hot-hands", name: "Hot Hands",
                blurb: "+2 rips every Show.", cost: 120, bonusRips: 2),
        Trainer(id: "gilder", name: "Gilder",
                blurb: "+5% foil chance on every card.", cost: 100,
                requires: Milestone.gemHolo.rawValue, bonusFoilChance: 0.05),
        Trainer(id: "appraiser", name: "Appraiser",
                blurb: "Every grade rolls one tier higher.", cost: 130,
                requires: Milestone.aceGrader.rawValue, gradeBump: 1),
        Trainer(id: "whale", name: "The Whale",
                blurb: "Every pack holds one extra hit.", cost: 150,
                requires: Milestone.hoarder.rawValue, bonusPackCards: 1),
        Trainer(id: "evolutionist", name: "Evolutionist",
                blurb: "Evolution-line bonuses are doubled.", cost: 120, evoBonusMultiplier: 2.0),
        Trainer(id: "speculator", name: "Speculator",
                blurb: "Your first pack each Show is free.", cost: 140, firstPackFree: true),
        Trainer(id: "patron", name: "Patron of the Set",
                blurb: "+$2 per unique card when you Make the Cut.", cost: 110,
                requires: Milestone.setMaster.rawValue, cashPerUniqueOnCut: 2),
        Trainer(id: "dynamo", name: "Dynamo",
                blurb: "+1 Energy at the start of each Show.", cost: 100, energyPerShow: 1),
    ]

    static let powerUps: [PowerUp] = [
        PowerUp(id: "holo-press", name: "Holo Press",
                blurb: "Turn a card foil (×3 value).", cost: 40, energyCost: 2, effect: .holoPress),
        PowerUp(id: "fast-track", name: "Fast-Track Grade",
                blurb: "Grade a card free — guaranteed PSA 8+.", cost: 45, energyCost: 2, effect: .fastTrackGrade),
        PowerUp(id: "pack-search", name: "Pack Search",
                blurb: "Your next pack's hit is a guaranteed ultra.", cost: 35, energyCost: 1, effect: .packSearch,
                requires: Milestone.ultraHunter.rawValue),
        PowerUp(id: "market-tip", name: "Market Tip",
                blurb: "Instant cash, scaled to the Show.", cost: 25, energyCost: 1, effect: .marketTip),
        PowerUp(id: "counterfeit", name: "Counterfeit",
                blurb: "Add a second copy of a card you own.", cost: 50, energyCost: 3, effect: .counterfeit,
                requires: Milestone.hoarder.rawValue),
        PowerUp(id: "polish", name: "Polish",
                blurb: "Bump a graded card up two tiers.", cost: 30, energyCost: 1, effect: .polish),
    ]

    static let energyCards: [EnergyCard] = [
        EnergyCard(id: "energy-cell", name: "Energy Cell",
                   blurb: "+2 Energy now.", cost: 30, energy: 2, maxBonus: 0),
        EnergyCard(id: "capacitor", name: "Capacitor",
                   blurb: "+1 Energy now and +2 max Energy.", cost: 45, energy: 1, maxBonus: 2),
    ]

    static let twists: [Twist] = [
        Twist(id: "cold-snap", name: "Cold Snap",
              blurb: "The shop pays 15% less for dupes this Show.", sellbackDelta: -0.15),
        Twist(id: "counterfeits", name: "Counterfeit Scare",
              blurb: "No foils are pulled this Show.", foilsDisabled: true),
        Twist(id: "rush", name: "Rush Hour",
              blurb: "Two fewer rips, but the bar drops 15%.", ripDelta: -2, quotaMultiplier: 0.85),
        Twist(id: "bull-market", name: "Bull Market",
              blurb: "Packs run hot — but the bar climbs 20%.", quotaMultiplier: 1.20),
    ]

    // Lookups.
    static let trainerById: [String: Trainer] = Dictionary(uniqueKeysWithValues: trainers.map { ($0.id, $0) })
    static let powerUpById: [String: PowerUp] = Dictionary(uniqueKeysWithValues: powerUps.map { ($0.id, $0) })
    static let energyById: [String: EnergyCard] = Dictionary(uniqueKeysWithValues: energyCards.map { ($0.id, $0) })
    static let twistById: [String: Twist] = Dictionary(uniqueKeysWithValues: twists.map { ($0.id, $0) })

    static func trainer(_ id: String) -> Trainer? { trainerById[id] }
    static func powerUp(_ id: String) -> PowerUp? { powerUpById[id] }
    static func energyCard(_ id: String) -> EnergyCard? { energyById[id] }
    static func twist(_ id: String) -> Twist? { twistById[id] }

    /// Resolve any catalog id (across all three kinds) to a unified boost.
    static func boost(_ id: String) -> BoostCard? {
        if let t = trainerById[id] { return .trainer(t) }
        if let p = powerUpById[id] { return .powerUp(p) }
        if let e = energyById[id]  { return .energy(e) }
        return nil
    }

    /// The full offerable pool given a set of unlocked milestones, minus any
    /// unique Trainers the player already holds. Power-Ups and Energy can repeat,
    /// so they stay in the pool regardless.
    static func availablePool(unlocked: Set<String>, ownedTrainerIds: Set<String>) -> [BoostCard] {
        func ok(_ req: String?) -> Bool { req == nil || unlocked.contains(req!) }
        var pool: [BoostCard] = []
        pool += trainers.filter { ok($0.requires) && !ownedTrainerIds.contains($0.id) }.map { .trainer($0) }
        pool += powerUps.filter { ok($0.requires) }.map { .powerUp($0) }
        pool += energyCards.filter { ok($0.requires) }.map { .energy($0) }
        return pool
    }
}
