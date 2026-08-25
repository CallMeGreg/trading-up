import Foundation

// MARK: - ChaseCore: generation (Grails, Asks, Leads, packs, drafts, bazaar)

extension ChaseCore {

    static func randomPassiveItem<G: RandomNumberGenerator>(using rng: inout G) -> ItemKind {
        ItemKind.allCases.filter { $0.isPassive }.randomElement(using: &rng) ?? .loupe
    }

    /// Build a Sprytes-only pack (unchanged from v1: 3 common + 2 uncommon + 1
    /// hit), applying the run's foil chance, Whale (+1 card) and Pack Search
    /// (guaranteed ultra hit). Pure — no `self` state changes.
    static func makePack<G: RandomNumberGenerator>(set: Int, foilChance: Double, whale: Bool,
                                                   packSearch: Bool, using rng: inout G) -> [CardInstance] {
        let inSet = CardDatabase.cards(inSet: set)
        func pick(_ r: Rarity) -> Card? { inSet.filter { $0.rarity == r }.randomElement(using: &rng) }
        var out: [CardInstance] = []
        for _ in 0..<Economy.commonsPerPack   { if let c = pick(.common)   { out.append(CardInstance(cardId: c.id)) } }
        for _ in 0..<Economy.uncommonsPerPack { if let c = pick(.uncommon) { out.append(CardInstance(cardId: c.id)) } }
        let ultra = packSearch || Double.random(in: 0..<1, using: &rng) < Economy.ultraHitChance
        if let c = pick(ultra ? .ultra : .rare) ?? pick(.rare) { out.append(CardInstance(cardId: c.id)) }
        if whale, let c = pick(.common) { out.append(CardInstance(cardId: c.id)) }
        for i in out.indices where Double.random(in: 0..<1, using: &rng) < foilChance { out[i].foil = true }
        return out
    }

    // MARK: Grails — always one Easy, one Medium, one Hard

    func grailOffers<G: RandomNumberGenerator>(using rng: inout G) -> [Grail] {
        [makeGrail(tier: .easy,   using: &rng),
         makeGrail(tier: .medium, using: &rng),
         makeGrail(tier: .hard,   using: &rng)]
    }

    func makeGrail<G: RandomNumberGenerator>(tier: GrailTier, using rng: inout G) -> Grail {
        let maxSet = Economy.grailMaxSet(tier: tier)
        switch tier {
        case .easy:
            var g = Grail(tier: .easy, price: 0)
            switch Int.random(in: 0..<3, using: &rng) {
            case 0:  g.requireFoil = true;               g.headline = "Any foil Spryte"
            case 1:  g.gradeMin = 10;                    g.headline = "Any Spryte graded PSA 10"
            default: g.rarity = .ultra; g.minValue = 120; g.headline = "Any Ultra worth $120+"
            }
            g.price = Economy.grailPrice(tier: .easy, setId: 0, requireFoil: g.requireFoil, gradeMin: g.gradeMin)
            return g
        case .medium:
            let set = Int.random(in: 1...max(1, maxSet), using: &rng)
            var g = Grail(tier: .medium, price: 0); g.setId = set
            if Bool.random(using: &rng) { g.requireFoil = true; g.headline = "A \(CardDatabase.setName(set)) foil" }
            else { g.gradeMin = 8; g.headline = "A \(CardDatabase.setName(set)) card graded 8+" }
            g.price = Economy.grailPrice(tier: .medium, setId: set, requireFoil: g.requireFoil, gradeMin: g.gradeMin)
            return g
        case .hard:
            let set = Int.random(in: 1...max(1, maxSet), using: &rng)
            let ultras = CardDatabase.cards(inSet: set).filter { $0.rarity == .ultra }
            let target = ultras.randomElement(using: &rng) ?? CardDatabase.cards(inSet: set).last
            var g = Grail(tier: .hard, price: 0)
            g.cardId = target?.id ?? ""; g.setId = set
            let name = target?.name ?? "a legendary Spryte"
            if Bool.random(using: &rng) { g.requireFoil = true; g.headline = "\(name) — foil" }
            else { g.gradeMin = 9; g.headline = "\(name) — graded 9+" }
            g.price = Economy.grailPrice(tier: .hard, setId: set, requireFoil: g.requireFoil, gradeMin: g.gradeMin)
            return g
        }
    }

