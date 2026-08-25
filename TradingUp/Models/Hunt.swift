import Foundation

// MARK: - Ask — the varied Lead objective
//
// Every Lead poses an Ask: the thing you must satisfy to run the Lead down and
// follow it to the next, hotter one. Asks vary by type, so no single strategy
// (e.g. hoard cash) solves every Lead. An Ask is pure data + evaluation; the
// engine generates them (`ChaseCore.makeAsk`) with run context.

enum AskKind: String, Codable, CaseIterable, Hashable {
    case cash       // bank $X
    case grade      // possess a card graded ≥ N
    case handover   // give up a card meeting a spec (consumes it)
    case set        // own K distinct cards from a named set
    case evolution  // complete a named evolution line
    case value      // own a single card worth ≥ $X

    var label: String {
        switch self {
        case .cash: return "Cash"
        case .grade: return "Grade"
        case .handover: return "Handover"
        case .set: return "Set"
        case .evolution: return "Evolution"
        case .value: return "Value"
        }
    }
}

/// A Lead's objective. One `AskKind` plus whichever parameters it needs; unused
/// fields stay at their defaults. Codable + lenient so it round-trips in a save.
struct Ask: Codable, Hashable {
    var kind: AskKind
    var amount: Double = 0        // Cash / Value target
    var gradeMin: Int = 0         // Grade target, or Handover "graded N+"
    var setId: Int = 0            // Set target, or Handover "from set"
    var count: Int = 0            // Set: K distinct cards
    var lineId: String = ""       // Evolution: which line
    var requireFoil: Bool = false // Handover: a foil
    var requireRare: Bool = false // Handover: a rare (or better)

    init(kind: AskKind) { self.kind = kind }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind        = try c.decodeIfPresent(AskKind.self, forKey: .kind) ?? .cash
        amount      = try c.decodeIfPresent(Double.self,  forKey: .amount) ?? 0
        gradeMin    = try c.decodeIfPresent(Int.self,     forKey: .gradeMin) ?? 0
        setId       = try c.decodeIfPresent(Int.self,     forKey: .setId) ?? 0
        count       = try c.decodeIfPresent(Int.self,     forKey: .count) ?? 0
        lineId      = try c.decodeIfPresent(String.self,  forKey: .lineId) ?? ""
        requireFoil = try c.decodeIfPresent(Bool.self,    forKey: .requireFoil) ?? false
        requireRare = try c.decodeIfPresent(Bool.self,    forKey: .requireRare) ?? false
    }

    /// Whether the Ask consumes a card when the Lead is run down.
    var consumesCard: Bool { kind == .handover }

    /// Does a single owned copy satisfy the *card* portion of this Ask? (Used for
    /// Handover to find which card to surrender, and for Value/Grade checks.)
    func cardQualifies(_ inst: CardInstance) -> Bool {
        switch kind {
        case .value:    return inst.currentValue >= amount
        case .grade:    return (inst.grade ?? 0) >= gradeMin
        case .handover:
            if requireFoil && !inst.foil { return false }
            if requireRare && !inst.card.rarity.canBeGraded { return false }
            if gradeMin != 0 && (inst.grade ?? 0) < gradeMin { return false }
            if setId != 0 && inst.card.set != setId { return false }
            return true
        default:        return false
        }
    }

    /// Is the Ask satisfied by the given cash + stock right now?
    func isSatisfied(cash: Double, stock: [CardInstance]) -> Bool {
        switch kind {
        case .cash:
            return cash >= amount
        case .value, .grade, .handover:
            return stock.contains(where: cardQualifies)
        case .set:
            let owned = Set(stock.map { $0.cardId }.filter { CardDatabase.byId[$0]?.set == setId })
            return owned.count >= count
        case .evolution:
            let line = CardDatabase.line(lineId)
            guard !line.isEmpty else { return false }
            let owned = Set(stock.map { $0.cardId })
            return line.allSatisfy { owned.contains($0.id) }
        }
    }

    /// (current, target) numeric progress, for a progress bar. Cash uses dollars.
    func progress(cash: Double, stock: [CardInstance]) -> (current: Double, target: Double) {
        switch kind {
        case .cash:  return (min(cash, amount), amount)
        case .value:
            let best = stock.map { $0.currentValue }.max() ?? 0
            return (min(best, amount), amount)
        case .grade:
            let best = stock.compactMap { $0.grade }.max() ?? 0
            return (Double(min(best, gradeMin)), Double(gradeMin))
        case .handover:
            return (stock.contains(where: cardQualifies) ? 1 : 0, 1)
        case .set:
            let owned = Set(stock.map { $0.cardId }.filter { CardDatabase.byId[$0]?.set == setId })
            return (Double(min(owned.count, count)), Double(count))
        case .evolution:
            let line = CardDatabase.line(lineId)
            let owned = Set(stock.map { $0.cardId })
            let have = line.filter { owned.contains($0.id) }.count
            return (Double(have), Double(max(line.count, 1)))
        }
    }

    var describe: String {
        switch kind {
        case .cash:  return "Bank $\(Int(amount))"
        case .value: return "Own a card worth ≥ $\(Int(amount))"
        case .grade: return "Own a card graded ≥ PSA \(gradeMin)"
        case .handover:
            if requireFoil { return "Hand over a foil" }
            if gradeMin != 0 { return "Hand over a card graded \(gradeMin)+" }
            if requireRare { return "Hand over a rare or better" }
            return "Hand over a card"
        case .set:  return "Own \(count) distinct \(CardDatabase.setName(setId)) cards"
        case .evolution:
            let names = CardDatabase.line(lineId).map { $0.name }
            return "Complete the \(names.first ?? "evolution") line"
        }
    }
}

