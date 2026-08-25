import Foundation

// MARK: - Owned instance

/// A specific owned copy of a card. Two copies of the same card can differ in foil/grade.
struct CardInstance: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    let cardId: String
    var foil: Bool = false
    var grade: Int? = nil    // nil = ungraded

    init(id: UUID = UUID(), cardId: String, foil: Bool = false, grade: Int? = nil) {
        self.id = id
        self.cardId = cardId
        self.foil = foil
        self.grade = grade
    }

    /// Decode leniently, like `Stats` and `GameCore`: synthesized `Codable`
    /// ignores property defaults and throws on any missing key, which would make
    /// adding a per-copy field (serial number, acquired date, …) break every
    /// existing save. Only `cardId` is genuinely required.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cardId = try c.decode(String.self, forKey: .cardId)
        id     = try c.decodeIfPresent(UUID.self, forKey: .id)   ?? UUID()
        foil   = try c.decodeIfPresent(Bool.self, forKey: .foil) ?? false
        grade  = try c.decodeIfPresent(Int.self,  forKey: .grade)
    }

    var card: Card { CardDatabase.byId[cardId] ?? .unknown(id: cardId) }
    var currentValue: Double { Economy.value(base: card.baseValue, foil: foil, grade: grade) }
    /// What the shop actually pays for this copy if sold: market value minus the
    /// sell-back spread. Selling always uses this; `currentValue` stays the market
    /// value shown in the collection and used for net worth / peaks / sorting.
    var sellValue: Double { Economy.sellback(currentValue) }
}

// MARK: - Stats

struct Stats: Codable {
    var packsOpened = 0
    var boxesOpened = 0
    var cardsPulled = 0
    var foilsPulled = 0
    var ultrasPulled = 0
    var cardsSold = 0
    var moneySpent = 0.0
    var moneyEarned = 0.0
    var bestGrade = 0
    var peakCash = Economy.startingCash
    /// All-time highest value of any single card owned (from a pull or a grade bump).
    var peakCardValue = 0.0
    /// All-time largest proceeds from a single card sale.
    var peakSale = 0.0

    init() {}

    /// Decode leniently so saves written before a field existed still load: any
    /// missing key falls back to its default instead of failing the whole decode.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        packsOpened   = try c.decodeIfPresent(Int.self,    forKey: .packsOpened)   ?? 0
        boxesOpened   = try c.decodeIfPresent(Int.self,    forKey: .boxesOpened)   ?? 0
        cardsPulled   = try c.decodeIfPresent(Int.self,    forKey: .cardsPulled)   ?? 0
        foilsPulled   = try c.decodeIfPresent(Int.self,    forKey: .foilsPulled)   ?? 0
        ultrasPulled  = try c.decodeIfPresent(Int.self,    forKey: .ultrasPulled)  ?? 0
        cardsSold     = try c.decodeIfPresent(Int.self,    forKey: .cardsSold)     ?? 0
        moneySpent    = try c.decodeIfPresent(Double.self, forKey: .moneySpent)    ?? 0
        moneyEarned   = try c.decodeIfPresent(Double.self, forKey: .moneyEarned)   ?? 0
        bestGrade     = try c.decodeIfPresent(Int.self,    forKey: .bestGrade)     ?? 0
        peakCash      = try c.decodeIfPresent(Double.self, forKey: .peakCash)      ?? Economy.startingCash
        peakCardValue = try c.decodeIfPresent(Double.self, forKey: .peakCardValue) ?? 0
        peakSale      = try c.decodeIfPresent(Double.self, forKey: .peakSale)      ?? 0
    }
}

// MARK: - Lifetime stats

/// Totals across every *completed* run (won or lost/reset), independent of the
/// current run's `Stats`. Deliberately not a copy of `Stats`: the aggregation
/// rule differs per field (sums, running maxes, or run counters), so it can't
/// just be added on top of the in-progress run's numbers.
///
/// Stored lifetime only ever contains finished runs — the current run is
/// folded in separately, at display time, via `folding(_:won:)`. That keeps
/// the reset path (which permanently commits the just-finished run) and the
/// display path (which previews the in-progress run as if it just finished)
/// sharing one code path, so they can't drift, and it makes the v1 -> v2
/// migration trivial: an existing player's stored lifetime starts at zero,
/// and their in-progress run is added back in the moment it's displayed.
struct LifetimeStats: Codable {
    var runsStarted = 0
    var runsWon = 0
    var packsOpened = 0
    var boxesOpened = 0
    var cardsPulled = 0
    var foilsPulled = 0
    var ultrasPulled = 0
    var cardsSold = 0
    var moneySpent = 0.0
    var moneyEarned = 0.0
    var bestGrade = 0
    var peakCash = Economy.startingCash
    var peakCardValue = 0.0
    var peakSale = 0.0
    /// Fewest packs opened in a *winning* run. `nil` until a run has been won.
    var bestRunPacks: Int? = nil

    init() {}

    /// Decode leniently, like `Stats` and `GameCore`: synthesized `Codable`
    /// ignores property defaults and throws on any missing key. A v1 save has
    /// none of these keys at all, so every field must be optional here.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        runsStarted   = try c.decodeIfPresent(Int.self,    forKey: .runsStarted)   ?? 0
        runsWon       = try c.decodeIfPresent(Int.self,    forKey: .runsWon)       ?? 0
        packsOpened   = try c.decodeIfPresent(Int.self,    forKey: .packsOpened)   ?? 0
        boxesOpened   = try c.decodeIfPresent(Int.self,    forKey: .boxesOpened)   ?? 0
        cardsPulled   = try c.decodeIfPresent(Int.self,    forKey: .cardsPulled)   ?? 0
        foilsPulled   = try c.decodeIfPresent(Int.self,    forKey: .foilsPulled)   ?? 0
        ultrasPulled  = try c.decodeIfPresent(Int.self,    forKey: .ultrasPulled)  ?? 0
        cardsSold     = try c.decodeIfPresent(Int.self,    forKey: .cardsSold)     ?? 0
        moneySpent    = try c.decodeIfPresent(Double.self, forKey: .moneySpent)    ?? 0
        moneyEarned   = try c.decodeIfPresent(Double.self, forKey: .moneyEarned)   ?? 0
        bestGrade     = try c.decodeIfPresent(Int.self,    forKey: .bestGrade)     ?? 0
        peakCash      = try c.decodeIfPresent(Double.self, forKey: .peakCash)      ?? Economy.startingCash
        peakCardValue = try c.decodeIfPresent(Double.self, forKey: .peakCardValue) ?? 0
        peakSale      = try c.decodeIfPresent(Double.self, forKey: .peakSale)      ?? 0
        bestRunPacks  = try c.decodeIfPresent(Int.self,    forKey: .bestRunPacks)
    }

    /// Returns lifetime totals with `run` folded in as one additional run
    /// (won if `won` is true). Used both to preview "all time" totals for
    /// display — folding in the still-in-progress current run — and to
    /// permanently commit a finished run's stats when starting a new game.
    /// Sharing this one function for both means they can never drift apart.
    func folding(_ run: Stats, won: Bool) -> LifetimeStats {
        var out = self
        out.runsStarted += 1
        if won { out.runsWon += 1 }
        out.packsOpened += run.packsOpened
        out.boxesOpened += run.boxesOpened
        out.cardsPulled += run.cardsPulled
        out.foilsPulled += run.foilsPulled
        out.ultrasPulled += run.ultrasPulled
        out.cardsSold += run.cardsSold
        out.moneySpent += run.moneySpent
        out.moneyEarned += run.moneyEarned
        out.bestGrade = max(out.bestGrade, run.bestGrade)
        out.peakCash = max(out.peakCash, run.peakCash)
        out.peakCardValue = max(out.peakCardValue, run.peakCardValue)
        out.peakSale = max(out.peakSale, run.peakSale)
        if won {
            out.bestRunPacks = min(out.bestRunPacks ?? Int.max, run.packsOpened)
        }
        return out
    }
}