    // MARK: Asks — the varied objective deck

    func makeAsk<G: RandomNumberGenerator>(leadIndex: Int, isBoss: Bool, complication: Complication,
                                           maxSet: Int, using rng: inout G) -> Ask {
        if isBoss {   // The Authenticator demands a graded 9+
            var a = Ask(kind: .grade); a.gradeMin = 9; return a
        }
        let mult = complication.askMultiplier
        let deck: [AskKind] = [.cash, .cash, .cash, .value, .grade, .grade, .set, .set, .handover, .evolution]
        var kind = deck.randomElement(using: &rng) ?? .cash

        // Evolution needs a feasible 2-stage line in range; it's also too fiddly
        // for the opening Leads (two specific cards on a thin Energy budget), so
        // fall back to cash before Lead 3 or when no line fits.
        let duos = CardDatabase.evolutionLines.values.filter { $0.count == 2 && ($0.first?.set ?? 99) <= maxSet }
        if kind == .evolution && (duos.isEmpty || leadIndex <= 2) { kind = .cash }

        var a = Ask(kind: kind)
        switch kind {
        case .cash:
            a.amount = (Economy.cashAsk(lead: leadIndex) * mult / 10).rounded() * 10
        case .value:
            a.amount = max(30, (Economy.valueAsk(lead: leadIndex) * mult / 5).rounded() * 5)
        case .grade:
            a.gradeMin = min(5 + leadIndex, 9)
        case .handover:
            if leadIndex <= 2 { a.requireRare = true }
            else if Bool.random(using: &rng) { a.requireFoil = true }
            else { a.gradeMin = 8 }
        case .set:
            a.setId = Int.random(in: 1...max(1, maxSet), using: &rng)
            let base = min(2 + leadIndex, 5)
            a.count = max(2, min(6, Int((Double(base) * mult).rounded())))
        case .evolution:
            if let line = duos.randomElement(using: &rng), let head = line.first {
                a.lineId = head.lineId
            } else { a.kind = .cash; a.amount = Economy.cashAsk(lead: leadIndex) }
        }
        return a
    }

    // MARK: Route options — 2–3 branches (or the Score)

    func makeLeadOptions<G: RandomNumberGenerator>(nextIndex: Int, totalLeads: Int, trainer: TrainerKind,
                                                   maxSet: Int, using rng: inout G) -> [LeadOption] {
        if nextIndex >= totalLeads {   // the final Lead is the Score
            let e = energyBudget(complication: .none, isBoss: false, trainer: trainer) + Economy.scoreEnergyBonus
            return [LeadOption(ask: Ask(kind: .cash), complication: .none,
                               energyBudget: e, bonus: .cash(0), isScore: true)]
        }
        if nextIndex % 4 == 0 {        // a boss Lead every 4th
            let comp = Complication.authenticator
            let e = energyBudget(complication: comp, isBoss: true, trainer: trainer)
            let ask = makeAsk(leadIndex: nextIndex, isBoss: true, complication: comp, maxSet: maxSet, using: &rng)
            return [LeadOption(ask: ask, complication: comp, energyBudget: e, bonus: .energy(3))]
        }
        let count = Int.random(in: 2...3, using: &rng)
        let compDeck: [Complication] = [.none, .none, .none, .coldSnap, .backlog, .counterfeits, .rush, .bullMarket]
        return (0..<count).map { _ in
            let comp = compDeck.randomElement(using: &rng) ?? .none
            let ask = makeAsk(leadIndex: nextIndex, isBoss: false, complication: comp, maxSet: maxSet, using: &rng)
            let e = energyBudget(complication: comp, isBoss: false, trainer: trainer)
            let bonuses: [RouteBonus] = [.cash((Economy.cashAsk(lead: nextIndex) * 0.4 / 5).rounded() * 5),
                                         .energy(2), .freeItem]
            return LeadOption(ask: ask, complication: comp, energyBudget: e,
                              bonus: bonuses.randomElement(using: &rng) ?? .energy(2))
        }
    }