// MARK: - Grail — the run's win condition
//
// The single dream card a Hunt trades up toward. Always offered as one Easy, one
// Medium, one Hard at the start. A Grail is a card *classifier* plus a cash price
// paid at the Score. Win = hold a card that matches AND pay its price.

enum GrailTier: String, Codable, CaseIterable, Hashable {
    case easy, medium, hard

    var label: String { rawValue.capitalized }
}

struct Grail: Codable, Hashable {
    var tier: GrailTier
    var price: Double

    // Classifier — any field left at default is "don't care".
    var cardId: String = ""       // a specific named card (Hard)
    var setId: Int = 0            // constrain to a set (Medium/Hard)
    var rarity: Rarity? = nil     // "any ultra"
    var requireFoil: Bool = false
    var gradeMin: Int = 0
    var minValue: Double = 0

    var headline: String = ""     // human summary, precomputed at offer time

    init(tier: GrailTier, price: Double) { self.tier = tier; self.price = price }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tier        = try c.decodeIfPresent(GrailTier.self, forKey: .tier) ?? .easy
        price       = try c.decodeIfPresent(Double.self,    forKey: .price) ?? 0
        cardId      = try c.decodeIfPresent(String.self,    forKey: .cardId) ?? ""
        setId       = try c.decodeIfPresent(Int.self,       forKey: .setId) ?? 0
        rarity      = try c.decodeIfPresent(Rarity.self,    forKey: .rarity)
        requireFoil = try c.decodeIfPresent(Bool.self,      forKey: .requireFoil) ?? false
        gradeMin    = try c.decodeIfPresent(Int.self,       forKey: .gradeMin) ?? 0
        minValue    = try c.decodeIfPresent(Double.self,    forKey: .minValue) ?? 0
        headline    = try c.decodeIfPresent(String.self,    forKey: .headline) ?? ""
    }

    /// Does this owned copy satisfy the Grail's condition (ignoring price)?
    func matches(_ inst: CardInstance) -> Bool {
        let card = inst.card
        if !cardId.isEmpty && inst.cardId != cardId { return false }
        if setId != 0 && card.set != setId { return false }
        if let r = rarity, card.rarity != r { return false }
        if requireFoil && !inst.foil { return false }
        if gradeMin != 0 && (inst.grade ?? 0) < gradeMin { return false }
        if minValue != 0 && inst.currentValue < minValue { return false }
        return true
    }

    func isHeld(in stock: [CardInstance]) -> Bool { stock.contains(where: matches) }
}

// MARK: - Complications — per-Lead modifiers (light variety layer)
//
// Some Leads (and a boss Lead every 4th) carry a Complication that forces
// adaptation. You see it while routing, so it's a pre-committed wager, not a
// gotcha. These are secondary variety knobs kept with the type; core balance
// lives in Economy.

