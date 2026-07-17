import Foundation

// MARK: - Owned instance

/// A specific owned copy of a card. Two copies of the same card can differ in foil/grade.
struct CardInstance: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    let cardId: String
    var foil: Bool = false
    var grade: Int? = nil    // nil = ungraded

    var card: Card { CardDatabase.byId[cardId]! }
    var currentValue: Double { Economy.value(base: card.baseValue, foil: foil, grade: grade) }
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
    var hasWon = false
    /// Optional so older saves (which lack the key) decode cleanly to `nil`.
    var welcomeSeen: Bool? = nil

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
        return cash < Economy.packPrice(set: 1) && sellableInstances.isEmpty
    }

    // MARK: Welcome / onboarding

    var hasSeenWelcome: Bool { welcomeSeen ?? false }

    /// Show the intro only on a brand-new game (fresh, no progress yet) that
    /// hasn't been dismissed — so it appears on first launch and after New Game,
    /// but never interrupts an in-progress collection.
    var shouldShowWelcome: Bool { !hasSeenWelcome && instances.isEmpty && stats.packsOpened == 0 }

    mutating func markWelcomeSeen() { welcomeSeen = true }

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
        let pack = buildPack(set: set, using: &rng)
        ingest(pack)
        let bonuses = checkBonuses()
        return OpenResult(pulled: pack, bonuses: bonuses, isBox: false)
    }

    mutating func buyBox<G: RandomNumberGenerator>(set: Int, using rng: inout G) -> OpenResult? {
        guard isUnlocked(set: set) else { return nil }
        let price = Economy.boxPrice(set: set)
        guard cash >= price else { return nil }
        cash -= price
        stats.moneySpent += price
        stats.boxesOpened += 1
        stats.packsOpened += Economy.boxPacks

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

        ingest(pulled)
        let bonuses = checkBonuses()
        return OpenResult(pulled: pulled, bonuses: bonuses, isBox: true)
    }

    private mutating func ingest(_ newInstances: [CardInstance]) {
        instances += newInstances
        stats.cardsPulled += newInstances.count
        stats.foilsPulled += newInstances.filter { $0.foil }.count
        stats.ultrasPulled += newInstances.filter { CardDatabase.byId[$0.cardId]?.rarity == .ultra }.count
        updatePeak()
    }

    // MARK: Selling

    @discardableResult
    mutating func sell(instanceId: UUID) -> Double? {
        guard let idx = instances.firstIndex(where: { $0.id == instanceId }) else { return nil }
        let inst = instances[idx]
        guard isSellable(inst) else { return nil }
        let v = inst.currentValue
        instances.remove(at: idx)
        cash += v
        stats.moneyEarned += v
        stats.cardsSold += 1
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
                proceeds += extra.currentValue
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