// MARK: - Events (transient, for UI)

enum BonusKind { case evolution, set }

struct BonusEvent: Identifiable {
    let id = UUID()
    let kind: BonusKind
    let title: String
    let amount: Double
}

/// A milestone firing for the first time — a permanent unlock. Carried out of a
/// rip/cut so the UI can celebrate it. Kept separate from the cash `BonusEvent`
/// list so a milestone's Renown is never mistaken for cash added to the wallet.
struct MilestoneEvent: Identifiable {
    let id = UUID()
    let milestone: Milestone
    var renown: Int { milestone.renown }
    var title: String { milestone.name }
    var detail: String { milestone.detail }
}

struct OpenResult {
    let pulled: [CardInstance]
    let bonuses: [BonusEvent]
    let isBox: Bool
    /// Cards already owned *before* this pack/box was opened — lets the reveal
    /// screen flag which pulled cards are brand new to the collection.
    var preOwnedIds: Set<String> = []
    /// When set (box packs), restricts duplicate classification to the copies
    /// owned up to and including this pack, so a box opened all at once still
    /// classifies keepers in true pack-by-pack order. `nil` = use all copies.
    var visibleInstanceIds: Set<UUID>? = nil
    /// Milestones unlocked by this pack (usually empty). Surfaced by the run
    /// loop (`ripPack`), never by the primitive `buyPack`.
    var milestones: [MilestoneEvent] = []
}

struct GradeResult {
    let grade: Int
    let fee: Double
    let oldValue: Double
    let newValue: Double
}

// MARK: - Run & meta state

/// Everything about the *current Season* that isn't the collection itself: which
/// Show you're on, the rip budget, Energy, the relics/consumables in play, the
/// active Twist, and the between-Show shopping state. Reset at the start of each
/// Season. Decodes leniently (every key optional) so it can grow additively and
/// old saves — which have no `run` at all — default cleanly.
struct RunState: Codable, Hashable {
    /// False on a bare/legacy core until a Season is set up around it.
    var active = false
    var show = 1
    var ripsRemaining = 0
    var usedFreePackThisShow = false
    var energy = 0
    var maxEnergy = Economy.baseMaxEnergy
    /// Trainers are unique holdings; Power-Ups may repeat. Both are stored as
    /// catalog id references, so a boost leaving the catalogue later is dropped
    /// on load instead of breaking the save (mirrors how card ids are handled).
    var trainerIds: [String] = []
    var powerUpIds: [String] = []
    var twistId: String? = nil
    var guaranteedUltraNextPack = false
    /// Between-Show shopping is open (draft + Bazaar), i.e. not inside a Show.
    var atBazaar = false
    var draftIds: [String] = []
    var bazaarIds: [String] = []
    var rerolls = 0
    /// Set when a Show is failed — the Season is over pending the summary.
    var seasonEnded = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        active                 = try c.decodeIfPresent(Bool.self,     forKey: .active)                 ?? false
        show                   = try c.decodeIfPresent(Int.self,      forKey: .show)                   ?? 1
        ripsRemaining          = try c.decodeIfPresent(Int.self,      forKey: .ripsRemaining)          ?? 0
        usedFreePackThisShow   = try c.decodeIfPresent(Bool.self,     forKey: .usedFreePackThisShow)   ?? false
        energy                 = try c.decodeIfPresent(Int.self,      forKey: .energy)                 ?? 0
        maxEnergy              = try c.decodeIfPresent(Int.self,      forKey: .maxEnergy)              ?? Economy.baseMaxEnergy
        trainerIds             = try c.decodeIfPresent([String].self, forKey: .trainerIds)             ?? []
        powerUpIds             = try c.decodeIfPresent([String].self, forKey: .powerUpIds)             ?? []
        twistId                = try c.decodeIfPresent(String.self,   forKey: .twistId)
        guaranteedUltraNextPack = try c.decodeIfPresent(Bool.self,    forKey: .guaranteedUltraNextPack) ?? false
        atBazaar               = try c.decodeIfPresent(Bool.self,     forKey: .atBazaar)               ?? false
        draftIds               = try c.decodeIfPresent([String].self, forKey: .draftIds)               ?? []
        bazaarIds              = try c.decodeIfPresent([String].self, forKey: .bazaarIds)              ?? []
        rerolls                = try c.decodeIfPresent(Int.self,      forKey: .rerolls)                ?? 0
        seasonEnded            = try c.decodeIfPresent(Bool.self,     forKey: .seasonEnded)            ?? false
    }
}

