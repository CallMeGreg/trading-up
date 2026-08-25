import Foundation

// MARK: - Binder — the permanent, read-only collection
//
// One slot per Spryte (all 250). When a Hunt ends (win OR bust) the best copy of
// each card you held is deposited if it beats the copy already there. "Best" is
// by *quality* (a foil PSA 10 is the aspirational top), so a slot is never done
// at first ownership — you keep chasing a foil, then a 9, then a Gem-Mint 10.

struct BinderCopy: Codable, Hashable {
    var foil: Bool = false
    var grade: Int? = nil

    init(foil: Bool = false, grade: Int? = nil) { self.foil = foil; self.grade = grade }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        foil  = try c.decodeIfPresent(Bool.self, forKey: .foil) ?? false
        grade = try c.decodeIfPresent(Int.self,  forKey: .grade)
    }

    /// Aspirational quality on [0,1]: owning a copy is 0.20, a foil adds 0.35,
    /// grade scales the last 0.45 (PSA 10 = full). A raw copy is 0.20; a foil
    /// Gem-Mint 10 is 1.0. This defines Binder "completion" and the deposit rule.
    static func quality(foil: Bool, grade: Int?) -> Double {
        var q = 0.20
        if foil { q += 0.35 }
        if let g = grade { q += 0.45 * (Double(max(0, min(g, 10))) / 10.0) }
        return q
    }

    var quality: Double { BinderCopy.quality(foil: foil, grade: grade) }
}

// MARK: - Discoveries — one-time achievements that unlock content

enum Discovery: String, Codable, CaseIterable, Hashable, Identifiable {
    case firstLead, firstGrail, setMaster, hoarder, gemHolo
    case aceGrader, deepChase, ultraHunter, centurion, masterCollector

    var id: String { rawValue }

    var title: String {
        switch self {
        case .firstLead:       return "First Lead"
        case .firstGrail:      return "First Grail"
        case .setMaster:       return "Set Master"
        case .hoarder:         return "Hoarder"
        case .gemHolo:         return "Gem Holo"
        case .aceGrader:       return "Ace Grader"
        case .deepChase:       return "Deep Chase"
        case .ultraHunter:     return "Ultra Hunter"
        case .centurion:       return "Centurion"
        case .masterCollector: return "Master Collector"
        }
    }

    var blurb: String {
        switch self {
        case .firstLead:       return "Run down your first Lead."
        case .firstGrail:      return "Land your first Grail."
        case .setMaster:       return "Own a full 50-card set during a Hunt."
        case .hoarder:         return "Hold 8 copies of one card."
        case .gemHolo:         return "Own a foil graded 10."
        case .aceGrader:       return "Grade 3 cards to 9+ in a single Hunt."
        case .deepChase:       return "Reach the Score on a Set-4+ Grail."
        case .ultraHunter:     return "Pull 10 ultras (lifetime)."
        case .centurion:       return "Reach 100 unique cards in the Binder."
        case .masterCollector: return "Collect all 250 cards in the Binder."
        }
    }

    /// A few Trainers are *earned* here, a second unlock path beside the Guild.
    var unlocksTrainer: TrainerKind? {
        switch self {
        case .firstGrail: return .grader
        case .deepChase:  return .foilhunter
        case .centurion:  return .curator
        default:          return nil
        }
    }
}

// MARK: - Guild upgrades — permanent, Renown-bought

