import Foundation

enum ClassicSim {
    enum Policy: String, CaseIterable {
        case careless, gradingOnly, requestsOnly, tradesOnly, focused

        var grades: Bool { self == .gradingOnly || self == .focused }
        var requests: Bool { self == .requestsOnly || self == .focused }
        var trades: Bool { self == .tradesOnly || self == .focused }
        var usesCollectors: Bool { requests || trades }
    }

    struct Outcome {
        let won: Bool
        let capped: Bool
        let stranded: Bool
        let packs: Int
        let requests: Int
        let trades: Int
    }

    struct Summary {
        let wins: Int
        let trials: Int
        let capped: Int
        let stranded: Int
        let averagePacks: Double
        let averageRequests: Double
        let averageTrades: Double
        var winPercent: Double { Double(wins) * 100 / Double(trials) }
    }

    static func run(policy: Policy, trials: Int, seed: UInt64) throws -> Summary {
        var outcomes: [Outcome] = []
        for i in 0..<trials {
            outcomes.append(try play(policy: policy, seed: seed &+ UInt64(i)))
        }
        let divisor = Double(trials)
        return Summary(wins: outcomes.filter(\.won).count, trials: trials,
                       capped: outcomes.filter(\.capped).count,
                       stranded: outcomes.filter(\.stranded).count,
                       averagePacks: Double(outcomes.reduce(0) { $0 + $1.packs }) / divisor,
                       averageRequests: Double(outcomes.reduce(0) { $0 + $1.requests }) / divisor,
                       averageTrades: Double(outcomes.reduce(0) { $0 + $1.trades }) / divisor)
    }

    static func play(policy: Policy, seed: UInt64) throws -> Outcome {
        var rng = SeededRNG(seed)
        var core = GameCore()
        func outcome(capped: Bool = false) -> Outcome {
            Outcome(won: core.hasWon, capped: capped, stranded: !core.hasWon && !capped && !core.isGameOver,
                    packs: core.stats.packsOpened,
                    requests: core.collectors.requestsCompleted, trades: core.collectors.tradesCompleted)
        }

        for _ in 0..<5_000 {
            if core.hasWon { return outcome() }
            let incomplete = (1...CardDatabase.setCount).filter {
                core.isUnlocked(set: $0) && core.ownedCount(inSet: $0) < 50
            }
            let target = incomplete.first ?? 1
            if policy.usesCollectors {
                try useCollectors(core: &core, target: target, requests: policy.requests, trades: policy.trades)
                if core.hasWon { return outcome() }
                try trackGoals(core: &core, target: target, requests: policy.requests, trades: policy.trades)
            }
            liquidate(core: &core, grade: policy.grades, rng: &rng)
            if core.cash < Economy.cheapestPackPrice {
                for goal in core.collectors.trackedGoals {
                    try core.setCollectorGoalTracked(goal, tracked: false)
                }
                if policy.usesCollectors {
                    try useCollectors(core: &core, target: target, requests: policy.requests, trades: policy.trades)
                }
                liquidate(core: &core, grade: policy.grades, rng: &rng)
            }
            if core.hasWon { return outcome() }
            guard core.cash >= Economy.cheapestPackPrice else { return outcome() }
            let affordable = incomplete.first { core.cash >= Economy.packPrice(set: $0) } ?? 1
            guard core.buyPack(set: affordable, using: &rng) != nil else {
                throw SimulationError.illegalPurchase
            }
        }
        return outcome(capped: true)
    }

    private static func useCollectors(core: inout GameCore, target: Int, requests useRequests: Bool, trades: Bool) throws {
        for goal in core.collectors.trackedGoals {
            try core.setCollectorGoalTracked(goal, tracked: false)
        }
        for _ in 0..<50 {
            let requests = (useRequests ? Array(1...CardDatabase.setCount) : [])
                .flatMap { core.collectorRequests(inSet: $0) }
                .compactMap { core.collectorPreview(for: $0.goal) }
                .filter(\.isReady)
                .sorted {
                    if $0.deal.cashReward != $1.deal.cashReward { return $0.deal.cashReward > $1.deal.cashReward }
                    return $0.id < $1.id
                }
            if let request = requests.first {
                _ = try core.completeCollectorDeal(request.deal.goal, expectedInstanceIDs: request.suppliedIDs)
                continue
            }
            if trades, let trade = preferredTrade(core: core, set: target),
               let preview = core.collectorPreview(for: trade), preview.isReady {
                _ = try core.completeCollectorDeal(trade, expectedInstanceIDs: preview.suppliedIDs)
                continue
            }
            return
        }
        throw SimulationError.dealLoop
    }

