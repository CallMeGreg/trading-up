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
    case retry     // missed the bar but spent a reprint; same round restarts
    case lost      // missed the bar with no reprints left — run over
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
    var retriesLeft = 0
    var won = false
    var lost = false

    // Resources
    var cash: Double = 0
    var packTier = 1                      // highest set unlocked; any set 1…packTier is rippable
    var showcase: [CardInstance] = []     // the cards you keep (capacity = effectiveSlots)
    var attunedCatalysts: [Catalyst] = []
    var purchasedSlots = 0
    var purchasedCatalystSlots = 0

    // Round-clear earnings, remembered so the between-round shop can *show* them —
    // making the interest-on-unspent-cash lever obvious (docs/DESIGN.md §14).
    var lastInterest: Double = 0
    var lastStipend: Double = 0

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
        self.retriesLeft = GauntletEconomy.retries(tier)
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
    var synergyPerMatch: Double { GauntletEconomy.baseSynergyPerMatch + mods.synergyPerMatchBonus }
    var sellbackRate: Double { min(Economy.sellbackRate + mods.sellbackBonus, GauntletEconomy.maxSellbackRate) }
    var foilChance: Double { Economy.foilChance + mods.foilChanceBonus }
    var ultraChance: Double { Economy.ultraHitChance + mods.ultraChanceBonus }
    func gradeFee(for card: Card) -> Double { Economy.gradeFee(set: card.set) * mods.gradeFeeMult }

    // MARK: Appraisal engine

    /// Score a set of cards: each card's market value (base × foil × grade), lifted
    /// by same-element synergy within the group, then by the run's global multiplier.
    static func appraise(_ cards: [CardInstance], synergyPerMatch: Double, appraisalMult: Double) -> Double {
        var total = 0.0
        for c in cards {
            let matches = cards.filter { $0.id != c.id && $0.card.element == c.card.element }.count
            total += c.currentValue * (1 + synergyPerMatch * Double(matches))
        }
        return total * appraisalMult
    }

    var showcaseAppraisal: Double {
        Self.appraise(showcase, synergyPerMatch: synergyPerMatch, appraisalMult: mods.appraisalMult)
    }

    /// How much the Showcase's appraisal would rise if `inst` were kept (accounts
    /// for synergy in both directions). Negative-improving swaps use this too.
    func marginalAppraisal(of inst: CardInstance) -> Double {
        let after = Self.appraise(showcase + [inst], synergyPerMatch: synergyPerMatch, appraisalMult: mods.appraisalMult)
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
            let drop = base - Self.appraise(without, synergyPerMatch: synergyPerMatch, appraisalMult: mods.appraisalMult)
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
            let interest = GauntletEconomy.interest(on: cash)
            let stipend = GauntletEconomy.roundClearStipend(tier, round: round, appraisal: showcaseAppraisal) * mods.stipendMult
            lastInterest = interest
            lastStipend = stipend
            cash += interest + stipend
            noteCash()
            if round >= roundsTotal { won = true; return .won }
            round += 1
            startRound()
            return .cleared
        } else if retriesLeft > 0 {
            retriesLeft -= 1
            startRound()
            return .retry
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
        let cards = Self.buildPack(set: s, foilChance: foilChance, ultraChance: ultraChance, using: &rng)
        var cat: Catalyst? = nil
        if Double.random(in: 0..<1, using: &rng) < GauntletEconomy.catalystDropChance {
            cat = Catalyst.random(using: &rng)
        }
        return RipResult(cards: cards, catalyst: cat)
    }

    // MARK: Packs (the rip rail)

    /// Whether a set's packs can be ripped this run — everything up to the highest
    /// unlocked tier. Richer sets are unlocked (for cash) as the run goes.
    func isPackUnlocked(_ set: Int) -> Bool { set >= 1 && set <= packTier }

    /// Every set the pack rail shows, low → high.
    static let allPackTiers: [Int] = Array(1...GauntletEconomy.maxPackTier)

    /// The next set that can be unlocked (one above the highest unlocked), or nil
    /// once the run is at the cap.
    var nextPackTier: Int? { packTier < GauntletEconomy.maxPackTier ? packTier + 1 : nil }

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

    var packTierUpgradeCost: Double? {
        guard packTier < GauntletEconomy.maxPackTier else { return nil }
        return GauntletEconomy.packTierUpgradeCost(to: packTier + 1)
    }
    var nextSlotCost: Double { GauntletEconomy.slotCost(purchased: purchasedSlots) }
    var nextCatalystSlotCost: Double { GauntletEconomy.catalystSlotCost(purchased: purchasedCatalystSlots) }

    @discardableResult
    mutating func upgradePackTier() -> Bool {
        guard let cost = packTierUpgradeCost, cash >= cost else { return false }
        cash -= cost
        packTier += 1
        return true
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
