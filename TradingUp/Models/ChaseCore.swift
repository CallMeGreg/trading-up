import Foundation

// MARK: - RunState — one live Hunt
//
// Cash, stock and Items persist across Leads within a Hunt; only the Energy
// budget refreshes and the Ask bar rises. RunState is Codable so a Hunt can be
// saved mid-run.

struct RunState: Codable {
    var grail: Grail
    var trainer: TrainerKind
    var maxSet: Int                       // highest set the player may rip (paywall)

    var stock: [CardInstance] = []
    var cash: Double
    var items: [ItemKind] = []            // owned; passives always-on, one-shots consumed on use
    var energy: Int = 0                   // remaining at the current Lead

    var lead: Lead
    var route: [LeadOption] = []          // branches to the next Lead
    var draft: [DraftOption] = []         // current post-Lead draft offers
    var bazaarOffers: [ItemKind] = []     // items on sale between Leads
    var phase: HuntPhase = .working
    var totalLeads: Int

    var leadsRunDown = 0
    var renownBanked: Double = 0
    var pendingEnergyBonus = 0            // drafted/route Energy, applied at the next Lead
    var newDiscoveries: [Discovery] = []  // hit during this Hunt, for the summary

    // Per-Lead flags
    var freeFirstPackUsed = false         // Speculator
    var packSearchArmed = false           // Pack Search one-shot
    var rerollsUsed = 0

    // Per-Hunt discovery counters
    var gradedNinePlus = 0

    init(grail: Grail, trainer: TrainerKind, maxSet: Int, cash: Double,
         lead: Lead, totalLeads: Int) {
        self.grail = grail; self.trainer = trainer; self.maxSet = maxSet
        self.cash = cash; self.lead = lead; self.totalLeads = totalLeads
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        grail          = try c.decode(Grail.self, forKey: .grail)
        trainer        = try c.decodeIfPresent(TrainerKind.self, forKey: .trainer) ?? .digger
        maxSet         = try c.decodeIfPresent(Int.self, forKey: .maxSet) ?? CardDatabase.setCount
        stock          = try c.decodeIfPresent([CardInstance].self, forKey: .stock) ?? []
        cash           = try c.decodeIfPresent(Double.self, forKey: .cash) ?? 0
        items          = try c.decodeIfPresent([ItemKind].self, forKey: .items) ?? []
        energy         = try c.decodeIfPresent(Int.self, forKey: .energy) ?? 0
        lead           = try c.decode(Lead.self, forKey: .lead)
        route          = try c.decodeIfPresent([LeadOption].self, forKey: .route) ?? []
        draft          = try c.decodeIfPresent([DraftOption].self, forKey: .draft) ?? []
        bazaarOffers   = try c.decodeIfPresent([ItemKind].self, forKey: .bazaarOffers) ?? []
        phase          = try c.decodeIfPresent(HuntPhase.self, forKey: .phase) ?? .working
        totalLeads     = try c.decodeIfPresent(Int.self, forKey: .totalLeads) ?? 4
        leadsRunDown   = try c.decodeIfPresent(Int.self, forKey: .leadsRunDown) ?? 0
        renownBanked   = try c.decodeIfPresent(Double.self, forKey: .renownBanked) ?? 0
        pendingEnergyBonus = try c.decodeIfPresent(Int.self, forKey: .pendingEnergyBonus) ?? 0
        newDiscoveries = try c.decodeIfPresent([Discovery].self, forKey: .newDiscoveries) ?? []
        freeFirstPackUsed = try c.decodeIfPresent(Bool.self, forKey: .freeFirstPackUsed) ?? false
        packSearchArmed   = try c.decodeIfPresent(Bool.self, forKey: .packSearchArmed) ?? false
        rerollsUsed    = try c.decodeIfPresent(Int.self, forKey: .rerollsUsed) ?? 0
        gradedNinePlus = try c.decodeIfPresent(Int.self, forKey: .gradedNinePlus) ?? 0
    }

    // Derived
    func hasPassive(_ k: ItemKind) -> Bool { k.isPassive && items.contains(k) }
    func hasItem(_ k: ItemKind) -> Bool { items.contains(k) }
    var uniqueCount: Int { Set(stock.map { $0.cardId }).count }
    var netWorth: Double { cash + stock.reduce(0) { $0 + $1.currentValue } }
    var isScore: Bool { lead.isScore }

    func instances(of cardId: String) -> [CardInstance] { stock.filter { $0.cardId == cardId } }
    func maxCopiesOfAnyCard() -> Int {
        Dictionary(grouping: stock, by: { $0.cardId }).values.map { $0.count }.max() ?? 0
    }
}

// MARK: - HuntSummary — the post-run recap (win or bust)

struct HuntSummary: Hashable {
    var won: Bool
    var grailHeadline: String
    var leadsRunDown: Int
    var renownEarned: Double
    var cardsDeposited: Int
    var newDiscoveries: [Discovery]
    var binderUnique: Int
}

// MARK: - ChaseCore — the pure, deterministic engine

struct ChaseCore: Codable {
    var meta = MetaState()
    var run: RunState? = nil

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        meta = try c.decodeIfPresent(MetaState.self, forKey: .meta) ?? MetaState()
        run  = try c.decodeIfPresent(RunState.self, forKey: .run)
    }

    private enum CodingKeys: String, CodingKey { case meta, run }

    // MARK: Rates & effects
    //
    // Param-based so mutating funcs can read the *in-flight* RunState; thin
    // `run`-based wrappers below serve the UI.

    static func foilChance(_ r: RunState) -> Double {
        if r.lead.complication.blocksFoils { return 0 }
        var f = Economy.chaseFoilChance
        if r.hasPassive(.gilder) { f += Economy.gilderFoilBonus }
        if r.trainer == .foilhunter { f += Economy.foilhunterFoilBonus }
        return f
    }

    static func gradingIsFree(_ r: RunState) -> Bool {
        r.trainer == .grader || r.hasPassive(.loupe)
    }

    static func gradeFeeNow(_ r: RunState, set: Int) -> Double {
        gradingIsFree(r) ? 0 : Economy.gradeFee(set: set) * r.lead.complication.gradeFeeFactor
    }

    static func sellbackRate(_ r: RunState, for inst: CardInstance) -> Double {
        var rate = r.hasPassive(.bulkBuyer) ? Economy.bulkBuyerSellback : Economy.sellbackRate
        rate *= r.lead.complication.sellbackFactor
        if inst.foil && r.trainer == .foilhunter { rate += Economy.foilhunterFoilSellBonus }
        return min(rate, 1.10)
    }

    // UI wrappers
    func gradingIsFree() -> Bool { run.map(ChaseCore.gradingIsFree) ?? false }
    func gradeFeeNow(set: Int) -> Double { run.map { ChaseCore.gradeFeeNow($0, set: set) } ?? Economy.gradeFee(set: set) }
    func sellbackRate(for inst: CardInstance) -> Double { run.map { ChaseCore.sellbackRate($0, for: inst) } ?? Economy.sellbackRate }
    func sellPreview(_ inst: CardInstance) -> Double { inst.currentValue * sellbackRate(for: inst) }

    // MARK: Energy budgeting

    /// Energy granted at a Lead: base (meta) + Trainer (Digger) + Complication + boss bonus.
    func energyBudget(complication: Complication, isBoss: Bool, trainer: TrainerKind) -> Int {
        var e = meta.baseEnergyPerLead
        if trainer == .digger { e += Economy.diggerBonusEnergy }
        e += complication.energyDelta
        if isBoss { e += Economy.bossEnergyBonus }
        return max(1, e)
    }
}