    func makeDraft<G: RandomNumberGenerator>(trainer: TrainerKind, using rng: inout G) -> [DraftOption] {
        let size = trainer == .curator ? Economy.curatorDraftSize : Economy.draftSize
        return (0..<size).map { _ in
            if Int.random(in: 0..<4, using: &rng) == 0 {
                return DraftOption(kind: .energy(Economy.draftEnergyChunk))
            }
            return DraftOption(kind: .item(ItemKind.allCases.randomElement(using: &rng) ?? .loupe))
        }
    }

    func makeBazaar<G: RandomNumberGenerator>(using rng: inout G) -> [ItemKind] {
        Array(ItemKind.bazaarOrder.shuffled(using: &rng).prefix(Economy.bazaarSlots))
    }
}

// MARK: - ChaseCore: Hunt lifecycle

extension ChaseCore {

    var hasActiveRun: Bool { run != nil }

    mutating func startHunt<G: RandomNumberGenerator>(grail: Grail, trainer: TrainerKind,
                                                      using rng: inout G) {
        meta.lifetime.huntsStarted += 1
        let total = Economy.huntLeads(tier: grail.tier)
        // Rip ceiling: the Grail's own set (so its card is obtainable), floored at
        // the tier ceiling so even a set-agnostic easy Grail can rip Set 1.
        let maxSet = max(grail.setId, Economy.grailMaxSet(tier: grail.tier))
        var cash = meta.stake
        if trainer == .financier { cash += Economy.financierBonusStake }
        var items: [ItemKind] = []
        if trainer == .grader  { items.append(.loupe) }
        if trainer == .curator { items.append(ChaseCore.randomPassiveItem(using: &rng)) }

        let firstAsk = makeAsk(leadIndex: 1, isBoss: false, complication: .none, maxSet: maxSet, using: &rng)
        let e1 = energyBudget(complication: .none, isBoss: false, trainer: trainer)
        let lead = Lead(index: 1, ask: firstAsk, energyBudget: e1, complication: .none, isScore: total == 1)

        var r = RunState(grail: grail, trainer: trainer, maxSet: maxSet, cash: cash, lead: lead, totalLeads: total)
        r.energy = e1
        r.items = items
        r.route = makeLeadOptions(nextIndex: 2, totalLeads: total, trainer: trainer, maxSet: maxSet, using: &rng)
        run = r
    }

    // MARK: Working a Lead — rip / sell / grade / items

    @discardableResult
    mutating func ripPack<G: RandomNumberGenerator>(set: Int, using rng: inout G) -> [CardInstance]? {
        guard var r = run, r.phase == .working, set >= 1, set <= r.maxSet else { return nil }
        let price = Economy.packPrice(set: set)
        let free = (r.trainer == .speculator && !r.freeFirstPackUsed)
        if free {
            r.freeFirstPackUsed = true
        } else {
            guard r.energy >= 1, r.cash >= price else { return nil }
            r.energy -= 1
            r.cash -= price
        }
        let pack = ChaseCore.makePack(set: set, foilChance: ChaseCore.foilChance(r),
                                      whale: r.hasPassive(.whale), packSearch: r.packSearchArmed, using: &rng)
        r.packSearchArmed = false
        r.stock += pack
        meta.lifetime.packsRipped += 1
        meta.lifetime.ultrasPulled += pack.filter { $0.card.rarity == .ultra }.count
        run = r
        checkPullDiscoveries()
        return pack
    }

    @discardableResult
    mutating func sell(instanceId: UUID) -> Double? {
        guard var r = run, let idx = r.stock.firstIndex(where: { $0.id == instanceId }) else { return nil }
        let inst = r.stock[idx]
        let v = ChaseCore.sellbackRate(r, for: inst) * inst.currentValue
        r.stock.remove(at: idx)
        r.cash += v
        run = r
        return v
    }

    /// Sell every copy except the single best (by value) of each card — the AI's
    /// "dump duplicates" move, mirroring v1's `sellDuplicates`.
    @discardableResult
    mutating func sellDuplicates() -> (count: Int, proceeds: Double) {
        guard let r0 = run else { return (0, 0) }
        var count = 0; var proceeds = 0.0
        for (_, copies) in Dictionary(grouping: r0.stock, by: { $0.cardId }) where copies.count > 1 {
            let extras = copies.sorted { $0.currentValue > $1.currentValue }.dropFirst()
            for e in extras { if let v = sell(instanceId: e.id) { count += 1; proceeds += v } }
        }
        return (count, proceeds)
    }

