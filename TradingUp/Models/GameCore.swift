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
}

struct GradeResult {
    let grade: Int
    let fee: Double
    let oldValue: Double
    let newValue: Double
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
    }

    // MARK: Resetting

    /// A fresh run that keeps the collection's lifetime record: the run that's
    /// ending is folded into `lifetime` first (as won or lost, whichever
    /// `hasWon` says), then everything else — cash, collection, current-run
    /// `stats` — starts over. Pure and unit-testable in isolation from
    /// `GameState`/persistence.
    func startingNewRun() -> GameCore {
        var fresh = GameCore()
        fresh.lifetime = lifetime.folding(stats, won: hasWon)
        return fresh
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

    func instances(of cardId: String) -> [CardInstance] { instances.filter { $0.cardId == cardId } }

    var collectionValue: Double { instances.reduce(0) { $0 + $1.currentValue } }
    var netWorth: Double { cash + collectionValue }

    func ownedCount(inSet set: Int) -> Int {
        let ids = uniqueOwnedIds
        return CardDatabase.cards(inSet: set).reduce(0) { $0 + (ids.contains($1.id) ? 1 : 0) }
    }

    /// A set is playable only once enough *unique* cards have been collected.
    /// Set 1 is always unlocked; later sets gate on Economy.uniquesToUnlock(set:).
    func isUnlocked(set: Int) -> Bool { uniqueCount >= Economy.uniquesToUnlock(set: set) }

    var isGameOver: Bool {
        guard !hasWon else { return false }
        return cash < Economy.cheapestPackPrice && sellableInstances.isEmpty
    }

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

    func buildPack<G: RandomNumberGenerator>(set: Int, using rng: inout G) -> [CardInstance] {
        let pool = CardDatabase.cards(inSet: set)
        let commons = pool.filter { $0.rarity == .common }
        let uncommons = pool.filter { $0.rarity == .uncommon }
        let rares = pool.filter { $0.rarity == .rare }
        let ultras = pool.filter { $0.rarity == .ultra }

        var out: [CardInstance] = []
        out += commons.shuffled(using: &rng).prefix(Economy.commonsPerPack).map { CardInstance(cardId: $0.id) }
        out += uncommons.shuffled(using: &rng).prefix(Economy.uncommonsPerPack).map { CardInstance(cardId: $0.id) }

        let hitIsUltra = Double.random(in: 0..<1, using: &rng) < Economy.ultraHitChance
        let hitPool = hitIsUltra ? ultras : rares
        if let hit = hitPool.randomElement(using: &rng) {
            out.append(CardInstance(cardId: hit.id))
        }

        for i in out.indices where Double.random(in: 0..<1, using: &rng) < Economy.foilChance {
            out[i].foil = true
        }
        return out
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
        let v = inst.sellValue
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
                proceeds += extra.sellValue
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
        let fee = Economy.gradeFee(set: inst.card.set)
        guard cash >= fee else { return nil }
        let oldValue = inst.currentValue
        cash -= fee
        stats.moneySpent += fee
        let g = Economy.rollGrade(using: &rng)
        instances[idx].grade = g
        stats.bestGrade = max(stats.bestGrade, g)
        stats.peakCardValue = max(stats.peakCardValue, instances[idx].currentValue)
        updatePeak()
        return GradeResult(grade: g, fee: fee, oldValue: oldValue, newValue: instances[idx].currentValue)
    }

    // MARK: Bonuses

    mutating func checkBonuses() -> [BonusEvent] {
        var events: [BonusEvent] = []
        let owned = uniqueOwnedIds

        for (lineId, cards) in CardDatabase.evolutionLines where !claimedEvoLines.contains(lineId) {
            if cards.allSatisfy({ owned.contains($0.id) }) {
                claimedEvoLines.insert(lineId)
                let amount = Economy.evolutionBonus(set: cards[0].set, stageCount: cards[0].stageCount)
                cash += amount
                stats.moneyEarned += amount
                let names = cards.map { $0.name }.joined(separator: " → ")
                events.append(BonusEvent(kind: .evolution, title: "Evolution complete: \(names)", amount: amount))
            }
        }

        for set in 1...CardDatabase.setCount where !claimedSets.contains(set) {
            let setCards = CardDatabase.cards(inSet: set)
            if !setCards.isEmpty && setCards.allSatisfy({ owned.contains($0.id) }) {
                claimedSets.insert(set)
                let amount = Economy.setCompletionBonus(set: set)
                cash += amount
                stats.moneyEarned += amount
                events.append(BonusEvent(kind: .set, title: "Set complete: \(CardDatabase.setName(set))!", amount: amount))
            }
        }

        updatePeak()
        if uniqueCount >= CardDatabase.all.count { hasWon = true }
        return events
    }

    private mutating func updatePeak() { stats.peakCash = max(stats.peakCash, cash) }
}
