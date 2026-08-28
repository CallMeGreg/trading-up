import Foundation

// MARK: - Stat keys

/// The lifetime Gauntlet stats meta progression tracks. They double as the
/// currency Trainer unlocks are priced in (see `TrainerUnlock`), so the keys live
/// in one place both the `Trainer` roster and `GauntletProgress` can name safely.
/// Defined alongside the run (not the persistence layer) so the headless balance
/// harness — which compiles `Trainer` and `GauntletCore` but not `GauntletProgress`
/// — resolves them.
enum GauntletStat {
    static let packsRipped    = "packsRipped"     // lifetime sum
    static let maxShowcase    = "maxShowcase"     // largest Showcase reached, any run
    static let bestRoundScore = "bestRoundScore"  // highest round appraisal, any run
    static let cardsGraded    = "cardsGraded"     // lifetime sum
    static let maxCashHeld     = "maxCashHeld"     // most cash held at once, any run
}

// MARK: - Rip & round results

/// What a finished run contributes to lifetime meta stats — gathered by
/// `GauntletRun` and folded into `GauntletProgress` via `ingest`, on a win *or* a
/// loss (you earned the milestones either way). Declared here, alongside the run,
/// so the headless balance harness compiles it without the persistence layer.
struct GauntletRunReport: Equatable {
    var packsRipped = 0
    var maxShowcase = 0
    var bestRoundScore = 0
    var cardsGraded = 0
    var maxCashHeld = 0
}

/// What a single rip surfaced: the pack's cards, plus an optional Catalyst offer.
struct RipResult {
    var cards: [CardInstance]
    var catalyst: Catalyst?
}

/// How a round ended.
enum RoundOutcome: Equatable {
    case cleared   // hit the bar, advanced to the next round
    case won       // cleared the final round — run won
    case lost      // missed the bar — run over (rounds are single-life)
}

// MARK: - Gauntlet run

/// One Gauntlet run: an escalating sequence of rounds, each demanding a rising
/// cumulative **appraisal** from your standing **Showcase**, reached within a
/// fixed number of **rips**, while **cash** (earned by selling at the spread,
/// spent in the between-round shop) is the across-run currency. Keep-vs-sell each
/// pull is the core decision. Pure Foundation game logic, like `GameCore`, so the
/// balance harness can drive it headless. See docs/DESIGN.md §14.
struct GauntletRun {

    let tier: GauntletTier
    var trainer: Trainer

    // Progress
    var round = 1
    var ripsLeft = 0
    var won = false
    var lost = false

    // Resources
    var cash: Double = 0
    var unlockedPacks: Set<Int> = [1]    // element sets rippable this run; set 1 is free, others bought open in any order
    var showcase: [CardInstance] = []     // the cards you keep (capacity = effectiveSlots)
    var attunedCatalysts: [Catalyst] = []
    var purchasedSlots = 0
    var purchasedCatalystSlots = 0

    // Round-clear earnings, remembered so the between-round shop can *show* them —
    // making the interest-on-unspent-cash lever obvious (docs/DESIGN.md §14).
    var lastInterest: Double = 0
    var lastStipend: Double = 0
    /// Cash paid for rips left unused when the round was cleared (docs/DESIGN.md §14).
    var lastRipBank: Double = 0

    // Lifetime-style stats this run contributes toward meta Trainer unlocks. Pure
    // and observable so `GauntletState` can fold them into `GauntletProgress` at the
    // end of a run (win or loss). See `runReport`.
    var packsRipped = 0
    var cardsGraded = 0
    var bestRoundScore = 0.0
    var maxShowcaseReached = 0
    private(set) var maxCashReached = 0.0

    init(tier: GauntletTier, trainer: Trainer) {
        self.tier = tier
        self.trainer = trainer
        self.cash = GauntletEconomy.startingCash + trainer.activeMods.startingCashBonus
        self.maxCashReached = self.cash
        startRound()
    }

    // MARK: Derived modifiers

    /// Trainer advantage plus every attuned Catalyst, summed.
    var mods: RunMods {
        var m = trainer.activeMods
        for c in attunedCatalysts { m = m + c.mods }
        return m
    }