    static func appraised(_ g: Int) -> Int {
        let up = min(g + 1, 10)
        return Economy.gradeMultiplier(up) >= Economy.gradeMultiplier(g) ? up : g
    }

    @discardableResult
    mutating func grade<G: RandomNumberGenerator>(instanceId: UUID, using rng: inout G) -> Int? {
        guard var r = run, let idx = r.stock.firstIndex(where: { $0.id == instanceId }) else { return nil }
        let inst = r.stock[idx]
        guard inst.card.rarity.canBeGraded, inst.grade == nil else { return nil }
        let fee = ChaseCore.gradeFeeNow(r, set: inst.card.set)
        guard r.cash >= fee else { return nil }
        r.cash -= fee
        var g = Economy.rollGrade(using: &rng)
        if r.hasPassive(.appraiser) { g = ChaseCore.appraised(g) }
        r.stock[idx].grade = g
        if g >= 9 { r.gradedNinePlus += 1 }
        meta.lifetime.cardsGraded += 1
        let foil = r.stock[idx].foil
        run = r
        checkGradeDiscoveries(grade: g, foil: foil)
        return g
    }

    @discardableResult
    mutating func useItem<G: RandomNumberGenerator>(_ kind: ItemKind, targetInstanceId: UUID?,
                                                    using rng: inout G) -> Bool {
        guard var r = run, !kind.isPassive, let itemIdx = r.items.firstIndex(of: kind) else { return false }
        func targetIndex() -> Int? { targetInstanceId.flatMap { id in r.stock.firstIndex(where: { $0.id == id }) } }
        var gradedTo: Int? = nil; var gradedFoil = false
        switch kind {
        case .holoPress:
            guard let t = targetIndex() else { return false }
            r.stock[t].foil = true
        case .fastTrackGrade:
            guard let t = targetIndex(), r.stock[t].card.rarity.canBeGraded, r.stock[t].grade == nil else { return false }
            var g = max(Economy.fastTrackGradeFloor, Economy.rollGrade(using: &rng))
            if r.hasPassive(.appraiser) { g = ChaseCore.appraised(g) }
            r.stock[t].grade = g
            if g >= 9 { r.gradedNinePlus += 1 }
            meta.lifetime.cardsGraded += 1
            gradedTo = g; gradedFoil = r.stock[t].foil
        case .packSearch:
            r.packSearchArmed = true
        case .marketTip:
            r.cash += Economy.marketTipPayout(lead: r.lead.index)
        case .counterfeit:
            guard let t = targetIndex() else { return false }
            r.stock.append(CardInstance(cardId: r.stock[t].cardId))
        case .polish:
            guard let t = targetIndex(), let g = r.stock[t].grade else { return false }
            r.stock[t].grade = min(g + 2, 10)
            gradedTo = r.stock[t].grade; gradedFoil = r.stock[t].foil
        default:
            return false
        }
        r.items.remove(at: itemIdx)
        run = r
        if let g = gradedTo { checkGradeDiscoveries(grade: g, foil: gradedFoil) }
        return true
    }

    // MARK: Ask evaluation & advancing

    func askSatisfied() -> Bool {
        guard let r = run else { return false }
        if r.lead.isScore { return canLandGrail() }
        return r.lead.ask.isSatisfied(cash: r.cash, stock: r.stock)
    }

    func canLandGrail() -> Bool {
        guard let r = run, r.lead.isScore else { return false }
        return r.grail.isHeld(in: r.stock) && r.cash >= r.grail.price
    }

    /// Heuristic "no way forward" flag for the UI/AI: at a non-Score Lead with the
    /// Ask unmet, out of Energy and cash for a pack, no free pack, and no one-shot
    /// left to change the picture.
    var hardBust: Bool {
        guard let r = run, r.phase == .working, !r.lead.isScore, !askSatisfied() else { return false }
        if r.trainer == .speculator && !r.freeFirstPackUsed { return false }
        if r.energy > 0 && r.cash >= Economy.packPrice(set: 1) { return false }
        if r.items.contains(where: { !$0.isPassive }) { return false }
        return true
    }

