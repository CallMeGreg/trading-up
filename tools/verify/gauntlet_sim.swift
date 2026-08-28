import Foundation

// Gauntlet strategy simulation for tools/verify. Declarations only — no
// top-level code (that lives in main.swift). These policies drive `GauntletRun`
// to completion so the harness can assert the difficulty curve statistically,
// exactly as the Classic strategy sims do. See docs/DESIGN.md §14.8.

enum GauntletStyle {
    case optimized   // curates for synergy, grades keepers, banks Catalysts, works the shop
    case careless    // keeps by raw value, never grades, dumps Catalysts, hoards cash
}

struct GauntletSimResult {
    var won = false
    var lost = false
    var clearedRounds = 0
    var finalRound = 1
    var finalPackTier = 1
    var finalSlots = 0
    var finalAppraisal = 0.0
    var finalCash = 0.0
    var catalystsAttuned = 0
    var finalCompleteLines = 0   // complete evolution lines standing in the final Showcase
    var capped = false   // hit the safety iteration cap (should never happen)
}

enum GauntletSim {

    // Expected grade multiplier (~1.50×) — grading a valuable keeper is +EV, so
    // the optimised policy grades when half the value clears the fee.
    static let expectedGradeMult: Double = {
        Economy.gradeTable.reduce(0.0) { $0 + Double($1.odds) / 100.0 * $1.mult }
    }()

    static func weakestByValueIndex(_ cards: [CardInstance]) -> Int? {
        guard !cards.isEmpty else { return nil }
        var wi = 0
        for i in cards.indices where cards[i].currentValue < cards[wi].currentValue { wi = i }
        return wi
    }

    /// How many complete evolution lines stand in `cards` — a diagnostic the harness
    /// prints so we can see how often the optimised policy *completes* a line (vs
    /// hoarding singles), given line-completion is the core skill lever.
    static func completeLines(_ cards: [CardInstance]) -> Int {
        let byLine = Dictionary(grouping: cards.filter { $0.card.stageCount > 1 }, by: { $0.card.lineId })
        return byLine.values.reduce(0) { acc, group in
            acc + (Set(group.map { $0.card.stage }).count == group[0].card.stageCount ? 1 : 0)
        }
    }

    /// How aggressively the optimised policy speculatively holds a *partial* line —
    /// credit toward a completion it hasn't landed yet, so a cheap common isn't
    /// dumped for sticker value while its chain is still assembling. 0 = ignore
    /// partial lines (purely value-greedy); higher = chase completions harder.
    static let lineOptionWeight = 0.75

    /// The optimised policy's private valuation of a *whole* Showcase: the exact
    /// appraisal engine (which already pays the completion bonus for finished lines)
    /// plus a smaller "option value" for lines still assembling — weighted by how
    /// close they are. Because it scores the entire Showcase, evicting a linemate
    /// lowers the score on its own, so the argmax below never breaks a line it's
    /// trying to build.
    static func showcaseScore(_ sc: [CardInstance], evoLineBonus: Double, appraisalMult: Double) -> Double {
        var s = GauntletRun.appraise(sc, evoLineBonus: evoLineBonus, appraisalMult: appraisalMult)
        guard evoLineBonus > 0 else { return s }
        let byLine = Dictionary(grouping: sc.filter { $0.card.stageCount > 1 }, by: { $0.card.lineId })
        for (_, g) in byLine {
            let stageCount = g[0].card.stageCount
            let present = Set(g.map { $0.card.stage }).count
            if present >= 1 && present < stageCount {
                let lineVal = g.reduce(0.0) { $0 + $1.currentValue }
                let progress = Double(present) / Double(stageCount)
                s += evoLineBonus * lineVal * lineOptionWeight * progress * appraisalMult
            }
        }
        return s
    }

    // MARK: Per-pull curation

    static func handleCards<G: RandomNumberGenerator>(_ cards: [CardInstance], style: GauntletStyle, run: inout GauntletRun, rng: inout G) {
        switch style {
        case .optimized:
            // Curate for value *and* evolution lines. Each incoming card either fills
            // an empty slot or is placed where it lifts the Showcase's strategic score
            // the most — a score that credits both finished lines (exactly) and lines
            // still assembling (option value), so the policy will hold a cheap common
            // toward a completion instead of dumping it for a pricier single.
            let elb = run.evoLineBonus
            let am = run.mods.appraisalMult
            for inst in cards.sorted(by: { $0.currentValue > $1.currentValue }) {
                if run.canKeep {
                    run.keep(inst)
                    continue
                }
                // "Sell" keeps the Showcase as-is; each swap trials inst into a slot.
                var bestScore = showcaseScore(run.showcase, evoLineBonus: elb, appraisalMult: am)
                var bestSlot: Int? = nil
                for j in run.showcase.indices {
                    var trial = run.showcase
                    trial[j] = inst
                    let sc = showcaseScore(trial, evoLineBonus: elb, appraisalMult: am)
                    if sc > bestScore { bestScore = sc; bestSlot = j }
                }
                if let j = bestSlot { run.swapIn(inst, at: j) } else { run.sell(inst) }
            }
        case .careless:
            // Fill slots as they come; later only swap on raw sticker value.
            for inst in cards {
                if run.canKeep {
                    run.keep(inst)
                } else if let wi = weakestByValueIndex(run.showcase), inst.currentValue > run.showcase[wi].currentValue {
                    run.swapIn(inst, at: wi)
                } else {
                    run.sell(inst)
                }
            }
        }
    }