    private static func trackGoals(core: inout GameCore, target: Int, requests useRequests: Bool, trades: Bool) throws {
        let requests = (useRequests ? core.collectorRequests(inSet: target) : [])
            .compactMap { core.collectorPreview(for: $0.goal) }
        let sorted = requests.sorted {
            if $0.missingCount != $1.missingCount { return $0.missingCount < $1.missingCount }
            if $0.deal.cashReward != $1.deal.cashReward { return $0.deal.cashReward > $1.deal.cashReward }
            return $0.id < $1.id
        }
        var goals = sorted.map { $0.deal.goal }
        if trades, let trade = preferredTrade(core: core, set: target) {
            if goals.count >= CollectorEconomy.maximumTrackedGoals {
                goals = [goals[0], trade]
            } else {
                goals.append(trade)
            }
        }
        for goal in goals.prefix(CollectorEconomy.maximumTrackedGoals) {
            try core.setCollectorGoalTracked(goal, tracked: true)
        }
    }

    private static func preferredTrade(core: GameCore, set: Int) -> CollectorGoal? {
        let targets = core.collectorTradeTargets(inSet: set)
        guard let rarity = targets.first?.rarity else { return nil }
        let owned = core.uniqueOwnedIds
        // Public information only: prefer the least likely missing rarity, then
        // a card that completes a displayed family. Never inspect the RNG.
        return targets.filter { $0.rarity == rarity }.sorted { a, b in
            let aCompletes = CardDatabase.evolutionLines[a.lineId]?.allSatisfy { $0.id == a.id || owned.contains($0.id) } ?? false
            let bCompletes = CardDatabase.evolutionLines[b.lineId]?.allSatisfy { $0.id == b.id || owned.contains($0.id) } ?? false
            if aCompletes != bCompletes { return aCompletes }
            return a.id < b.id
        }.first.map { .trade($0.id) }
    }

    private static func liquidate<G: RandomNumberGenerator>(core: inout GameCore, grade: Bool, rng: inout G) {
        let reserved = core.collectorReservedInstanceIDs
        for id in core.uniqueOwnedIds.sorted() {
            let copies = core.instances(of: id).sorted { $0.currentValue > $1.currentValue }
            for extra in copies.dropFirst() where !reserved.contains(extra.id) {
                let fee = Economy.gradeFee(set: extra.card.set)
                if grade, extra.grade == nil, extra.currentValue > fee / (0.5 * Economy.sellbackRate),
                   core.cash >= fee {
                    _ = core.grade(instanceId: extra.id, using: &rng)
                }
                _ = core.sell(instanceId: extra.id)
            }
        }
    }

    private enum SimulationError: Error {
        case illegalPurchase, dealLoop, missingPolicy
    }

    static func verify(trials: Int, seed: UInt64, check: (Bool, String) -> Void) throws {
        print("\n== Classic collector balance (packs-only, seed \(seed)) ==")
        check(FeatureFlags.removeBoosterBoxes, "Classic balance measures the shipped packs-only shop")
        var results: [Policy: Summary] = [:]
        for policy in Policy.allCases {
            let count = policy == .careless || policy == .focused ? trials : min(trials, 200)
            let result = try run(policy: policy, trials: count, seed: seed)
            results[policy] = result
            print(String(format: "  %@: %.1f%% wins (%d/%d), %.1f packs, %.1f requests, %.1f trades",
                         policy.rawValue, result.winPercent, result.wins, result.trials,
                         result.averagePacks, result.averageRequests, result.averageTrades))
            check(result.capped == 0 && result.stranded == 0,
                  "\(policy.rawValue): no capped runs or premature losses while a legal recovery remains")
        }
        guard let focused = results[.focused], let careless = results[.careless] else {
            throw SimulationError.missingPolicy
        }
        check((70...80).contains(focused.winPercent), "focused collector play wins 70-80% (target about 75%)")
        check((5...15).contains(careless.winPercent), "careless cash-out play wins 5-15% (target about 10%)")
        check(focused.winPercent - careless.winPercent >= 60, "planning creates at least a 60-point win-rate gap")
    }
}