/// Permanent progress that outlives any Season: the Renown bank, the milestones
/// unlocked once and for all, and the Guild upgrade ladders bought with Renown.
/// Preserved across `startingNewSeason()`. Decodes leniently like everything else.
struct MetaState: Codable, Hashable {
    var renown = 0
    var milestones: Set<String> = []
    var stakeLevel = 0
    var trainerSlotLevel = 0
    var ripLevel = 0
    var energyLevel = 0

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        renown           = try c.decodeIfPresent(Int.self,         forKey: .renown)           ?? 0
        milestones       = try c.decodeIfPresent(Set<String>.self, forKey: .milestones)       ?? []
        stakeLevel       = try c.decodeIfPresent(Int.self,         forKey: .stakeLevel)       ?? 0
        trainerSlotLevel = try c.decodeIfPresent(Int.self,         forKey: .trainerSlotLevel) ?? 0
        ripLevel         = try c.decodeIfPresent(Int.self,         forKey: .ripLevel)         ?? 0
        energyLevel      = try c.decodeIfPresent(Int.self,         forKey: .energyLevel)      ?? 0
    }

    var trainerSlots: Int { Economy.baseTrainerSlots + trainerSlotLevel }

    func has(_ m: Milestone) -> Bool { milestones.contains(m.rawValue) }

    func guildLevel(_ u: GuildUpgrade) -> Int {
        switch u {
        case .stake:       return stakeLevel
        case .trainerSlot: return trainerSlotLevel
        case .rip:         return ripLevel
        case .energy:      return energyLevel
        }
    }

    mutating func bumpGuild(_ u: GuildUpgrade) {
        switch u {
        case .stake:       stakeLevel += 1
        case .trainerSlot: trainerSlotLevel += 1
        case .rip:         ripLevel += 1
        case .energy:      energyLevel += 1
        }
    }
}

// MARK: - Pack construction config

/// How a single pack is built. The default reproduces the classic pack exactly,
/// so `buildPack(set:using:)` — used by the harness, the EV checks and every
/// existing test — is untouched. Trainers/Power-Ups feed a modified config
/// through `packConfig(set:)` for the run loop only.
struct PackConfig: Hashable {
    var commons = Economy.commonsPerPack
    var uncommons = Economy.uncommonsPerPack
    var extraHits = 0
    var foilChance = Economy.foilChance
    var forceUltraHit = false
    static let standard = PackConfig()
}

// MARK: - Game core (pure, deterministic, Foundation-only)

struct GameCore: Codable {
    var cash: Double = Economy.startingCash
    var instances: [CardInstance] = []
    var claimedEvoLines: Set<String> = []
    var claimedSets: Set<Int> = []
    var stats = Stats()
    /// Totals across *completed* runs only — the current run's `Stats` are
    /// folded in separately at display time. See `LifetimeStats`.
    var lifetime = LifetimeStats()
    var hasWon = false
    /// Set once the player dismisses the win screen to keep browsing their
    /// finished collection. `hasWon` stays true forever; this only controls
    /// whether the celebration overlay is still being presented.
    var winAcknowledged = false
    var welcomeSeen = false
    /// The current Season (Shows, rips, Energy, relics, Twist). See `RunState`.
    var run = RunState()
    /// Permanent cross-Season progress (Renown, milestones, Guild). See `MetaState`.
    var meta = MetaState()

    init() {}