    static func handleCatalyst(_ catalyst: Catalyst?, style: GauntletStyle, run: inout GauntletRun) {
        guard let catalyst else { return }
        switch style {
        case .optimized:
            if run.canAttune { run.attune(catalyst) } else { run.sellCatalyst(catalyst) }
        case .careless:
            run.sellCatalyst(catalyst)
        }
    }

    // MARK: Grading

    static func gradeKeepers<G: RandomNumberGenerator>(run: inout GauntletRun, rng: inout G) {
        // Grade ungraded keepers by descending value while it clears the fee EV.
        let order = run.showcase.indices.sorted { run.showcase[$0].currentValue > run.showcase[$1].currentValue }
        for i in order {
            guard run.showcase[i].grade == nil else { continue }
            let v = run.showcase[i].currentValue
            let fee = run.gradeFee(for: run.showcase[i].card)
            if v * (expectedGradeMult - 1) > fee && run.cash >= fee {
                run.gradeShowcaseCard(at: i, using: &rng)
            }
        }
    }

    /// A casual player slabs only the single chase card, and only when it's cheap
    /// insurance — leaving the deeper grading edge (grade *every* keeper) on the table.
    static func gradeTopKeeper<G: RandomNumberGenerator>(run: inout GauntletRun, rng: inout G) {
        guard let i = run.showcase.indices.max(by: { run.showcase[$0].currentValue < run.showcase[$1].currentValue }) else { return }
        guard run.showcase[i].grade == nil else { return }
        let fee = run.gradeFee(for: run.showcase[i].card)
        if run.cash >= fee * 2 { run.gradeShowcaseCard(at: i, using: &rng) }
    }

    // MARK: Shop (between rounds)

    static let optimizedSlotCap = 12

    static func shop(style: GauntletStyle, run: inout GauntletRun) {
        switch style {
        case .optimized:
            var improved = true
            while improved {
                improved = false
                if let set = run.nextLockedPack, let cost = run.packUnlockCost(set), run.cash >= cost {
                    run.unlockPack(set); improved = true; continue
                }
                if run.effectiveSlots < optimizedSlotCap, run.cash >= run.nextSlotCost {
                    run.buySlot(); improved = true; continue
                }
                if run.attunedCatalysts.count >= run.effectiveCatalystSlots,
                   run.cash >= run.nextCatalystSlotCost, run.cash >= run.nextCatalystSlotCost * 2 {
                    run.buyCatalystSlot(); improved = true; continue
                }
            }
        case .careless:
            // Hoards a little less; springs for a pack unlock once it can afford one
            // with a modest buffer — but still ignores slots and Catalyst slots.
            if let set = run.nextLockedPack, let cost = run.packUnlockCost(set), run.cash >= cost * 1.4 {
                run.unlockPack(set)
            }
        }
    }

    // MARK: Full run

    static func simulate<G: RandomNumberGenerator>(tier: GauntletTier, trainer: Trainer, style: GauntletStyle, rng: inout G, trace: Bool = false) -> GauntletSimResult {
        var run = GauntletRun(tier: tier, trainer: trainer)
        var guardCounter = 0
        var result = GauntletSimResult()

        while !run.won && !run.lost {
            guardCounter += 1
            if guardCounter > 2000 { result.capped = true; break }

            while run.ripsLeft > 0 {
                let res = run.rip(using: &rng)
                handleCards(res.cards, style: style, run: &run, rng: &rng)
                handleCatalyst(res.catalyst, style: style, run: &run)
            }
            if style == .optimized { gradeKeepers(run: &run, rng: &rng) }
            else { gradeTopKeeper(run: &run, rng: &rng) }

            let roundBefore = run.round
            let appraisalBefore = run.showcaseAppraisal
            let targetBefore = run.target
            let outcome = run.endRound(using: &rng)
            if trace {
                print(String(format: "    T%@ r%d  appraisal $%.0f / target $%.0f  cash $%.0f  packTier %d  slots %d  cats %d  -> %@",
                             tier.rawValue.prefix(1).uppercased(), roundBefore, appraisalBefore, targetBefore,
                             run.cash, run.packTier, run.effectiveSlots, run.attunedCatalysts.count, String(describing: outcome)))
            }
            if outcome == .cleared { shop(style: style, run: &run) }
        }

        result.won = run.won
        result.lost = run.lost
        result.finalRound = run.round
        result.clearedRounds = run.won ? run.roundsTotal : max(0, run.round - 1)
        result.finalPackTier = run.packTier
        result.finalSlots = run.effectiveSlots
        result.finalAppraisal = run.showcaseAppraisal
        result.finalCash = run.cash
        result.catalystsAttuned = run.attunedCatalysts.count
        result.finalCompleteLines = completeLines(run.showcase)
        return result
    }

    /// Aggregate win/bust rates over many seeded runs.
    static func winRate(tier: GauntletTier, trainer: Trainer, style: GauntletStyle, trials: Int, seed0: UInt64) -> (win: Double, bust: Double, capped: Int, avgCleared: Double, avgLines: Double) {
        var wins = 0, busts = 0, capped = 0, clearedTotal = 0
        var linesTotal = 0
        for s in 0..<trials {
            var rng = SeededRNG(seed0 &+ UInt64(s))
            let r = simulate(tier: tier, trainer: trainer, style: style, rng: &rng)
            if r.capped { capped += 1 }
            else if r.won { wins += 1 }
            else if r.lost { busts += 1 }
            clearedTotal += r.clearedRounds
            linesTotal += r.finalCompleteLines
        }
        return (Double(wins) / Double(trials) * 100,
                Double(busts) / Double(trials) * 100,
                capped,
                Double(clearedTotal) / Double(trials),
                Double(linesTotal) / Double(trials))
    }
}