enum Complication: String, Codable, CaseIterable, Hashable {
    case none, coldSnap, backlog, counterfeits, rush, bullMarket, authenticator

    var title: String {
        switch self {
        case .none:          return "Clear"
        case .coldSnap:      return "Cold Snap"
        case .backlog:       return "Backlog"
        case .counterfeits:  return "Counterfeits"
        case .rush:          return "Rush"
        case .bullMarket:    return "Bull Market"
        case .authenticator: return "The Authenticator"
        }
    }

    var blurb: String {
        switch self {
        case .none:          return "No complication."
        case .coldSnap:      return "Sell-back drops to 60% this Lead."
        case .backlog:       return "Grading fees are doubled this Lead."
        case .counterfeits:  return "No foils can be pulled this Lead."
        case .rush:          return "−2 Energy, but the Ask is 20% lighter."
        case .bullMarket:    return "Sells pay 20% more, but the Ask is 25% steeper."
        case .authenticator: return "Boss: the Ask demands a graded 9+."
        }
    }

    // Effect queries (secondary variety knobs). Sell-back is a *factor* so passive
    // counters (Bulk Buyer, Foilhunter) still help against a Cold Snap.
    var sellbackFactor: Double {
        switch self {
        case .coldSnap:   return 0.80   // ~0.75 → 0.60
        case .bullMarket: return 1.20   // sells pay more
        default:          return 1.0
        }
    }
    var gradeFeeFactor: Double { self == .backlog ? 2.0 : 1.0 }
    var blocksFoils: Bool { self == .counterfeits }
    var energyDelta: Int { self == .rush ? -2 : 0 }
    var askMultiplier: Double {
        switch self {
        case .rush:       return 0.80
        case .bullMarket: return 1.25
        default:          return 1.0
        }
    }
    var isBoss: Bool { self == .authenticator }
}

// MARK: - Lead & route options

struct Lead: Codable, Hashable {
    var index: Int                 // 1-based
    var ask: Ask
    var energyBudget: Int
    var complication: Complication = .none
    var isScore: Bool = false      // the final Lead: the Grail is on the table
}

/// A bonus a route branch pays when you run it down — makes routing meaningful
/// beyond the Ask/Complication tradeoff.
enum RouteBonus: Codable, Hashable {
    case cash(Double)
    case energy(Int)     // added to the next Lead's budget
    case freeItem        // an extra free Item, drafted-style

    var describe: String {
        switch self {
        case .cash(let x):  return "+$\(Int(x))"
        case .energy(let e): return "+\(e) Energy next Lead"
        case .freeItem:      return "a free Item"
        }
    }
}

/// One branch shown up front when routing to the next Lead.
struct LeadOption: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var ask: Ask
    var complication: Complication
    var energyBudget: Int
    var bonus: RouteBonus
    var isScore: Bool = false

    init(id: UUID = UUID(), ask: Ask, complication: Complication,
         energyBudget: Int, bonus: RouteBonus, isScore: Bool = false) {
        self.id = id; self.ask = ask; self.complication = complication
        self.energyBudget = energyBudget; self.bonus = bonus; self.isScore = isScore
    }
}

// MARK: - Draft

/// A single post-Lead draft offer: an Item or a chunk of Energy.
struct DraftOption: Codable, Hashable, Identifiable {
    enum Kind: Codable, Hashable {
        case item(ItemKind)
        case energy(Int)   // added to the next Lead
    }
    var id: UUID = UUID()
    var kind: Kind

    init(id: UUID = UUID(), kind: Kind) { self.id = id; self.kind = kind }

    var title: String {
        switch kind {
        case .item(let i):   return i.title
        case .energy(let e): return "+\(e) Energy"
        }
    }
    var blurb: String {
        switch kind {
        case .item(let i):   return i.blurb
        case .energy:        return "Extra Energy for your next Lead."
        }
    }
}

// MARK: - Hunt phase

enum HuntPhase: String, Codable, Hashable {
    case working   // ripping / selling / grading at the current Lead (incl. Score)
    case draft     // pick 1 of N after running down a Lead
    case bazaar    // spend cash on Items / reroll
    case route     // choose the next Lead from branches
    case won       // Grail landed
    case bust      // the Grail slipped away
}