    var effectiveSlots: Int { GauntletEconomy.startingSlots(tier) + purchasedSlots + mods.extraSlots }
    var effectiveCatalystSlots: Int { GauntletEconomy.baseCatalystSlots + purchasedCatalystSlots + mods.extraCatalystSlots }
    var evoLineBonus: Double { GauntletEconomy.baseEvoLineBonus + mods.evoLineBonusBonus }
    var sellbackRate: Double { min(Economy.sellbackRate + mods.sellbackBonus, GauntletEconomy.maxSellbackRate) }
    var foilChance: Double { Economy.foilChance + mods.foilChanceBonus }
    var ultraChance: Double { Economy.ultraHitChance + mods.ultraChanceBonus }
    func gradeFee(for card: Card) -> Double { Economy.gradeFee(set: card.set) * mods.gradeFeeMult }

    // MARK: Appraisal engine

    /// Score a set of cards: the sum of every card's market value (base × foil ×
    /// grade), lifted by a bonus for each *complete evolution line* standing in the
    /// group, then scaled by the run's global multiplier. A line is complete when
    /// every one of its stages is present — so chasing a line to its final form,
    /// not hoarding singles, is what the engine rewards (docs/DESIGN.md §14.4).
    static func appraise(_ cards: [CardInstance], evoLineBonus: Double, appraisalMult: Double) -> Double {
        var total = cards.reduce(0.0) { $0 + $1.currentValue }
        if evoLineBonus > 0 {
            // Group the multi-stage cards by their line; a line whose every stage is
            // represented lifts the value of all its cards in the group.
            let byLine = Dictionary(grouping: cards.filter { $0.card.stageCount > 1 },
                                    by: { $0.card.lineId })
            for (_, group) in byLine {
                let stageCount = group[0].card.stageCount
                let stagesPresent = Set(group.map { $0.card.stage })
                if stagesPresent.count == stageCount {
                    let lineValue = group.reduce(0.0) { $0 + $1.currentValue }
                    total += evoLineBonus * lineValue
                }
            }
        }
        return total * appraisalMult
    }

    var showcaseAppraisal: Double {
        Self.appraise(showcase, evoLineBonus: evoLineBonus, appraisalMult: mods.appraisalMult)
    }

    /// How much the Showcase's appraisal would rise if `inst` were kept (accounts
    /// for any evolution line it completes). Negative-improving swaps use this too.
    func marginalAppraisal(of inst: CardInstance) -> Double {
        let after = Self.appraise(showcase + [inst], evoLineBonus: evoLineBonus, appraisalMult: mods.appraisalMult)
        return after - showcaseAppraisal
    }

    /// The Showcase card that contributes the least appraisal right now.
    func weakestShowcaseIndex() -> Int? {
        guard !showcase.isEmpty else { return nil }
        let base = showcaseAppraisal
        var worst = 0
        var worstDrop = Double.greatestFiniteMagnitude
        for i in showcase.indices {
            var without = showcase
            without.remove(at: i)
            let drop = base - Self.appraise(without, evoLineBonus: evoLineBonus, appraisalMult: mods.appraisalMult)
            if drop < worstDrop { worstDrop = drop; worst = i }
        }
        return worst
    }

    // MARK: Targets

    var target: Double { GauntletEconomy.target(tier, round: round) }
    var isBossRound: Bool { GauntletEconomy.isBossRound(tier, round: round) }
    var roundsTotal: Int { GauntletEconomy.rounds(tier) }
    var progress: Double { target > 0 ? showcaseAppraisal / target : 1 }

    // MARK: Rounds

    mutating func startRound() {
        ripsLeft = GauntletEconomy.ripBudget(tier, round: round) + mods.extraRipsPerRound
    }

    /// Resolve the round once the player is done ripping.
    mutating func endRound<G: RandomNumberGenerator>(using rng: inout G) -> RoundOutcome {
        bestRoundScore = max(bestRoundScore, showcaseAppraisal)
        if showcaseAppraisal >= target {
            // Interest is figured on the cash you *held* (before this clear's
            // credits), so banking is what compounds. Leftover rips then cash out.
            let interest = GauntletEconomy.interest(on: cash)
            let stipend = GauntletEconomy.roundClearStipend(tier, round: round, appraisal: showcaseAppraisal) * mods.stipendMult
            let ripBank = GauntletEconomy.leftoverRipValue(round: round, rips: ripsLeft)
            lastInterest = interest
            lastStipend = stipend
            lastRipBank = ripBank
            cash += interest + stipend + ripBank
            ripsLeft = 0
            noteCash()
            if round >= roundsTotal { won = true; return .won }
            round += 1
            startRound()
            return .cleared
        } else {
            lost = true
            return .lost
        }
    }