enum GuildUpgrade: String, Codable, CaseIterable, Hashable, Identifiable {
    case trainerSlot   // unlock the next Trainer option
    case stake         // +starting cash each Hunt
    case energy        // +1 base Energy each Lead
    case bazaarReroll  // cheaper Bazaar rerolls
    case ascension     // unlock harder Hunts (staged)

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trainerSlot:  return "Recruit Trainer"
        case .stake:        return "Fatten the Stake"
        case .energy:       return "Deeper Reserves"
        case .bazaarReroll: return "Bazaar Contacts"
        case .ascension:    return "Ascension"
        }
    }

    var blurb: String {
        switch self {
        case .trainerSlot:  return "Permanently unlock another Trainer to pick from."
        case .stake:        return "+$\(Int(Economy.stakePerUpgrade)) starting cash every Hunt."
        case .energy:       return "+1 base Energy at every Lead."
        case .bazaarReroll: return "Bazaar rerolls get cheaper."
        case .ascension:    return "Unlock escalating difficulty tiers (staged)."
        }
    }

    var maxLevel: Int {
        switch self {
        case .trainerSlot:  return max(0, Economy.trainerUnlockOrder.count - 1) // digger is free
        case .stake:        return 5
        case .energy:       return 5
        case .bazaarReroll: return 3
        case .ascension:    return 1
        }
    }
}

struct GrailRecord: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var headline: String
    var tier: GrailTier

    init(id: UUID = UUID(), headline: String, tier: GrailTier) {
        self.id = id; self.headline = headline; self.tier = tier
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id       = try c.decodeIfPresent(UUID.self,      forKey: .id) ?? UUID()
        headline = try c.decodeIfPresent(String.self,    forKey: .headline) ?? ""
        tier     = try c.decodeIfPresent(GrailTier.self, forKey: .tier) ?? .easy
    }
}

// MARK: - Lifetime stats (all-time, across every Hunt)

struct ChaseLifetime: Codable, Hashable {
    var huntsStarted = 0
    var huntsWon = 0
    var leadsRunDown = 0
    var renownEarned = 0.0
    var packsRipped = 0
    var cardsGraded = 0
    var ultrasPulled = 0
    var bestBinderUnique = 0

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        huntsStarted     = try c.decodeIfPresent(Int.self,    forKey: .huntsStarted) ?? 0
        huntsWon         = try c.decodeIfPresent(Int.self,    forKey: .huntsWon) ?? 0
        leadsRunDown     = try c.decodeIfPresent(Int.self,    forKey: .leadsRunDown) ?? 0
        renownEarned     = try c.decodeIfPresent(Double.self, forKey: .renownEarned) ?? 0
        packsRipped      = try c.decodeIfPresent(Int.self,    forKey: .packsRipped) ?? 0
        cardsGraded      = try c.decodeIfPresent(Int.self,    forKey: .cardsGraded) ?? 0
        ultrasPulled     = try c.decodeIfPresent(Int.self,    forKey: .ultrasPulled) ?? 0
        bestBinderUnique = try c.decodeIfPresent(Int.self,    forKey: .bestBinderUnique) ?? 0
    }
}

// MARK: - MetaState — everything that persists across Hunts

struct MetaState: Codable {
    var renown: Double = 0
    var binder: [String: BinderCopy] = [:]
    var unlockedTrainers: Set<TrainerKind> = [TrainerKind.starter]
    var discoveries: Set<Discovery> = []
    var upgrades: [String: Int] = [:]           // GuildUpgrade.rawValue -> level
    var grailsLanded: [GrailRecord] = []
    var lifetime = ChaseLifetime()
    /// The app major version whose "What's New" the player has seen. Lets a
    /// future major show its own explainer once, like 2.0's reset screen.
    var lastSeenMajorVersion = 0

    init() {}