    /// Decode leniently, like `Stats`: Swift's synthesized `init(from:)` ignores
    /// property defaults and throws on any missing key, so adding a field here
    /// would make every existing save fail to decode. Decoding each key
    /// independently means new fields fall back to their default and old saves
    /// keep loading.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cash            = try c.decodeIfPresent(Double.self,         forKey: .cash)            ?? Economy.startingCash
        instances       = try c.decodeIfPresent([CardInstance].self, forKey: .instances)       ?? []
        claimedEvoLines = try c.decodeIfPresent(Set<String>.self,    forKey: .claimedEvoLines) ?? []
        claimedSets     = try c.decodeIfPresent(Set<Int>.self,       forKey: .claimedSets)     ?? []
        stats           = try c.decodeIfPresent(Stats.self,          forKey: .stats)           ?? Stats()
        lifetime        = try c.decodeIfPresent(LifetimeStats.self,  forKey: .lifetime)        ?? LifetimeStats()
        hasWon          = try c.decodeIfPresent(Bool.self,           forKey: .hasWon)          ?? false
        winAcknowledged = try c.decodeIfPresent(Bool.self,           forKey: .winAcknowledged) ?? false
        welcomeSeen     = try c.decodeIfPresent(Bool.self,           forKey: .welcomeSeen)     ?? false
        run             = try c.decodeIfPresent(RunState.self,       forKey: .run)             ?? RunState()
        meta            = try c.decodeIfPresent(MetaState.self,      forKey: .meta)            ?? MetaState()
    }

    // MARK: Resetting

    /// A fresh Season that keeps the collection's lifetime record *and* all
    /// permanent meta-progress (Renown, milestones, Guild upgrades). The Season
    /// that's ending is folded into `lifetime` first (won if this one was the
    /// Championship), then the binder, cash and per-run `stats` start over,
    /// re-stocked with the player's Guild-upgraded starting stake and a fresh
    /// Show 1. Pure and unit-testable in isolation from `GameState`/persistence.
    func startingNewRun() -> GameCore {
        var fresh = GameCore()
        fresh.lifetime = lifetime.folding(stats, won: hasWon)
        fresh.meta = meta
        fresh.welcomeSeen = welcomeSeen   // the intro is a once-ever thing, not per-Season
        fresh.cash = Economy.startingStake(stakeLevel: meta.stakeLevel)
        fresh.activateShowOne()
        return fresh
    }

    /// Reads better at call sites than `startingNewRun()` now that a "run" is a
    /// Season on the Circuit.
    func startingNewSeason() -> GameCore { startingNewRun() }

    /// Set up a brand-new Season around a freshly-reset core: activate the run,
    /// stock Energy from the Guild, and drop the player into Show 1 (no Twist,
    /// full rips). The collection/cash are assumed already prepared by the caller.
    private mutating func activateShowOne() {
        run = RunState()
        run.active = true
        run.show = 1
        run.maxEnergy = Economy.baseMaxEnergy + meta.energyLevel
        run.energy = min(run.maxEnergy, Economy.startingEnergy + meta.energyLevel)
        enterShow(twistId: nil)
    }

    /// Give a legacy or bare core an active Season *without* disturbing the
    /// collection or cash it already has — the migration path for v1/v2 saves,
    /// which drop their in-progress binder straight into Show 1 of the Circuit.
    mutating func ensureActiveRun() {
        guard !run.active else { return }
        run = RunState()
        run.active = true
        run.show = 1
        run.maxEnergy = Economy.baseMaxEnergy + meta.energyLevel
        run.energy = min(run.maxEnergy, Economy.startingEnergy + meta.energyLevel)
        enterShow(twistId: nil)
    }

    /// "All time" totals for display: the permanently-recorded `lifetime`
    /// (completed runs only) plus this still-in-progress run, previewed as if
    /// it ended right now. Never persisted — recomputed on read so it can
    /// never double-count against `startingNewRun()`.
    var lifetimeIncludingCurrentRun: LifetimeStats { lifetime.folding(stats, won: hasWon) }

    // MARK: Load hygiene

    /// A copy of this state with any card ids that are no longer in the shipped
    /// catalogue removed — so a save written against an older card list (renamed,
    /// renumbered, or retired cards) loads as a slightly smaller collection
    /// instead of showing placeholder cards. Returns the cleaned state and how
    /// many copies were dropped.
    func sanitized() -> (core: GameCore, droppedInstances: Int) {
        var out = self
        let kept = instances.filter { CardDatabase.exists($0.cardId) }
        let dropped = instances.count - kept.count
        guard dropped > 0 else { return (out, 0) }
        out.instances = kept
        // Re-open bonuses whose line/set the player no longer completes, so the
        // reward isn't permanently stranded if they re-collect the cards.
        let owned = Set(kept.map { $0.cardId })
        out.claimedEvoLines = out.claimedEvoLines.filter { lineId in
            CardDatabase.evolutionLines[lineId]?.allSatisfy { owned.contains($0.id) } ?? false
        }
        out.claimedSets = out.claimedSets.filter { set in
            let cards = CardDatabase.cards(inSet: set)
            return !cards.isEmpty && cards.allSatisfy { owned.contains($0.id) }
        }
        return (out, dropped)
    }

    // MARK: Derived

    var uniqueOwnedIds: Set<String> { Set(instances.map { $0.cardId }) }
    var uniqueCount: Int { uniqueOwnedIds.count }

    func count(of cardId: String) -> Int { instances.reduce(0) { $0 + ($1.cardId == cardId ? 1 : 0) } }
    func owns(_ cardId: String) -> Bool { instances.contains { $0.cardId == cardId } }

    /// A copy is sellable only if it is not the last remaining copy of that card.
    func isSellable(_ inst: CardInstance) -> Bool { count(of: inst.cardId) > 1 }
    var sellableInstances: [CardInstance] { instances.filter { isSellable($0) } }

    /// Every copy the player could actually part with — all but one of each
    /// card. Unlike `sellableInstances` (which flags *both* copies of a pair as
    /// sellable, since either one may go) this is the set that can be sold
    /// *together*, so it's what any "how much is left to raise" sum has to use.
    /// The cheapest copy of each card is the one left behind, because that's
    /// the choice that maximises what the rest are worth.
    var sellableExtras: [CardInstance] {
        Dictionary(grouping: instances, by: { $0.cardId }).values.flatMap { copies in
            copies.count > 1
                ? Array(copies.sorted { $0.currentValue < $1.currentValue }.dropFirst())
                : []
        }
    }

    /// The most cash this position could ever be turned into: every duplicate
    /// sold at the shop's buylist price, grading the ones first where even the
    /// fee-inclusive best case (`Economy.luckiestGrade`) beats selling them
    /// raw. Extras are liquidated cheapest-first so those early sales can
    /// bankroll the grading fees on the pricier ones.
    ///
    /// Deliberately optimistic: it exists to decide when a run is *provably*
    /// unrecoverable, so it must never miss a way back to a pack.
    var maxRaisableCash: Double {
        var pool = cash
        for inst in sellableExtras.sorted(by: { sellPrice(of: $0) < sellPrice(of: $1) }) {
            let fee = gradingIsFree ? 0 : Economy.gradeFee(set: inst.card.set)
            let luckiestSale = effectiveSellback(
                Economy.value(base: inst.card.baseValue, foil: inst.foil, grade: Economy.luckiestGrade)
            )
            let raw = sellPrice(of: inst)
            let worthGrading = inst.card.rarity.canBeGraded && inst.grade == nil
                && pool >= fee && luckiestSale - fee > raw
            pool += worthGrading ? luckiestSale - fee : raw
        }
        return pool
    }

    func instances(of cardId: String) -> [CardInstance] { instances.filter { $0.cardId == cardId } }

    var collectionValue: Double { instances.reduce(0) { $0 + $1.currentValue } }
    var netWorth: Double { cash + collectionValue }

    // MARK: Trainer / Twist effects (folded in at the point each applies)

    /// The Trainers currently in play, resolved from their catalog ids.
    var activeTrainers: [Trainer] { run.trainerIds.compactMap { BoostCatalog.trainer($0) } }
    /// The Power-Ups the player is holding, resolved from their catalog ids.
    var heldPowerUps: [PowerUp] { run.powerUpIds.compactMap { BoostCatalog.powerUp($0) } }
    /// The Twist in force this Show, if any.
    var activeTwist: Twist? { run.twistId.flatMap { BoostCatalog.twist($0) } }

    /// The shop's buylist rate after Trainers (Bulk Buyer) and any Twist (Cold
    /// Snap), clamped so it can never exceed near-parity. Base is `Economy`'s 75%.
    var effectiveSellbackRate: Double {
        let bonus = activeTrainers.reduce(0.0) { $0 + $1.sellbackBonus }
        let twist = activeTwist?.sellbackDelta ?? 0
        return min(0.98, max(0.30, Economy.sellbackRate + bonus + twist))
    }
    func effectiveSellback(_ value: Double) -> Double { value * effectiveSellbackRate }
    /// What a copy actually fetches now, with Trainer/Twist effects applied.
    func sellPrice(of inst: CardInstance) -> Double { effectiveSellback(inst.currentValue) }

    /// Per-card foil probability after Gilder (+) and Counterfeit Scare (off).
    var effectiveFoilChance: Double {
        if activeTwist?.foilsDisabled == true { return 0 }
        return min(0.9, Economy.foilChance + activeTrainers.reduce(0.0) { $0 + $1.bonusFoilChance })
    }
    var gradingIsFree: Bool { activeTrainers.contains { $0.gradingFree } }
    var gradeBump: Int { activeTrainers.reduce(0) { $0 + $1.gradeBump } }
    var evoBonusMultiplier: Double { activeTrainers.map { $0.evoBonusMultiplier }.max() ?? 1.0 }
    var bonusPackCards: Int { activeTrainers.reduce(0) { $0 + $1.bonusPackCards } }
    var trainerRipBonus: Int { activeTrainers.reduce(0) { $0 + $1.bonusRips } }
    var hasTrainerSlotFree: Bool { run.trainerIds.count < meta.trainerSlots }

    /// Speculator's free first pack, still unused this Show.
    var firstPackFreeAvailable: Bool {
        !run.usedFreePackThisShow && activeTrainers.contains { $0.firstPackFree }
    }

    // MARK: The Circuit (Show / Quota / Cut / Bust)

    /// The net-worth bar for the current Show, after any Twist multiplier.
    var currentQuota: Double { Economy.quota(show: run.show) * (activeTwist?.quotaMultiplier ?? 1.0) }
    /// Progress toward the current Show's bar, 0...1.
    var quotaProgress: Double { currentQuota > 0 ? min(1, netWorth / currentQuota) : 1 }
    /// Whether holdings have reached the bar, so the player may Make the Cut.
    var canMakeCut: Bool { run.active && !hasWon && !run.seasonEnded && !run.atBazaar && netWorth >= currentQuota }
    /// Final Show of a Season — clearing it wins the Championship.
    var isChampionshipShow: Bool { run.show >= Economy.seasonShows }

    func ownedCount(inSet set: Int) -> Int {
        let ids = uniqueOwnedIds
        return CardDatabase.cards(inSet: set).reduce(0) { $0 + (ids.contains($1.id) ? 1 : 0) }
    }

    /// A set is playable only once enough *unique* cards have been collected.
    /// Set 1 is always unlocked; later sets gate on Economy.uniquesToUnlock(set:).
    func isUnlocked(set: Int) -> Bool { uniqueCount >= Economy.uniquesToUnlock(set: set) }

    /// A Season busts when the current Show can no longer be cleared: holdings
    /// are below the bar and there's no move left that could lift them there —
    /// no rip left you can afford, no ungraded card you can send in, no Power-Up
    /// to play. Grading and pulls both *add value* (that's how you beat the bar),
    /// so as long as one is reachable the Show is still alive.
    ///
    /// Deliberately generous about what counts as a move: it decides when to end
    /// a Season, so it must never call one lost while a real climb remains.
    var isBust: Bool {
        guard run.active, !hasWon, !run.seasonEnded, !run.atBazaar else { return false }
        if netWorth >= currentQuota { return false }
        // A pull still to come (a rip you can pay for, or a free first pack).
        let canRip = firstPackFreeAvailable
            || (run.ripsRemaining > 0 && maxRaisableCash >= Economy.cheapestPackPrice)
        if canRip { return false }
        // A grade still to roll (adds expected value without a pull).
        let canGrade = instances.contains { inst in
            inst.card.rarity.canBeGraded && inst.grade == nil
                && (gradingIsFree || cash >= Economy.gradeFee(set: inst.card.set))
        }
        if canGrade { return false }
        // A Power-Up still to play (several lift net worth on their own).
        if run.energy > 0 && !run.powerUpIds.isEmpty { return false }
        return true
    }

    /// Retained name for the presentation layer: a busted Season is the Circuit's
    /// "game over" for the current climb (the run summary, not a terminal state —
    /// the player spends Renown and starts a new Season).
    var isGameOver: Bool { isBust }

    // MARK: Welcome / onboarding

    var hasSeenWelcome: Bool { welcomeSeen }

    /// Show the intro only on a brand-new game (fresh, no progress yet) that
    /// hasn't been dismissed — so it appears on first launch and after New Game,
    /// but never interrupts an in-progress collection.
    var shouldShowWelcome: Bool { !hasSeenWelcome && instances.isEmpty && stats.packsOpened == 0 }

    mutating func markWelcomeSeen() { welcomeSeen = true }

    // MARK: Win presentation

    /// The win overlay is shown once per completed collection. After the player
    /// dismisses it they keep their finished collection and can browse freely —
    /// winning shouldn't force a reset to see the cards you just collected.
    var shouldShowWin: Bool { hasWon && !winAcknowledged }

    mutating func acknowledgeWin() { winAcknowledged = true }

    // MARK: Pack building

    /// The classic pack, unchanged: three commons, two uncommons, one rare-or-
    /// ultra hit, ~1% foils. Kept as the canonical entry point used by the EV
    /// harness and every test, so their numbers never move. The run loop calls
    /// the `config:` overload instead to fold in Trainer/Power-Up effects.
    func buildPack<G: RandomNumberGenerator>(set: Int, using rng: inout G) -> [CardInstance] {
        buildPack(set: set, config: .standard, using: &rng)
    }

    func buildPack<G: RandomNumberGenerator>(set: Int, config: PackConfig, using rng: inout G) -> [CardInstance] {
        let pool = CardDatabase.cards(inSet: set)
        let commons = pool.filter { $0.rarity == .common }
        let uncommons = pool.filter { $0.rarity == .uncommon }
        let rares = pool.filter { $0.rarity == .rare }
        let ultras = pool.filter { $0.rarity == .ultra }

        var out: [CardInstance] = []
        out += commons.shuffled(using: &rng).prefix(config.commons).map { CardInstance(cardId: $0.id) }
        out += uncommons.shuffled(using: &rng).prefix(config.uncommons).map { CardInstance(cardId: $0.id) }

        // One base hit plus any extra hit-slots (Whale). A Pack Search forces the
        // first hit to an ultra; the rest roll normally.
        let hitCount = 1 + max(0, config.extraHits)
        for h in 0..<hitCount {
            let forceUltra = config.forceUltraHit && h == 0
            let isUltra = forceUltra || Double.random(in: 0..<1, using: &rng) < Economy.ultraHitChance
            let hitPool = isUltra ? ultras : rares
            if let hit = hitPool.randomElement(using: &rng) {
                out.append(CardInstance(cardId: hit.id))
            }
        }

        for i in out.indices where Double.random(in: 0..<1, using: &rng) < config.foilChance {
            out[i].foil = true
        }
        return out
    }

    /// The pack recipe for the current run, folding in Trainer effects and a
    /// pending Pack Search.
    func packConfig(set: Int) -> PackConfig {
        PackConfig(commons: Economy.commonsPerPack,
                   uncommons: Economy.uncommonsPerPack,
                   extraHits: bonusPackCards,
                   foilChance: effectiveFoilChance,
                   forceUltraHit: run.guaranteedUltraNextPack)
    }

    // MARK: Buying

    mutating func buyPack<G: RandomNumberGenerator>(set: Int, using rng: inout G) -> OpenResult? {
        guard isUnlocked(set: set) else { return nil }
        let price = Economy.packPrice(set: set)
        guard cash >= price else { return nil }
        cash -= price
        stats.moneySpent += price
        stats.packsOpened += 1
        let preOwned = uniqueOwnedIds
        let pack = buildPack(set: set, using: &rng)
        ingest(pack)
        let bonuses = checkBonuses()
        return OpenResult(pulled: pack, bonuses: bonuses, isBox: false, preOwnedIds: preOwned)
    }

    /// Build every pack in a booster box, applying the box-wide ultra/foil
    /// guarantees across all of them, then splitting back into per-pack groups.
    /// Pure construction: touches neither cash, stats, nor the collection.
    func buildBoxPacks<G: RandomNumberGenerator>(set: Int, using rng: inout G) -> [[CardInstance]] {
        var pulled: [CardInstance] = []
        for _ in 0..<Economy.boxPacks { pulled += buildPack(set: set, using: &rng) }

        // Guarantee ultras (upgrade rare hits if short).
        let ultras = CardDatabase.cards(inSet: set).filter { $0.rarity == .ultra }
        func ultraCount() -> Int { pulled.filter { CardDatabase.byId[$0.cardId]?.rarity == .ultra }.count }
        while ultraCount() < Economy.boxGuaranteeUltras {
            let rareIdx = pulled.indices.filter { CardDatabase.byId[pulled[$0].cardId]?.rarity == .rare }
            guard let i = rareIdx.randomElement(using: &rng), let u = ultras.randomElement(using: &rng) else { break }
            pulled[i] = CardInstance(cardId: u.id, foil: pulled[i].foil)
        }

        // Guarantee foils.
        while pulled.filter({ $0.foil }).count < Economy.boxGuaranteeFoils {
            let plainIdx = pulled.indices.filter { !pulled[$0].foil }
            guard let i = plainIdx.randomElement(using: &rng) else { break }
            pulled[i].foil = true
        }

        // Guarantees replaced cards in place, so grouping by pack size is preserved.
        return stride(from: 0, to: pulled.count, by: Economy.packSize).map {
            Array(pulled[$0..<min($0 + Economy.packSize, pulled.count)])
        }
    }

    mutating func buyBox<G: RandomNumberGenerator>(set: Int, using rng: inout G) -> OpenResult? {
        guard isUnlocked(set: set) else { return nil }
        let price = Economy.boxPrice(set: set)
        guard cash >= price else { return nil }
        cash -= price
        stats.moneySpent += price
        stats.boxesOpened += 1
        stats.packsOpened += Economy.boxPacks
        let preOwned = uniqueOwnedIds
        let pulled = buildBoxPacks(set: set, using: &rng).flatMap { $0 }
        ingest(pulled)
        let bonuses = checkBonuses()
        return OpenResult(pulled: pulled, bonuses: bonuses, isBox: true, preOwnedIds: preOwned)
    }

    /// Open a booster box as a sequence of packs. All cards are added to the
    /// collection immediately (so nothing is lost if the reveal is interrupted),
    /// but each returned pack carries a snapshot of the copies visible "so far"
    /// so the reveal can classify duplicates in true pack-by-pack order.
    mutating func buyBoxPacks<G: RandomNumberGenerator>(set: Int, using rng: inout G) -> [OpenResult]? {
        guard isUnlocked(set: set) else { return nil }
        let price = Economy.boxPrice(set: set)
        guard cash >= price else { return nil }
        cash -= price
        stats.moneySpent += price
        stats.boxesOpened += 1

        let packs = buildBoxPacks(set: set, using: &rng)
        var results: [OpenResult] = []
        var visible = Set(instances.map { $0.id })   // copies owned before the box
        for pack in packs {
            let preOwned = uniqueOwnedIds
            stats.packsOpened += 1
            ingest(pack)
            visible.formUnion(pack.map { $0.id })
            let bonuses = checkBonuses()
            results.append(OpenResult(pulled: pack, bonuses: bonuses, isBox: false,
                                      preOwnedIds: preOwned, visibleInstanceIds: visible))
        }
        return results
    }

    private mutating func ingest(_ newInstances: [CardInstance]) {
        instances += newInstances
        stats.cardsPulled += newInstances.count
        stats.foilsPulled += newInstances.filter { $0.foil }.count
        stats.ultrasPulled += newInstances.filter { CardDatabase.byId[$0.cardId]?.rarity == .ultra }.count
        if let best = newInstances.map({ $0.currentValue }).max() {
            stats.peakCardValue = max(stats.peakCardValue, best)
        }
        updatePeak()
    }

    // MARK: Selling

    @discardableResult
    mutating func sell(instanceId: UUID) -> Double? {
        guard let idx = instances.firstIndex(where: { $0.id == instanceId }) else { return nil }
        let inst = instances[idx]
        guard isSellable(inst) else { return nil }
        let v = sellPrice(of: inst)
        instances.remove(at: idx)
        cash += v
        stats.moneyEarned += v
        stats.cardsSold += 1
        stats.peakSale = max(stats.peakSale, v)
        updatePeak()
        return v
    }

    /// Non-mutating preview: how many duplicate copies exist across the given
    /// cards (every copy except the single most valuable one of each) and what
    /// they would sell for. Used to label the "Sell duplicates" action.
    func duplicateSummary(of cardIds: Set<String>) -> (count: Int, proceeds: Double) {
        var count = 0
        var proceeds = 0.0
        for cardId in cardIds {
            let copies = instances(of: cardId).sorted { $0.currentValue > $1.currentValue }
            guard copies.count > 1 else { continue }
            for extra in copies.dropFirst() {   // keep copies[0] (best), the rest are extras
                count += 1
                proceeds += sellPrice(of: extra)
            }
        }
        return (count, proceeds)
    }

    /// Sells every duplicate copy across the given cards, always keeping the
    /// single most valuable copy of each (so the collection is never reduced
    /// below one of a card). Returns the number sold and total proceeds.
    @discardableResult
    mutating func sellDuplicates(of cardIds: Set<String>) -> (count: Int, proceeds: Double) {
        var count = 0
        var proceeds = 0.0
        for cardId in cardIds {
            let copies = instances(of: cardId).sorted { $0.currentValue > $1.currentValue }
            guard copies.count > 1 else { continue }
            for extra in copies.dropFirst() {   // reuses sell(): keeps last-copy protection + stats
                if let v = sell(instanceId: extra.id) {
                    count += 1
                    proceeds += v
                }
            }
        }
        return (count, proceeds)
    }

    // MARK: Grading

    mutating func grade<G: RandomNumberGenerator>(instanceId: UUID, using rng: inout G) -> GradeResult? {
        guard let idx = instances.firstIndex(where: { $0.id == instanceId }) else { return nil }
        let inst = instances[idx]
        guard inst.card.rarity.canBeGraded, inst.grade == nil else { return nil }
        let fee = gradingIsFree ? 0 : Economy.gradeFee(set: inst.card.set)
        guard cash >= fee else { return nil }
        let oldValue = inst.currentValue
        cash -= fee
        stats.moneySpent += fee
        var g = Economy.rollGrade(using: &rng)
        // Appraiser nudges the grade up, but never touches a rolled PSA 1 — that's
        // the 10× "authentic oddity", so bumping it would *lower* the value.
        if gradeBump > 0, g >= 2 { g = min(10, g + gradeBump) }
        instances[idx].grade = g
        stats.bestGrade = max(stats.bestGrade, g)
        stats.peakCardValue = max(stats.peakCardValue, instances[idx].currentValue)
        updatePeak()
        return GradeResult(grade: g, fee: fee, oldValue: oldValue, newValue: instances[idx].currentValue)
    }

    // MARK: Bonuses
    //
    // Only evolution-line completion pays cash now — the run's key non-sale
    // faucet. Completing a whole *set* no longer pays (that's the `setMaster`
    // milestone), and owning all 250 no longer "wins" (that's `masterCollector`;
    // the Season is won at the Championship instead). `claimedSets` is still
    // tracked so a set is only ever counted once, for the milestone.

    mutating func checkBonuses() -> [BonusEvent] {
        var events: [BonusEvent] = []
        let owned = uniqueOwnedIds

        for (lineId, cards) in CardDatabase.evolutionLines where !claimedEvoLines.contains(lineId) {
            if cards.allSatisfy({ owned.contains($0.id) }) {
                claimedEvoLines.insert(lineId)
                let amount = Economy.evolutionBonus(set: cards[0].set, stageCount: cards[0].stageCount) * evoBonusMultiplier
                cash += amount
                stats.moneyEarned += amount
                let names = cards.map { $0.name }.joined(separator: " → ")
                events.append(BonusEvent(kind: .evolution, title: "Evolution complete: \(names)", amount: amount))
            }
        }

        // Record set completion (no cash) so `setMaster` can fire exactly once.
        for set in 1...CardDatabase.setCount where !claimedSets.contains(set) {
            let setCards = CardDatabase.cards(inSet: set)
            if !setCards.isEmpty && setCards.allSatisfy({ owned.contains($0.id) }) {
                claimedSets.insert(set)
            }
        }

        updatePeak()
        return events
    }

    // MARK: - The Circuit: run loop

    /// Begin a Show: set (or clear) its Twist, refill the rip budget and Energy,
    /// and leave the Bazaar. Twist effects on rips/energy are read here, so the
    /// Twist is assigned before those are computed.
    mutating func enterShow(twistId: String?) {
        run.twistId = twistId
        run.atBazaar = false
        run.seasonEnded = false
        run.usedFreePackThisShow = false
        run.guaranteedUltraNextPack = false
        run.draftIds = []
        run.bazaarIds = []
        run.rerolls = 0

        let ripBonus = meta.ripLevel + trainerRipBonus
        let base = Economy.ripsPerShow(bonus: ripBonus)
        run.ripsRemaining = max(1, base + (activeTwist?.ripDelta ?? 0))

        // Energy refills to a fresh per-Show amount (never carried, never stacked
        // past the ceiling), so spending it inside a Show is a real trade-off.
        let refill = Economy.startingEnergy + meta.energyLevel
            + activeTrainers.reduce(0) { $0 + $1.energyPerShow }
        run.energy = min(run.maxEnergy, refill)
    }

    /// Open a pack *within a Show*: consumes a rip (or the Speculator's free
    /// first pack, which costs neither cash nor a rip), applies Trainer/Twist
    /// pack effects, and surfaces any milestones the pull unlocked. Distinct
    /// from the primitive `buyPack`, which stays effect-free for tests/EV.
    mutating func ripPack<G: RandomNumberGenerator>(set: Int, using rng: inout G) -> OpenResult? {
        guard run.active, !run.atBazaar, !run.seasonEnded, !hasWon else { return nil }
        guard isUnlocked(set: set) else { return nil }

        let free = firstPackFreeAvailable
        let price = free ? 0 : Economy.packPrice(set: set)
        if free {
            run.usedFreePackThisShow = true
        } else {
            guard run.ripsRemaining > 0, cash >= price else { return nil }
            run.ripsRemaining -= 1
        }
        cash -= price
        stats.moneySpent += price
        stats.packsOpened += 1

        let preOwned = uniqueOwnedIds
        let config = packConfig(set: set)
        let pack = buildPack(set: set, config: config, using: &rng)
        run.guaranteedUltraNextPack = false   // a Pack Search only primes one pack
        ingest(pack)
        let bonuses = checkBonuses()
        let milestones = refreshMilestones()
        return OpenResult(pulled: pack, bonuses: bonuses, isBox: false,
                          preOwnedIds: preOwned, milestones: milestones)
    }

    /// Clear the current Show once holdings have reached the bar. Pays Renown
    /// (plus the Patron's per-unique cash), then either advances to the Bazaar
    /// before the next Show or, at the Championship, wins the Season. Returns any
    /// milestones that fired (First Cut, Deep Run, Season Champion, …).
    @discardableResult
    mutating func makeCut() -> [MilestoneEvent] {
        guard canMakeCut else { return [] }

        let patron = activeTrainers.reduce(0.0) { $0 + $1.cashPerUniqueOnCut }
        if patron > 0 {
            let payout = patron * Double(uniqueCount)
            cash += payout
            stats.moneyEarned += payout
            updatePeak()
        }

        meta.renown += Economy.renownPerShowCleared

        if isChampionshipShow {
            hasWon = true
            meta.renown += Economy.renownChampionBonus
        } else {
            run.show += 1
            run.atBazaar = true     // GameState stocks the draft + Bazaar (it owns rng)
        }
        return refreshMilestones()
    }

    /// Take the free draft pick between Shows (one of `run.draftIds`). Clears the
    /// remaining choices so only one is ever taken.
    @discardableResult
    mutating func takeDraft(_ id: String) -> Bool {
        guard run.atBazaar, run.draftIds.contains(id) else { return false }
        guard acquire(id, free: true) else { return false }
        run.draftIds = []
        return true
    }

    /// Buy a stocked Bazaar offer at its listed price. Removes it from the shelf
    /// on success so it can't be bought twice.
    @discardableResult
    mutating func buyFromBazaar(_ id: String) -> Bool {
        guard run.atBazaar, let slot = run.bazaarIds.firstIndex(of: id) else { return false }
        guard acquire(id, free: false) else { return false }
        run.bazaarIds.remove(at: slot)
        return true
    }

    /// Apply an acquired boost: seat a Trainer (unique, slot-limited), pocket a
    /// Power-Up (stacks), or bank an Energy card immediately. Charges cash unless
    /// `free` (the draft). Pure w.r.t. rng.
    @discardableResult
    mutating func acquire(_ id: String, free: Bool) -> Bool {
        guard let boost = BoostCatalog.boost(id) else { return false }
        let price = free ? 0 : boost.cost
        guard cash >= price else { return false }
        switch boost {
        case .trainer(let t):
            guard hasTrainerSlotFree, !run.trainerIds.contains(t.id) else { return false }
            run.trainerIds.append(t.id)
        case .powerUp(let p):
            run.powerUpIds.append(p.id)
        case .energy(let e):
            run.maxEnergy += e.maxBonus
            run.energy = min(run.maxEnergy, run.energy + e.energy)
        }
        cash -= price
        stats.moneySpent += price
        return true
    }

    /// Restock the Bazaar for a rising Renown-free cash fee. Draft is untouched.
    @discardableResult
    mutating func rerollBazaar<G: RandomNumberGenerator>(using rng: inout G) -> Bool {
        guard run.atBazaar else { return false }
        let fee = Economy.rerollCost(rerolls: run.rerolls)
        guard cash >= fee else { return false }
        cash -= fee
        stats.moneySpent += fee
        run.rerolls += 1
        rollBazaar(using: &rng)
        return true
    }

    /// Stock the between-Show draft (free pick of `Economy.draftChoices`).
    mutating func rollDraft<G: RandomNumberGenerator>(using rng: inout G) {
        run.draftIds = offerIds(count: Economy.draftChoices, using: &rng)
    }

    /// Stock the Bazaar shelf (paid, `Economy.bazaarSlots` slots).
    mutating func rollBazaar<G: RandomNumberGenerator>(using rng: inout G) {
        run.bazaarIds = offerIds(count: Economy.bazaarSlots, using: &rng)
    }

    private func offerIds<G: RandomNumberGenerator>(count: Int, using rng: inout G) -> [String] {
        let pool = BoostCatalog.availablePool(unlocked: meta.milestones,
                                              ownedTrainerIds: Set(run.trainerIds))
        return Array(pool.map { $0.id }.shuffled(using: &rng).prefix(count))
    }

    /// Play a held Power-Up, spending its Energy. `target` is required for the
    /// card-targeting effects (see `PowerUp.needsTarget`). Returns whether it fired.
    @discardableResult
    mutating func playPowerUp<G: RandomNumberGenerator>(_ powerUpId: String, target: UUID?, using rng: inout G) -> Bool {
        guard run.active, !run.atBazaar else { return false }
        guard let slot = run.powerUpIds.firstIndex(of: powerUpId),
              let pu = BoostCatalog.powerUp(powerUpId), run.energy >= pu.energyCost else { return false }

        func targetIndex() -> Int? { target.flatMap { t in instances.firstIndex { $0.id == t } } }

        switch pu.effect {
        case .holoPress:
            guard let i = targetIndex(), !instances[i].foil else { return false }
            instances[i].foil = true
        case .fastTrackGrade:
            guard let i = targetIndex(), instances[i].card.rarity.canBeGraded, instances[i].grade == nil else { return false }
            var g = Economy.rollGrade(using: &rng)
            if g < 8 { g = 8 }                     // "guaranteed PSA 8+"
            instances[i].grade = g
            stats.bestGrade = max(stats.bestGrade, g)
        case .packSearch:
            run.guaranteedUltraNextPack = true
        case .marketTip:
            let amount = Economy.marketTipCash(show: run.show)
            cash += amount
            stats.moneyEarned += amount
        case .counterfeit:
            guard let i = targetIndex() else { return false }
            instances.append(CardInstance(cardId: instances[i].cardId))
            stats.cardsPulled += 1
        case .polish:
            guard let i = targetIndex(), let g = instances[i].grade, g >= 2 else { return false }
            instances[i].grade = min(10, g + 2)
        }

        run.energy -= pu.energyCost
        run.powerUpIds.remove(at: slot)
        stats.peakCardValue = max(stats.peakCardValue, instances.map { $0.currentValue }.max() ?? 0)
        updatePeak()
        return true
    }

    // MARK: - The Collectors' Guild (permanent, Renown-bought)

    func canBuyGuild(_ u: GuildUpgrade) -> Bool {
        meta.guildLevel(u) < Economy.guildMaxLevel(u)
            && meta.renown >= Economy.guildCost(u, currentLevel: meta.guildLevel(u))
    }

    @discardableResult
    mutating func buyGuildUpgrade(_ u: GuildUpgrade) -> Bool {
        guard canBuyGuild(u) else { return false }
        meta.renown -= Economy.guildCost(u, currentLevel: meta.guildLevel(u))
        meta.bumpGuild(u)
        return true
    }

    // MARK: - Milestones

    /// Bank any newly-satisfied milestones (once ever each) and their Renown.
    /// Called after every value-changing run action; returns the ones that fired
    /// so the UI can celebrate them.
    @discardableResult
    mutating func refreshMilestones() -> [MilestoneEvent] {
        var fired: [MilestoneEvent] = []
        for m in Milestone.allCases where !meta.milestones.contains(m.rawValue) {
            guard satisfies(m) else { continue }
            meta.milestones.insert(m.rawValue)
            meta.renown += m.renown
            fired.append(MilestoneEvent(milestone: m))
        }
        return fired
    }

    /// Whether a milestone's condition currently holds. State-based wherever
    /// possible so it reads naturally and unit-tests directly.
    func satisfies(_ m: Milestone) -> Bool {
        switch m {
        case .firstCut:
            return hasWon || run.show >= 2          // cleared at least one Show
        case .setMaster:
            return !claimedSets.isEmpty             // a full set completed this run
        case .hoarder:
            return maxCopiesOfAnyCard >= 8
        case .gemHolo:
            return instances.contains { $0.foil && $0.grade == 10 }
        case .aceGrader:
            return instances.reduce(0) { $0 + (($1.grade ?? 0) >= 9 ? 1 : 0) } >= 3
        case .deepRun:
            return run.show >= 5
        case .seasonChampion:
            return hasWon
        case .ultraHunter:
            return lifetimeIncludingCurrentRun.ultrasPulled >= 10
        case .centurion:
            return uniqueCount >= 100
        case .masterCollector:
            return uniqueCount >= CardDatabase.all.count
        }
    }

    var maxCopiesOfAnyCard: Int {
        Dictionary(grouping: instances, by: { $0.cardId }).values.map { $0.count }.max() ?? 0
    }

    private mutating func updatePeak() { stats.peakCash = max(stats.peakCash, cash) }
}