    private mutating func noteCash() { maxCashReached = max(maxCashReached, cash) }

    /// This run's contribution to lifetime meta stats, folded into `GauntletProgress`
    /// when the run ends (win or loss).
    var runReport: GauntletRunReport {
        GauntletRunReport(
            packsRipped: packsRipped,
            maxShowcase: maxShowcaseReached,
            bestRoundScore: Int(bestRoundScore.rounded()),
            cardsGraded: cardsGraded,
            maxCashHeld: Int(maxCashReached.rounded()))
    }

    // MARK: Ripping

    /// Build a pack at `set` honouring run-modified foil/ultra chances. Mirrors
    /// `GameCore.buildPack`, parameterised so Catalysts can heat the packs.
    static func buildPack<G: RandomNumberGenerator>(set: Int, foilChance: Double, ultraChance: Double, using rng: inout G) -> [CardInstance] {
        let pool = CardDatabase.cards(inSet: set)
        let commons = pool.filter { $0.rarity == .common }
        let uncommons = pool.filter { $0.rarity == .uncommon }
        let rares = pool.filter { $0.rarity == .rare }
        let ultras = pool.filter { $0.rarity == .ultra }

        var out: [CardInstance] = []
        out += commons.shuffled(using: &rng).prefix(Economy.commonsPerPack).map { CardInstance(cardId: $0.id) }
        out += uncommons.shuffled(using: &rng).prefix(Economy.uncommonsPerPack).map { CardInstance(cardId: $0.id) }

        let hitIsUltra = Double.random(in: 0..<1, using: &rng) < ultraChance
        let hitPool = hitIsUltra ? ultras : rares
        if let hit = hitPool.randomElement(using: &rng) { out.append(CardInstance(cardId: hit.id)) }

        for i in out.indices where Double.random(in: 0..<1, using: &rng) < foilChance { out[i].foil = true }
        return out
    }

    /// Open one pack, spending a rip. Rips the given unlocked `set` (default: the
    /// highest unlocked tier). Returns the cards and any Catalyst offer.
    mutating func rip<G: RandomNumberGenerator>(from set: Int? = nil, using rng: inout G) -> RipResult {
        guard ripsLeft > 0 else { return RipResult(cards: [], catalyst: nil) }
        let s = set ?? packTier
        guard isPackUnlocked(s) else { return RipResult(cards: [], catalyst: nil) }
        ripsLeft -= 1
        packsRipped += 1
        var cards = Self.buildPack(set: s, foilChance: foilChance, ultraChance: ultraChance, using: &rng)
        var cat: Catalyst? = nil
        if Double.random(in: 0..<1, using: &rng) < GauntletEconomy.catalystDropChance {
            cat = Catalyst.random(using: &rng)
            // A Catalyst takes a normal card's slot in the pack rather than riding
            // along as a bonus — it drops the lowest-stakes common so the pull is a
            // real trade-off. (docs/DESIGN.md §14.4)
            if let drop = cards.lastIndex(where: { $0.card.rarity == .common }) {
                cards.remove(at: drop)
            } else if !cards.isEmpty {
                cards.removeLast()
            }
        }
        return RipResult(cards: cards, catalyst: cat)
    }

    // MARK: Packs (the rip rail)

    /// Highest set currently unlocked — the default set `rip` opens and what the
    /// end-of-run trace reports. Derived from `unlockedPacks` (starter set 1 is
    /// always in the set, so this never falls below 1).
    var packTier: Int { unlockedPacks.max() ?? 1 }

    /// Whether a set's packs can be ripped this run. Sets unlock independently and
    /// out of order — buying set 4 open doesn't require sets 2 or 3.
    func isPackUnlocked(_ set: Int) -> Bool { unlockedPacks.contains(set) }

    /// Every set the pack rail shows, low → high.
    static let allPackTiers: [Int] = Array(1...GauntletEconomy.maxPackTier)

    /// The cheapest still-locked set on the rail (used by the sim/AI to pick the
    /// next sensible unlock), or nil once every set is open.
    var nextLockedPack: Int? {
        Self.allPackTiers.filter { !isPackUnlocked($0) }
            .min { (GauntletEconomy.packUnlockCost(set: $0) ?? .infinity) < (GauntletEconomy.packUnlockCost(set: $1) ?? .infinity) }
    }