    /// Lenient decode: every key optional so additive fields never break a save.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        renown           = try c.decodeIfPresent(Double.self, forKey: .renown) ?? 0
        binder           = try c.decodeIfPresent([String: BinderCopy].self, forKey: .binder) ?? [:]
        let trainers     = try c.decodeIfPresent(Set<TrainerKind>.self, forKey: .unlockedTrainers) ?? []
        unlockedTrainers = trainers.union([TrainerKind.starter])   // starter always available
        discoveries      = try c.decodeIfPresent(Set<Discovery>.self, forKey: .discoveries) ?? []
        upgrades         = try c.decodeIfPresent([String: Int].self, forKey: .upgrades) ?? [:]
        grailsLanded     = try c.decodeIfPresent([GrailRecord].self, forKey: .grailsLanded) ?? []
        lifetime         = try c.decodeIfPresent(ChaseLifetime.self, forKey: .lifetime) ?? ChaseLifetime()
        lastSeenMajorVersion = try c.decodeIfPresent(Int.self, forKey: .lastSeenMajorVersion) ?? 0
    }

    // MARK: Binder

    var binderUnique: Int { binder.count }

    /// Blended completion on [0,1]: half for how many of the 250 are owned, half
    /// for their average quality. All 250 raw ≈ 60%; all 250 Gem-Mint foil = 100%.
    var binderCompletion: Double {
        let total = Double(CardDatabase.all.count)
        guard total > 0 else { return 0 }
        let ownership = Double(binder.count) / total
        let quality = binder.values.reduce(0.0) { $0 + $1.quality } / total
        return 0.5 * ownership + 0.5 * quality
    }

    /// Deposit a copy if it beats the slot's current best (by quality).
    @discardableResult
    mutating func deposit(_ inst: CardInstance) -> Bool {
        guard CardDatabase.exists(inst.cardId) else { return false }
        let incoming = BinderCopy(foil: inst.foil, grade: inst.grade)
        if let existing = binder[inst.cardId], existing.quality >= incoming.quality { return false }
        binder[inst.cardId] = incoming
        return true
    }

    // MARK: Trainers & upgrades

    func isTrainerUnlocked(_ t: TrainerKind) -> Bool { unlockedTrainers.contains(t) }
    var availableTrainers: [TrainerKind] {
        TrainerKind.allCases.filter { unlockedTrainers.contains($0) }
    }

    @discardableResult
    mutating func unlockTrainer(_ t: TrainerKind) -> Bool {
        unlockedTrainers.insert(t).inserted
    }

    /// The next Trainer a `trainerSlot` purchase would unlock, in catalog order.
    var nextTrainerToUnlock: TrainerKind? {
        Economy.trainerUnlockOrder.first { !unlockedTrainers.contains($0) }
    }

    func level(_ u: GuildUpgrade) -> Int { upgrades[u.rawValue] ?? 0 }
    func canUpgrade(_ u: GuildUpgrade) -> Bool {
        // Trainers can also be unlocked by Discoveries, so the Recruit-Trainer
        // upgrade's availability tracks the actual unlocked set — not a separate
        // purchase counter that could drift and offer a slot with no Trainer left.
        if u == .trainerSlot { return nextTrainerToUnlock != nil }
        return level(u) < u.maxLevel
    }
    func upgradeCost(_ u: GuildUpgrade) -> Double? {
        guard canUpgrade(u) else { return nil }
        // Price the next Trainer by how many are already unlocked (bought or
        // earned), so a Discovery-gifted Trainer advances the cost tier too.
        let tier = u == .trainerSlot ? max(0, unlockedTrainers.count - 1) : level(u)
        return Economy.guildCost(u, level: tier)
    }

    /// Buy one level of a Guild upgrade with Renown. `trainerSlot` also unlocks
    /// the next Trainer. Returns whether the purchase happened.
    @discardableResult
    mutating func purchase(_ u: GuildUpgrade) -> Bool {
        guard let cost = upgradeCost(u), renown >= cost else { return false }
        if u == .trainerSlot {
            guard let next = nextTrainerToUnlock else { return false }
            unlockTrainer(next)
        }
        renown -= cost
        upgrades[u.rawValue, default: 0] += 1
        return true
    }

    // MARK: Derived run inputs (meta-progression felt at Hunt start)

    /// Starting cash for a Hunt = base stake + Guild stake levels.
    var stake: Double { Economy.baseStake + Double(level(.stake)) * Economy.stakePerUpgrade }

    /// Base Energy each Lead before Trainer/Complication adjustments.
    var baseEnergyPerLead: Int { Economy.baseEnergyPerLead + level(.energy) }

    /// Bazaar reroll cost after Guild discounts (Trainer discount applied later).
    var baseRerollCost: Double {
        max(Economy.rerollFloor, Economy.baseRerollCost - Double(level(.bazaarReroll)) * Economy.rerollDiscountPerLevel)
    }
}
