import Foundation

// The Chase (v2.0) verification harness. Mirrors tools/verify/main.swift: it is
// the play-test. It exercises the pure engine (ChaseCore + friends) across many
// seeds and two contrasting play styles, asserting: no soft-locks or infinite
// loops, no invariant violations (negative cash/energy, phase desync), every Ask
// kind and Grail tier is reachable and winnable, meta-progression accrues, the
// Binder deposit rule is monotonic, saves round-trip, and the difficulty curve
// lands in a sane band (weak play busts often, strong play wins more).

// MARK: - Deterministic RNG

struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(_ seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

var failures = 0
func check(_ cond: Bool, _ msg: String) {
    if cond { print("  ✓ \(msg)") } else { print("  ✗ FAIL: \(msg)"); failures += 1 }
}

var invViolations = 0
func inv(_ cond: Bool, _ msg: @autoclosure () -> String) {
    if !cond {
        invViolations += 1
        if invViolations <= 12 { print("  ✗ INVARIANT: \(msg())") }
    }
}

// Assert engine invariants at every observable step.
func assertInvariants(_ core: ChaseCore) {
    guard let r = core.run else { return }
    inv(r.cash >= -0.001, "cash went negative: \(r.cash)")
    inv(r.energy >= 0, "energy went negative: \(r.energy)")
    inv(r.leadsRunDown <= r.totalLeads, "leadsRunDown \(r.leadsRunDown) > totalLeads \(r.totalLeads)")
    inv(r.lead.index >= 1 && r.lead.index <= r.totalLeads, "lead index \(r.lead.index) out of 1...\(r.totalLeads)")
    for i in r.stock { inv(CardDatabase.exists(i.cardId), "stock holds unknown card \(i.cardId)") }
}

// MARK: - Auto-player

enum Style { case reckless, thoughtful }

func canRip(_ r: RunState, set: Int) -> Bool {
    if r.trainer == .speculator && !r.freeFirstPackUsed { return true }
    return r.energy >= 1 && r.cash >= Economy.packPrice(set: set)
}

func firstUngradedGradeable(_ r: RunState) -> CardInstance? {
    r.stock.first { $0.card.rarity.canBeGraded && $0.grade == nil }
}

// One productive action toward the current (non-Score) Ask. Returns false when no
// move can change the picture — the caller then busts out gracefully.
func autoStep(_ core: inout ChaseCore, _ style: Style, _ rng: inout SeededRNG) -> Bool {
    guard let r = core.run else { return false }
    let ask = r.lead.ask
    switch ask.kind {
    case .cash:      return stepCash(&core, style, &rng)
    case .value:     return stepGradeOrValue(&core, wantGrade: 1, style, &rng)
    case .grade:     return stepGradeOrValue(&core, wantGrade: ask.gradeMin, style, &rng)
    case .handover:  return stepHandover(&core, ask, style, &rng)
    case .set:       return stepSet(&core, ask, &rng)
    case .evolution: return stepEvolution(&core, ask, &rng)
    }
}

func raiseCashBySelling(_ core: inout ChaseCore, style: Style) -> Bool {
    guard let r = core.run else { return false }
    let (n, _) = core.sellDuplicates()
    if n > 0 { return true }
    if let victim = r.stock.min(by: { $0.currentValue < $1.currentValue }) {
        return core.sell(instanceId: victim.id) != nil
    }
    return false
}

func stepCash(_ core: inout ChaseCore, _ style: Style, _ rng: inout SeededRNG) -> Bool {
    guard let r = core.run else { return false }
    if style == .thoughtful, let g = firstUngradedGradeable(r),
       core.gradeFeeNow(set: g.card.set) <= r.cash * 0.4 {
        if core.grade(instanceId: g.id, using: &rng) != nil { return true }
    }
    if raiseCashBySelling(&core, style: style) { return true }
    if r.items.contains(.marketTip) { return core.useItem(.marketTip, targetInstanceId: nil, using: &rng) }
    if canRip(r, set: min(r.maxSet, 1)) { return core.ripPack(set: min(r.maxSet, 1), using: &rng) != nil }
    return false
}

func stepGradeOrValue(_ core: inout ChaseCore, wantGrade: Int, _ style: Style, _ rng: inout SeededRNG) -> Bool {
    guard let r = core.run else { return false }
    // Polish a graded card that's close to the target.
    if wantGrade >= 2, r.items.contains(.polish),
       let c = r.stock.first(where: { ($0.grade ?? 0) < wantGrade && ($0.grade ?? 0) >= wantGrade - 2 }) {
        return core.useItem(.polish, targetInstanceId: c.id, using: &rng)
    }
    // Value asks (wantGrade <= 1) want one *valuable* card: grade the highest-base
    // gradeable, or foil it with a Holo Press. A grade ask wants any card at the
    // bar, so the first gradeable is fine.
    let gradeable = r.stock.filter { $0.card.rarity.canBeGraded && $0.grade == nil }
    let pick = wantGrade <= 1 ? gradeable.max(by: { $0.currentValue < $1.currentValue }) : gradeable.first
    if wantGrade <= 1, r.items.contains(.holoPress),
       let c = r.stock.filter({ !$0.foil }).max(by: { $0.currentValue < $1.currentValue }) {
        return core.useItem(.holoPress, targetInstanceId: c.id, using: &rng)
    }
    if let g = pick {
        if r.items.contains(.fastTrackGrade) {
            return core.useItem(.fastTrackGrade, targetInstanceId: g.id, using: &rng)
        }
        if core.gradeFeeNow(set: g.card.set) <= r.cash {
            return core.grade(instanceId: g.id, using: &rng) != nil
        }
    }
    // Need a gradeable card: rip the cheapest set (every pack yields one hit).
    if canRip(r, set: min(r.maxSet, 1)) { return core.ripPack(set: min(r.maxSet, 1), using: &rng) != nil }
    if raiseCashBySelling(&core, style: style) { return true }
    return false
}

func stepHandover(_ core: inout ChaseCore, _ ask: Ask, _ style: Style, _ rng: inout SeededRNG) -> Bool {
    guard let r = core.run else { return false }
    if ask.requireFoil {
        if r.items.contains(.holoPress), let c = r.stock.first {
            return core.useItem(.holoPress, targetInstanceId: c.id, using: &rng)
        }
        if canRip(r, set: min(r.maxSet, 1)) { return core.ripPack(set: min(r.maxSet, 1), using: &rng) != nil }
        return false
    }
    if ask.gradeMin != 0 {
        return stepGradeOrValue(&core, wantGrade: ask.gradeMin, style, &rng)
    }
    // requireRare (or plain): any pack's hit is a rare or better.
    if canRip(r, set: min(r.maxSet, 1)) { return core.ripPack(set: min(r.maxSet, 1), using: &rng) != nil }
    return false
}

func stepSet(_ core: inout ChaseCore, _ ask: Ask, _ rng: inout SeededRNG) -> Bool {
    guard let r = core.run else { return false }
    let set = max(1, min(r.maxSet, ask.setId))
    if canRip(r, set: set) { return core.ripPack(set: set, using: &rng) != nil }
    // Short on cash for the target set: liquidate to afford a pack.
    if r.energy >= 1, let victim = r.stock.min(by: { $0.currentValue < $1.currentValue }) {
        return core.sell(instanceId: victim.id) != nil
    }
    return false
}

func stepEvolution(_ core: inout ChaseCore, _ ask: Ask, _ rng: inout SeededRNG) -> Bool {
    guard let r = core.run else { return false }
    let line = CardDatabase.line(ask.lineId)
    let set = max(1, min(r.maxSet, line.first?.set ?? 1))
    if canRip(r, set: set) { return core.ripPack(set: set, using: &rng) != nil }
    if r.energy >= 1, let victim = r.stock.min(by: { $0.currentValue < $1.currentValue }) {
        return core.sell(instanceId: victim.id) != nil
    }
    return false
}

// A thoughtful player banks the Grail card on the last Lead before the Score,
// while still flush, then holds it in. Spends down only to a price reserve so the
// Score is winnable — arriving already holding the Grail is the skilled line.
func buildGrailEarly(_ core: inout ChaseCore, _ rng: inout SeededRNG) {
    var steps = 0
    while let r = core.run, r.phase == .working, !r.lead.isScore, core.askSatisfied() {
        steps += 1; if steps > 80 { return }
        if r.grail.isHeld(in: r.stock) { return }
        if r.lead.index < r.totalLeads - 1 { return }   // only the penultimate Lead
        if r.energy <= 1 { return }
        if r.cash < r.grail.price + 25 { return }        // keep enough to pay at the Score
        if !makeGrailMatch(&core, .thoughtful, &rng) { return }
    }
}

// Work one non-Score Lead to completion (run down) or bust.
func workLead(_ core: inout ChaseCore, _ style: Style, _ rng: inout SeededRNG, _ steps: inout Int) {
    while let r = core.run, r.phase == .working, !r.lead.isScore {
        steps += 1
        if steps > 4000 { _ = core.giveUp(); return }
        assertInvariants(core)
        if core.askSatisfied() {
            if style == .thoughtful { buildGrailEarly(&core, &rng) }
            _ = core.runDownLead(using: &rng); return
        }
        if !autoStep(&core, style, &rng) { _ = core.giveUp(); return }
    }
}

// MARK: - Between-Lead decisions

func grailItemPrefs(_ g: Grail) -> [ItemKind] {
    var out: [ItemKind] = []
    if g.requireFoil { out += [.holoPress, .gilder] }
    if g.gradeMin != 0 { out += [.polish, .fastTrackGrade, .loupe, .appraiser] }
    if g.minValue != 0 { out += [.appraiser, .holoPress] }
    return out
}

func pickDraft(_ core: inout ChaseCore, _ style: Style, _ rng: inout SeededRNG) {
    guard let r = core.run, let first = r.draft.first else { return }
    if style == .reckless { _ = core.pickDraft(id: first.id, using: &rng); return }
    let prefs: [ItemKind] = grailItemPrefs(r.grail) + [.appraiser, .loupe, .whale, .marketTip]
    func rank(_ o: DraftOption) -> Int {
        switch o.kind {
        case .item(let k): return prefs.firstIndex(of: k).map { 100 - $0 } ?? 10
        case .energy:      return r.energy <= 1 ? 60 : 20
        }
    }
    let best = r.draft.max { rank($0) < rank($1) } ?? first
    _ = core.pickDraft(id: best.id, using: &rng)
}

func doBazaar(_ core: inout ChaseCore, _ style: Style, _ rng: inout SeededRNG) {
    guard let r = core.run else { return }
    if style == .reckless {
        if r.rerollsUsed == 0, r.cash >= core.currentRerollCost() { _ = core.rerollBazaar(using: &rng) }
        if let r2 = core.run,
           let buy = r2.bazaarOffers.filter({ Economy.itemPrice($0) <= r2.cash })
            .max(by: { Economy.itemPrice($0) < Economy.itemPrice($1) }) {
            _ = core.bazaarBuy(buy)
        }
        _ = core.leaveBazaar()
        return
    }
    // Thoughtful: buy at most one key item, keep a reserve toward the Grail price.
    let reserve = r.grail.price * 0.35
    let prefs = grailItemPrefs(r.grail)
    if let want = prefs.first(where: { r.bazaarOffers.contains($0) }),
       r.cash - Economy.itemPrice(want) >= reserve {
        _ = core.bazaarBuy(want)
    }
    _ = core.leaveBazaar()
}

func chooseRoute(_ core: inout ChaseCore, _ style: Style, _ rng: inout SeededRNG) {
    guard let r = core.run, let first = r.route.first else { return }
    if r.route.count == 1 { _ = core.chooseRoute(optionId: first.id, using: &rng); return }
    if style == .reckless { _ = core.chooseRoute(optionId: first.id, using: &rng); return }
    func score(_ o: LeadOption) -> Double {
        var s = 0.0
        if o.complication == .none { s += 5 }
        s -= o.complication.askMultiplier
        switch o.ask.kind {
        case .cash, .handover: s += 3
        case .value, .grade:   s += 2
        case .set, .evolution: s += 0
        }
        switch o.bonus {
        case .cash(let x):   s += min(3, x / 40)
        case .energy(let e): s += Double(e) * 0.7
        case .freeItem:      s += 2
        }
        return s
    }
    let best = r.route.max { score($0) < score($1) } ?? first
    _ = core.chooseRoute(optionId: best.id, using: &rng)
}

// MARK: - Score (final Lead)

func makeGrailMatch(_ core: inout ChaseCore, _ style: Style, _ rng: inout SeededRNG) -> Bool {
    guard let r = core.run else { return false }
    let g = r.grail
    func baseMatch(_ i: CardInstance) -> Bool {
        if !g.cardId.isEmpty && i.cardId != g.cardId { return false }
        if g.setId != 0 && i.card.set != g.setId { return false }
        if let rr = g.rarity, i.card.rarity != rr { return false }
        return true
    }
    let cands = r.stock.filter(baseMatch)
    if g.requireFoil, !cands.contains(where: { $0.foil }) {
        if r.items.contains(.holoPress), let c = cands.first ?? r.stock.first {
            return core.useItem(.holoPress, targetInstanceId: c.id, using: &rng)
        }
    }
    if g.gradeMin != 0 {
        if r.items.contains(.polish),
           let c = cands.first(where: { ($0.grade ?? 0) < g.gradeMin && ($0.grade ?? 0) >= g.gradeMin - 2 }) {
            return core.useItem(.polish, targetInstanceId: c.id, using: &rng)
        }
        if let c = cands.first(where: { $0.grade == nil && $0.card.rarity.canBeGraded }) {
            if r.items.contains(.fastTrackGrade) { return core.useItem(.fastTrackGrade, targetInstanceId: c.id, using: &rng) }
            if core.gradeFeeNow(set: c.card.set) <= r.cash { return core.grade(instanceId: c.id, using: &rng) != nil }
        }
    }
    if g.minValue != 0, let c = cands.max(by: { $0.currentValue < $1.currentValue }) {
        if c.grade == nil, c.card.rarity.canBeGraded, core.gradeFeeNow(set: c.card.set) <= r.cash {
            return core.grade(instanceId: c.id, using: &rng) != nil
        }
        if !c.foil, r.items.contains(.holoPress) { return core.useItem(.holoPress, targetInstanceId: c.id, using: &rng) }
    }
    // Fallback: rip the Grail's set to acquire raw material to work with.
    let ripSet = max(1, min(r.maxSet, g.setId == 0 ? 1 : g.setId))
    if canRip(r, set: ripSet) { return core.ripPack(set: ripSet, using: &rng) != nil }
    return false
}

func sellForGrailPrice(_ core: inout ChaseCore) -> Bool {
    guard let r = core.run else { return false }
    let g = r.grail
    let keep = r.stock.first(where: { g.matches($0) })?.id
    var sold = false
    for inst in r.stock where inst.id != keep {
        if core.sell(instanceId: inst.id) != nil { sold = true }
    }
    return sold
}

func workScore(_ core: inout ChaseCore, _ style: Style, _ rng: inout SeededRNG, _ steps: inout Int) {
    while let r = core.run, r.lead.isScore {
        steps += 1
        if steps > 4000 { _ = core.giveUp(); return }
        assertInvariants(core)
        if core.canLandGrail() { _ = core.landGrail(); return }
        let g = r.grail
        if !g.isHeld(in: r.stock) {
            if makeGrailMatch(&core, style, &rng) { continue }
            let set = max(1, min(r.maxSet, g.setId == 0 ? 1 : g.setId))
            if canRip(r, set: set) { _ = core.ripPack(set: set, using: &rng); continue }
            _ = core.giveUp(); return
        }
        if r.cash >= g.price { continue }        // will land on the next loop
        if sellForGrailPrice(&core) { continue }
        _ = core.giveUp(); return
    }
}

// MARK: - Play a whole Hunt

func pickGrail(_ offers: [Grail], _ style: Style, _ rng: inout SeededRNG) -> Grail {
    switch style {
    case .thoughtful:
        return offers.count > 1 && Int.random(in: 0..<4, using: &rng) == 0 ? offers[1] : offers[0]
    case .reckless:
        return offers.last ?? offers[0]
    }
}

func pickTrainer(_ meta: MetaState, _ grail: Grail, _ style: Style) -> TrainerKind {
    let avail = meta.availableTrainers
    if style == .reckless { return .digger }
    if grail.gradeMin != 0 || grail.minValue != 0, avail.contains(.grader) { return .grader }
    if grail.requireFoil, avail.contains(.foilhunter) { return .foilhunter }
    if avail.contains(.financier) { return .financier }
    return avail.contains(.digger) ? .digger : (avail.first ?? .digger)
}

// Diagnostics (printed, not asserted) to locate where Hunts die.
struct Diag {
    var plays = 0, reachedScore = 0, heldAtScore = 0, wins = 0
    var leadsSum = 0, totalSum = 0, bustLead: [Int: Int] = [:]
    var scoreCashSum = 0.0, scorePriceSum = 0.0, scoreN = 0
    var bustKind: [String: Int] = [:]
}
var diag = Diag()
var diagOn = false

@discardableResult
func playHunt(_ core: inout ChaseCore, _ style: Style, _ rng: inout SeededRNG) -> Bool {
    let wonBefore = core.meta.lifetime.huntsWon
    let offers = core.grailOffers(using: &rng)
    let grail = pickGrail(offers, style, &rng)
    let trainer = pickTrainer(core.meta, grail, style)
    core.startHunt(grail: grail, trainer: trainer, using: &rng)

    var everScore = false, heldAtScore = false
    var lastCash = 0.0, price = grail.price, lastLead = 0, total = core.run?.totalLeads ?? 0
    var lastAskKind = "cash"
    var steps = 0
    while core.run != nil {
        steps += 1
        if steps > 20000 { inv(false, "hunt exceeded step budget (soft-lock)"); _ = core.giveUp(); break }
        assertInvariants(core)
        if let r = core.run {
            lastLead = r.lead.index
            if r.lead.isScore {
                everScore = true
                if r.grail.isHeld(in: r.stock) { heldAtScore = true }
                lastCash = r.cash
            } else {
                lastAskKind = "\(r.lead.ask.kind)"
            }
        }
        switch core.run!.phase {
        case .working:
            if core.run!.lead.isScore { workScore(&core, style, &rng, &steps) }
            else { workLead(&core, style, &rng, &steps) }
        case .draft:  pickDraft(&core, style, &rng)
        case .bazaar: doBazaar(&core, style, &rng)
        case .route:  chooseRoute(&core, style, &rng)
        case .won, .bust: _ = core.giveUp()
        }
    }
    let won = core.meta.lifetime.huntsWon > wonBefore
    if diagOn {
        diag.plays += 1; diag.totalSum += total
        if everScore { diag.reachedScore += 1 }
        if heldAtScore { diag.heldAtScore += 1 }
        if won { diag.wins += 1 }
        if everScore { diag.scoreCashSum += lastCash; diag.scorePriceSum += price; diag.scoreN += 1 }
        if !won {
            diag.bustLead[lastLead, default: 0] += 1
            if !everScore { diag.bustKind[lastAskKind, default: 0] += 1 }
        }
    }
    return won
}

// MARK: - Simulation driver

struct StyleResult { var hunts = 0; var wins = 0; var busts = 0 }

func simulate(style: Style, hunts: Int, baseSeed: UInt64, veteran: Bool) -> StyleResult {
    var res = StyleResult()
    for i in 0..<hunts {
        var rng = SeededRNG(baseSeed &+ UInt64(i) &* 0x1000193)
        var core = ChaseCore()
        if veteran {
            for t in TrainerKind.allCases { core.meta.unlockTrainer(t) }
            core.meta.upgrades["stake"] = 2
            core.meta.upgrades["energy"] = 2
        }
        let won = playHunt(&core, style, &rng)
        res.hunts += 1
        if won { res.wins += 1 } else { res.busts += 1 }
    }
    return res
}

// MARK: - Run checks

print("== Chase data integrity ==")
do {
    var rng = SeededRNG(0xC0FFEE)
    let core = ChaseCore()
    var easyPaths = Set<String>(), tiersSeen = Set<GrailTier>()
    var priceBad = 0, cardBad = 0
    for _ in 0..<3000 {
        let offers = core.grailOffers(using: &rng)
        if offers.count != 3 { priceBad += 1; break }
        for (idx, g) in offers.enumerated() {
            tiersSeen.insert(g.tier)
            if g.price <= 0 || g.headline.isEmpty { priceBad += 1 }
            if g.tier == .hard, !g.cardId.isEmpty, !CardDatabase.exists(g.cardId) { cardBad += 1 }
            if idx == 0 {
                if g.requireFoil { easyPaths.insert("foil") }
                else if g.gradeMin > 0 { easyPaths.insert("grade") }
                else { easyPaths.insert("value") }
            }
            let ceil = max(g.setId, Economy.grailMaxSet(tier: g.tier))
            inv(g.setId <= ceil, "grail setId \(g.setId) exceeds rip ceiling \(ceil)")
        }
        inv(offers[0].price <= offers[2].price, "easy grail pricier than hard")
    }
    check(priceBad == 0, "every Grail has a positive price and a headline")
    check(cardBad == 0, "every Hard Grail names a real card")
    check(tiersSeen == Set(GrailTier.allCases), "all three Grail tiers generated")
    check(easyPaths.count == 3, "all three Easy-Grail paths (foil/grade/value) appear")
}

print("\n== Ask generation ==")
do {
    var rng = SeededRNG(7)
    let core = ChaseCore()
    var kinds = Set<AskKind>()
    var bad = 0
    for lead in 1...6 {
        for _ in 0..<4000 {
            let comp = Complication.allCases.randomElement(using: &rng)!
            let a = core.makeAsk(leadIndex: lead, isBoss: false, complication: comp, maxSet: 3, using: &rng)
            kinds.insert(a.kind)
            switch a.kind {
            case .cash, .value: if a.amount <= 0 { bad += 1 }
            case .grade:        if a.gradeMin < 1 || a.gradeMin > 10 { bad += 1 }
            case .set:          if a.setId < 1 || a.setId > 3 || a.count < 2 { bad += 1 }
            case .evolution:    if CardDatabase.line(a.lineId).count < 2 { bad += 1 }
            case .handover:     break
            }
        }
    }
    check(bad == 0, "every generated Ask has valid parameters")
    check(kinds == Set(AskKind.allCases), "all six Ask kinds are generated")
    let boss = core.makeAsk(leadIndex: 4, isBoss: true, complication: .authenticator, maxSet: 3, using: &rng)
    check(boss.kind == .grade && boss.gradeMin == 9, "boss Ask demands graded 9+")
}

print("\n== Economy sanity ==")
do {
    check((1...5).allSatisfy { Economy.cashAsk(lead: $0 + 1) > Economy.cashAsk(lead: $0) }, "cash Asks rise per Lead")
    check(Economy.grailMaxSet(tier: .easy) == 1 && Economy.grailMaxSet(tier: .hard) == 3, "rip ceiling scales with tier")
    check(ItemKind.allCases.allSatisfy { Economy.itemPrice($0) > 0 }, "every Item has a positive price")
    check(Economy.huntLeads(tier: .easy) < Economy.huntLeads(tier: .hard), "hard Hunts are longer")
}

print("\n== Binder deposit is monotonic ==")
do {
    var meta = MetaState()
    let id = CardDatabase.all[0].id
    _ = meta.deposit(CardInstance(cardId: id, foil: false, grade: 5))
    let q1 = meta.binder[id]!.quality
    _ = meta.deposit(CardInstance(cardId: id, foil: true, grade: 10))
    let q2 = meta.binder[id]!.quality
    _ = meta.deposit(CardInstance(cardId: id, foil: false, grade: 2))
    let q3 = meta.binder[id]!.quality
    check(q2 > q1, "a better copy replaces a worse one")
    check(q3 == q2, "a worse copy never downgrades the Binder slot")
    check(meta.binderUnique == 1, "one unique slot after three deposits of one card")
}

print("\n== Save round-trip & 2.0 migration ==")
do {
    var core = ChaseCore()
    var rng = SeededRNG(99)
    playHunt(&core, .thoughtful, &rng)
    let data = try! JSONEncoder().encode(ChaseSaveFile(core: core))
    let back = try! JSONDecoder().decode(ChaseSaveFile.self, from: data)
    check(back.core.meta.binderUnique == core.meta.binderUnique, "MetaState survives a save round-trip")
    check(back.schemaVersion == 3, "Chase save envelope is v3")

    var legacy = GameCore()
    legacy.instances = [CardInstance(cardId: CardDatabase.all[0].id, foil: true, grade: 9),
                        CardInstance(cardId: CardDatabase.all[1].id)]
    var fresh = ChaseCore()
    for inst in legacy.instances { fresh.meta.deposit(inst) }
    check(fresh.meta.binderUnique == 2, "2.0 reset seeds the Binder from a v1 collection")
}

print("\n== Play-test: many Hunts, two styles ==")
diagOn = true
do {
    var core = ChaseCore()
    for t in TrainerKind.allCases { core.meta.unlockTrainer(t) }
    core.meta.upgrades["stake"] = 2; core.meta.upgrades["energy"] = 2
    var rng = SeededRNG(0xD1A6)
    for _ in 0..<500 { playHunt(&core, .thoughtful, &rng) }
    let d = diag
    print(String(format: "  [diag] thoughtful ×%d: reachedScore %d (%.0f%%), heldGrail@score %d, wins %d",
                 d.plays, d.reachedScore, pct(d.reachedScore, d.plays), d.heldAtScore, d.wins))
    if d.scoreN > 0 {
        print(String(format: "  [diag] at Score: avg cash $%.0f vs avg price $%.0f",
                     d.scoreCashSum / Double(d.scoreN), d.scorePriceSum / Double(d.scoreN)))
    }
    let busts = d.bustLead.sorted { $0.key < $1.key }.map { "L\($0.key):\($0.value)" }.joined(separator: " ")
    print("  [diag] bust-at-lead histogram: \(busts)")
    let byKind = d.bustKind.sorted { $0.value > $1.value }.map { "\($0.key):\($0.value)" }.joined(separator: " ")
    print("  [diag] pre-Score bust-by-Ask: \(byKind)")
    print(String(format: "  [diag] avg totalLeads %.1f", Double(d.totalSum) / Double(max(1, d.plays))))
}
diagOn = false
diag = Diag()
let N = 1200
let vetThoughtful = simulate(style: .thoughtful, hunts: N, baseSeed: 0xA11CE, veteran: true)
let vetReckless   = simulate(style: .reckless,   hunts: N, baseSeed: 0xBEEF,  veteran: true)

func pct(_ a: Int, _ b: Int) -> Double { b == 0 ? 0 : Double(a) / Double(b) * 100 }
let winT = pct(vetThoughtful.wins, vetThoughtful.hunts)
let winR = pct(vetReckless.wins, vetReckless.hunts)
let bustR = pct(vetReckless.busts, vetReckless.hunts)
print(String(format: "  thoughtful: %d/%d won (%.1f%%), busts %.1f%%", vetThoughtful.wins, vetThoughtful.hunts, winT, 100 - winT))
print(String(format: "  reckless:   %d/%d won (%.1f%%), busts %.1f%%", vetReckless.wins, vetReckless.hunts, winR, bustR))
print(String(format: "  skill gap: %.1f points", winT - winR))

check(invViolations == 0, "no engine invariant violations across \(2 * N) Hunts")
check(winT >= 45, "thoughtful play wins at least 45% of Hunts")
check(bustR >= 30, "reckless play busts at least 30% of Hunts")
check(winT - winR >= 12, "strategy matters: ≥12-point skill gap")

print("\n== Meta-progression accrues (fresh start) ==")
do {
    var core = ChaseCore()
    var rng = SeededRNG(0x5EED)
    for _ in 0..<40 { playHunt(&core, .thoughtful, &rng) }
    check(core.meta.lifetime.huntsStarted == 40, "every Hunt is counted")
    check(core.meta.renown > 0, "Renown accrues over a fresh career")
    check(core.meta.binderUnique > 0, "the Binder fills over a career")
    let before = core.meta.availableTrainers.count
    var spins = 0
    while core.meta.canUpgrade(.trainerSlot),
          let cost = core.meta.upgradeCost(.trainerSlot), core.meta.renown >= cost, spins < 6 {
        check(core.meta.purchase(.trainerSlot), "Recruit Trainer purchase succeeds when affordable")
        spins += 1
    }
    check(core.meta.availableTrainers.count >= before, "recruited Trainers persist in meta")
}

print("\n\(failures == 0 && invViolations == 0 ? "ALL CHECKS PASSED ✅" : "SOME CHECKS FAILED ❌") (failures: \(failures), invariant violations: \(invViolations))")
exit(failures == 0 && invViolations == 0 ? 0 : 1)