    // MARK: Keep / sell / swap

    var canKeep: Bool { showcase.count < effectiveSlots }

    mutating func keep(_ inst: CardInstance) {
        if canKeep {
            showcase.append(inst)
            maxShowcaseReached = max(maxShowcaseReached, showcase.count)
        }
    }

    @discardableResult
    mutating func sell(_ inst: CardInstance) -> Double {
        let gain = inst.currentValue * sellbackRate
        cash += gain
        noteCash()
        return gain
    }

    /// Replace a Showcase card, banking the removed one's sell-back into cash.
    @discardableResult
    mutating func swapIn(_ inst: CardInstance, at index: Int) -> CardInstance {
        let removed = showcase[index]
        cash += removed.currentValue * sellbackRate
        noteCash()
        showcase[index] = inst
        return removed
    }

    // MARK: Grading (gamble a keeper's score)

    private mutating func rollGradeWithLuck<G: RandomNumberGenerator>(using rng: inout G) -> Int {
        let g1 = Economy.rollGrade(using: &rng)
        if Double.random(in: 0..<1, using: &rng) < mods.gradeLuckBonus {
            let g2 = Economy.rollGrade(using: &rng)
            return Economy.gradeMultiplier(g2) > Economy.gradeMultiplier(g1) ? g2 : g1
        }
        return g1
    }

    /// Grade the Showcase card at `index`, paying the fee. No-op if already graded
    /// or unaffordable. Returns the rolled grade.
    @discardableResult
    mutating func gradeShowcaseCard<G: RandomNumberGenerator>(at index: Int, using rng: inout G) -> Int? {
        guard showcase.indices.contains(index), showcase[index].grade == nil else { return nil }
        let fee = gradeFee(for: showcase[index].card)
        guard cash >= fee else { return nil }
        cash -= fee
        let g = rollGradeWithLuck(using: &rng)
        showcase[index].grade = g
        cardsGraded += 1
        return g
    }

    // MARK: Catalysts

    var canAttune: Bool { attunedCatalysts.count < effectiveCatalystSlots }

    @discardableResult
    mutating func attune(_ catalyst: Catalyst) -> Bool {
        guard canAttune else { return false }
        attunedCatalysts.append(catalyst)
        return true
    }

    mutating func sellCatalyst(_ catalyst: Catalyst) { cash += catalyst.saleValue; noteCash() }

    // MARK: Shop (between rounds)

    /// Cost to unlock a specific locked set's packs, or nil if it's the free
    /// starter, already unlocked, or off the rail.
    func packUnlockCost(_ set: Int) -> Double? {
        guard !isPackUnlocked(set) else { return nil }
        return GauntletEconomy.packUnlockCost(set: set)
    }
    /// Whether the run can afford to open a given locked set right now.
    func canUnlockPack(_ set: Int) -> Bool {
        guard let cost = packUnlockCost(set) else { return false }
        return cash >= cost
    }
    var nextSlotCost: Double { GauntletEconomy.slotCost(purchased: purchasedSlots) }
    var nextCatalystSlotCost: Double { GauntletEconomy.catalystSlotCost(purchased: purchasedCatalystSlots) }

    /// Buy a specific locked set open (any order). No-op if unaffordable/invalid.
    @discardableResult
    mutating func unlockPack(_ set: Int) -> Bool {
        guard let cost = packUnlockCost(set), cash >= cost else { return false }
        cash -= cost
        unlockedPacks.insert(set)
        return true
    }

    /// Convenience for the sim/AI: open the cheapest still-locked set if affordable.
    @discardableResult
    mutating func unlockNextPack() -> Bool {
        guard let set = nextLockedPack else { return false }
        return unlockPack(set)
    }

    @discardableResult
    mutating func buySlot() -> Bool {
        let cost = nextSlotCost
        guard cash >= cost else { return false }
        cash -= cost
        purchasedSlots += 1
        return true
    }

    @discardableResult
    mutating func buyCatalystSlot() -> Bool {
        let cost = nextCatalystSlotCost
        guard cash >= cost else { return false }
        cash -= cost
        purchasedCatalystSlots += 1
        return true
    }
}