    @discardableResult
    mutating func runDownLead<G: RandomNumberGenerator>(using rng: inout G) -> Bool {
        guard var r = run, r.phase == .working, !r.lead.isScore,
              r.lead.ask.isSatisfied(cash: r.cash, stock: r.stock) else { return false }
        if r.lead.ask.consumesCard {   // Handover: surrender the worst qualifying card
            if let victim = r.stock.enumerated().filter({ r.lead.ask.cardQualifies($0.element) })
                .min(by: { $0.element.currentValue < $1.element.currentValue })?.offset {
                r.stock.remove(at: victim)
            }
        }
        if r.hasPassive(.stipend) { r.cash += Double(r.uniqueCount) * Economy.stipendPerUnique }
        r.leadsRunDown += 1
        r.renownBanked += Economy.renownPerLead
        meta.lifetime.leadsRunDown += 1
        r.draft = makeDraft(trainer: r.trainer, using: &rng)
        r.phase = .draft
        run = r
        award(.firstLead)
        checkSetMaster()
        return true
    }

    // MARK: Draft → Bazaar → Route

    @discardableResult
    mutating func pickDraft<G: RandomNumberGenerator>(id: UUID, using rng: inout G) -> Bool {
        guard var r = run, r.phase == .draft, let opt = r.draft.first(where: { $0.id == id }) else { return false }
        switch opt.kind {
        case .item(let k):   r.items.append(k)
        case .energy(let e): r.pendingEnergyBonus += e
        }
        r.draft = []
        r.bazaarOffers = makeBazaar(using: &rng)
        r.phase = .bazaar
        run = r
        return true
    }

    func rerollCost(_ r: RunState) -> Double {
        var c = meta.baseRerollCost
        if r.trainer == .financier { c -= Economy.financierRerollDiscount }
        c += Double(r.rerollsUsed) * 5
        return max(Economy.rerollFloor, c)
    }
    func currentRerollCost() -> Double { run.map(rerollCost) ?? meta.baseRerollCost }

    @discardableResult
    mutating func bazaarBuy(_ kind: ItemKind) -> Bool {
        guard var r = run, r.phase == .bazaar, r.bazaarOffers.contains(kind) else { return false }
        let price = Economy.itemPrice(kind)
        guard r.cash >= price else { return false }
        r.cash -= price
        r.items.append(kind)
        if let i = r.bazaarOffers.firstIndex(of: kind) { r.bazaarOffers.remove(at: i) }
        run = r
        return true
    }

    @discardableResult
    mutating func rerollBazaar<G: RandomNumberGenerator>(using rng: inout G) -> Bool {
        guard var r = run, r.phase == .bazaar else { return false }
        let cost = rerollCost(r)
        guard r.cash >= cost else { return false }
        r.cash -= cost
        r.rerollsUsed += 1
        r.bazaarOffers = makeBazaar(using: &rng)
        run = r
        return true
    }

    @discardableResult
    mutating func leaveBazaar() -> Bool {
        guard var r = run, r.phase == .bazaar else { return false }
        r.phase = .route
        run = r
        return true
    }

    @discardableResult
    mutating func chooseRoute<G: RandomNumberGenerator>(optionId: UUID, using rng: inout G) -> Bool {
        guard var r = run, r.phase == .route, let opt = r.route.first(where: { $0.id == optionId }) else { return false }
        switch opt.bonus {
        case .cash(let x):   r.cash += x
        case .energy(let e): r.pendingEnergyBonus += e
        case .freeItem:      r.items.append(ItemKind.allCases.randomElement(using: &rng) ?? .loupe)
        }
        let nextIndex = r.lead.index + 1
        r.lead = Lead(index: nextIndex, ask: opt.ask, energyBudget: opt.energyBudget,
                      complication: opt.complication, isScore: opt.isScore)
        r.energy = opt.energyBudget + r.pendingEnergyBonus
        r.pendingEnergyBonus = 0
        r.freeFirstPackUsed = false
        r.phase = .working
        r.route = makeLeadOptions(nextIndex: nextIndex + 1, totalLeads: r.totalLeads,
                                  trainer: r.trainer, maxSet: r.maxSet, using: &rng)
        run = r
        if opt.isScore && r.grail.setId >= 4 { award(.deepChase) }
        return true
    }

    // MARK: Score & ending

    @discardableResult
    mutating func landGrail() -> HuntSummary? {
        guard var r = run, r.lead.isScore, canLandGrail() else { return nil }
        r.cash -= r.grail.price
        r.leadsRunDown += 1
        r.renownBanked += Economy.renownPerLead
        meta.lifetime.leadsRunDown += 1
        r.phase = .won
        run = r
        award(.firstGrail)
        return endHunt(won: true)
    }

    @discardableResult
    mutating func giveUp() -> HuntSummary {
        run?.phase = .bust
        return endHunt(won: false)
    }

    private mutating func endHunt(won: Bool) -> HuntSummary {
        guard let r = run else {
            return HuntSummary(won: won, grailHeadline: "", leadsRunDown: 0, renownEarned: 0,
                               cardsDeposited: 0, newDiscoveries: [], binderUnique: meta.binderUnique)
        }
        // Deposit the best (by quality) copy of each held card into the Binder.
        var deposited = 0
        for (_, copies) in Dictionary(grouping: r.stock, by: { $0.cardId }) {
            if let best = copies.max(by: {
                BinderCopy(foil: $0.foil, grade: $0.grade).quality < BinderCopy(foil: $1.foil, grade: $1.grade).quality
            }), meta.deposit(best) { deposited += 1 }
        }
        checkLifetimeDiscoveries()   // may award (adds to run.renownBanked) — do before tallying

        let r2 = run!   // award() mutated run.renownBanked / newDiscoveries
        var earned = r2.renownBanked
        if won { earned += Economy.grailBounty(tier: r2.grail.tier) }
        meta.renown += earned
        meta.lifetime.renownEarned += earned
        if won {
            meta.lifetime.huntsWon += 1
            meta.grailsLanded.append(GrailRecord(headline: r2.grail.headline, tier: r2.grail.tier))
        }
        meta.lifetime.bestBinderUnique = max(meta.lifetime.bestBinderUnique, meta.binderUnique)

        let summary = HuntSummary(won: won, grailHeadline: r2.grail.headline, leadsRunDown: r2.leadsRunDown,
                                  renownEarned: earned, cardsDeposited: deposited,
                                  newDiscoveries: r2.newDiscoveries, binderUnique: meta.binderUnique)
        run = nil
        return summary
    }

    // MARK: Discoveries

    private mutating func award(_ d: Discovery) {
        guard !meta.discoveries.contains(d) else { return }
        meta.discoveries.insert(d)
        let reward = Economy.discoveryRenown(d)
        if run != nil {
            run!.newDiscoveries.append(d)
            run!.renownBanked += reward
        } else {
            meta.renown += reward
            meta.lifetime.renownEarned += reward
        }
        if let t = d.unlocksTrainer { meta.unlockTrainer(t) }
    }

    private mutating func checkPullDiscoveries() {
        guard let r = run else { return }
        if r.maxCopiesOfAnyCard() >= 8 { award(.hoarder) }
        if meta.lifetime.ultrasPulled >= 10 { award(.ultraHunter) }
    }

    private mutating func checkGradeDiscoveries(grade: Int, foil: Bool) {
        if let r = run, r.gradedNinePlus >= 3 { award(.aceGrader) }
        if foil && grade == 10 { award(.gemHolo) }
    }

    private mutating func checkSetMaster() {
        guard let r = run else { return }
        let owned = Set(r.stock.map { $0.cardId })
        for s in 1...CardDatabase.setCount {
            let setCards = CardDatabase.cards(inSet: s)
            if !setCards.isEmpty && setCards.allSatisfy({ owned.contains($0.id) }) { award(.setMaster); break }
        }
    }

    private mutating func checkLifetimeDiscoveries() {
        if meta.binderUnique >= 100 { award(.centurion) }
        if meta.binderUnique >= CardDatabase.all.count { award(.masterCollector) }
    }
}
