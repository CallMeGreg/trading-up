import Foundation

enum Collector: String, CaseIterable, Codable {
    case mira, rowan, tess

    var name: String {
        switch self {
        case .mira: return "Mira"
        case .rowan: return "Rowan"
        case .tess: return "Tess"
        }
    }

    var specialty: String {
        switch self {
        case .mira: return "Starter collections"
        case .rowan: return "Evolution families"
        case .tess: return "Missing-card trades"
        }
    }
}

enum CollectorGoal: Codable, Equatable, Hashable, Identifiable {
    case request(String)
    case trade(String)

    var id: String {
        switch self {
        case .request(let id): return "request:\(id)"
        case .trade(let id): return "trade:\(id)"
        }
    }
}

struct CollectorProgress: Codable, Equatable {
    var completedRequestIDs: Set<String> = []
    var tradesCompletedBySet: [Int: Int] = [:]
    var trackedGoals: [CollectorGoal] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        completedRequestIDs = try c.decodeIfPresent(Set<String>.self, forKey: .completedRequestIDs) ?? []
        tradesCompletedBySet = try c.decodeIfPresent([Int: Int].self, forKey: .tradesCompletedBySet) ?? [:]
        trackedGoals = try c.decodeIfPresent([CollectorGoal].self, forKey: .trackedGoals) ?? []
    }

    var requestsCompleted: Int { completedRequestIDs.count }
    var tradesCompleted: Int { tradesCompletedBySet.values.reduce(0, +) }
}

enum CollectorEconomy {
    static let maximumTrackedGoals = 2
    static let requestsPerCollector = 3
    static let tradesPerSet = 2
    static let starterRewardMultiplier = 0.5
    static let familyRewardMultiplier = 1.0
}

struct CollectorRequirement: Identifiable {
    let id: String
    let label: String
    let cardIDs: Set<String>
    let count: Int
    let distinct: Bool
    var card: Card? = nil
    var rarity: Rarity? = nil
}

struct CollectorDeal: Identifiable {
    let goal: CollectorGoal
    let collector: Collector
    let set: Int
    let title: String
    let requirements: [CollectorRequirement]
    let cashReward: Double
    let rewardCard: Card?
    let sequence: Int
    let total: Int

    var id: String { goal.id }
    var requiredCount: Int { requirements.reduce(0) { $0 + $1.count } }
}

private enum CollectorCatalog {
    static func rarityRequirement(_ rarity: Rarity, count: Int, set: Int) -> CollectorRequirement {
        let plural: String
        switch rarity {
        case .common: plural = "commons"
        case .uncommon: plural = "uncommons"
        case .rare: plural = "rares"
        case .ultra: plural = "ultra rares"
        }
        return CollectorRequirement(id: rarity.rawValue,
                                    label: count == 1 ? "1 \(rarity.display.lowercased())" : "\(count) different \(plural)",
                                    cardIDs: Set(CardDatabase.cards(inSet: set).filter { $0.rarity == rarity }.map(\.id)),
                                    count: count, distinct: true, rarity: rarity)
    }

    static let requests: [Int: [CollectorDeal]] = Dictionary(uniqueKeysWithValues: (1...CardDatabase.setCount).map { set in
        let lines = CardDatabase.evolutionLines.values
            .filter { $0.first?.set == set && $0.count == 3 }.sorted { $0[0].id < $1[0].id }
        let deals = [Collector.mira, .rowan].flatMap { collector in
            (0..<CollectorEconomy.requestsPerCollector).compactMap { step -> CollectorDeal? in
                let requirements: [CollectorRequirement]
                let title: String
                let reward: Double
                if collector == .mira {
                    requirements = [rarityRequirement(.common, count: 3 + step, set: set)]
                    title = ["First binder", "Growing collection", "Collector's gift"][step]
                    reward = Economy.packPrice(set: set) * CollectorEconomy.starterRewardMultiplier
                } else {
                    guard lines.indices.contains(step) else { return nil }
                    requirements = lines[step].prefix(2).map { card in
                        CollectorRequirement(id: card.id, label: card.name, cardIDs: [card.id],
                                             count: 1, distinct: true, card: card, rarity: card.rarity)
                    }
                    title = "\(lines[step][0].name)'s family"
                    reward = Economy.packPrice(set: set) * CollectorEconomy.familyRewardMultiplier
                }
                return CollectorDeal(goal: .request("\(set)-\(collector.rawValue)-\(step)"),
                                     collector: collector, set: set, title: title,
                                     requirements: requirements, cashReward: reward, rewardCard: nil,
                                     sequence: step + 1, total: CollectorEconomy.requestsPerCollector)
            }
        }
        return (set, deals)
    })

    static let requestsByGoal: [CollectorGoal: CollectorDeal] =
        Dictionary(uniqueKeysWithValues: requests.values.flatMap { $0 }.map { ($0.goal, $0) })
}

struct CollectorRequirementProgress: Identifiable {
    let requirement: CollectorRequirement
    let instances: [CardInstance]
    var id: String { requirement.id }
    var count: Int { instances.count }
    var isComplete: Bool { count == requirement.count }
}

struct CollectorPreview: Identifiable {
    let deal: CollectorDeal
    let requirements: [CollectorRequirementProgress]
    var id: String { deal.id }
    var supplied: [CardInstance] { requirements.flatMap(\.instances) }
    var suppliedIDs: Set<UUID> { Set(supplied.map(\.id)) }
    var isReady: Bool { requirements.allSatisfy(\.isComplete) }
    var collectedCount: Int { requirements.reduce(0) { $0 + $1.count } }
    var missingCount: Int { deal.requiredCount - collectedCount }
    var sellValue: Double { supplied.reduce(0) { $0 + $1.sellValue } }
}

struct CollectorReceipt: Identifiable {
    let id = UUID()
    let deal: CollectorDeal
    let supplied: [CardInstance]
    let received: CardInstance?
    let bonuses: [BonusEvent]
}

enum CollectorError: LocalizedError, Equatable {
    case unavailable
    case trackingFull
    case missingCopies
    case changedOffer
    case lockedSet
    case finishPack
    case finishDeal
    case couldNotSave

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "This offer is no longer available. Your cards have not been changed."
        case .trackingFull:
            return "You can track two goals. Untrack one to make room; its offer will still be here."
        case .missingCopies:
            return "You still need more spare cards. Only ungraded, non-foil duplicates can go to collectors."
        case .changedOffer:
            return "Your available copies changed. Review the deal again before confirming."
        case .lockedSet:
            return "This set needs the full-game unlock before you can make collector deals."
        case .finishPack:
            return "Finish your pack summary before making a collector deal."
        case .finishDeal:
            return "Close the deal receipt before making another collector deal."
        case .couldNotSave:
            return "Your progress couldn't be saved, so no cards, cash, or tracked goals were changed. Please try again."
        }
    }
}

extension GameCore {
    func collectorRequests(inSet set: Int) -> [CollectorDeal] {
        guard (1...CardDatabase.setCount).contains(set), isUnlocked(set: set) else { return [] }
        return [Collector.mira, .rowan].compactMap { collector in
            CollectorCatalog.requests[set]?.first { deal in
                guard deal.collector == collector, case .request(let id) = deal.goal else { return false }
                return !collectors.completedRequestIDs.contains(id)
            }
        }
    }

    func collectorTradeTargets(inSet set: Int) -> [Card] {
        guard (1...CardDatabase.setCount).contains(set), isUnlocked(set: set),
              collectorTradesRemaining(inSet: set) > 0 else { return [] }
        let owned = uniqueOwnedIds
        return CardDatabase.cards(inSet: set).filter { !owned.contains($0.id) }.sorted {
            if $0.rarity != $1.rarity { return $0.rarity.order > $1.rarity.order }
            return $0.number < $1.number
        }
    }

    func collectorTradesRemaining(inSet set: Int) -> Int {
        max(0, CollectorEconomy.tradesPerSet - max(0, collectors.tradesCompletedBySet[set, default: 0]))
    }

    func collectorDeal(for goal: CollectorGoal) -> CollectorDeal? {
        switch goal {
        case .request:
            guard let request = CollectorCatalog.requestsByGoal[goal],
                  collectorRequests(inSet: request.set).contains(where: { $0.goal == goal }) else { return nil }
            return request
        case .trade(let id):
            guard let card = CardDatabase.card(id), isUnlocked(set: card.set), !owns(id),
                  collectorTradesRemaining(inSet: card.set) > 0 else { return nil }
            var requirements = [CollectorCatalog.rarityRequirement(.common, count: 3, set: card.set)]
            if card.rarity.order >= Rarity.uncommon.order {
                requirements.append(CollectorCatalog.rarityRequirement(.uncommon,
                                                       count: card.rarity == .uncommon ? 1 : 2,
                                                       set: card.set))
            }
            if card.rarity == .ultra {
                requirements.append(CollectorCatalog.rarityRequirement(.rare, count: 2, set: card.set))
            }
            return CollectorDeal(goal: goal, collector: .tess, set: card.set,
                                 title: "Trade for \(card.name)", requirements: requirements,
                                 cashReward: 0, rewardCard: card,
                                 sequence: CollectorEconomy.tradesPerSet - collectorTradesRemaining(inSet: card.set) + 1,
                                 total: CollectorEconomy.tradesPerSet)
        }
    }

    var collectorEligibleExtras: [CardInstance] {
        Dictionary(grouping: instances, by: \.cardId).values.flatMap { copies -> [CardInstance] in
            guard copies.count > 1 else { return [] }
            return copies.sorted(by: Self.collectorKeeperOrder).dropFirst().filter { !$0.foil && $0.grade == nil }
        }.sorted {
            if $0.currentValue != $1.currentValue { return $0.currentValue < $1.currentValue }
            if $0.cardId != $1.cardId { return $0.cardId < $1.cardId }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private static func collectorKeeperOrder(_ a: CardInstance, _ b: CardInstance) -> Bool {
        // Stable ties keep the earlier copy, matching the pack summary and bulk sale.
        a.currentValue > b.currentValue
    }

    var collectorTrackedPreviews: [CollectorPreview] {
        guard !collectors.trackedGoals.isEmpty else { return [] }
        var available = collectorEligibleExtras
        return collectors.trackedGoals.compactMap { goal in
            guard let deal = collectorDeal(for: goal) else { return nil }
            let preview = allocateCollectorCopies(to: deal, from: available)
            available.removeAll { preview.suppliedIDs.contains($0.id) }
            return preview
        }
    }

    var collectorReservedInstanceIDs: Set<UUID> {
        Set(collectorTrackedPreviews.flatMap { $0.supplied.map(\.id) })
    }

    func collectorReservation(for instance: CardInstance) -> CollectorDeal? {
        collectorTrackedPreviews.first { $0.suppliedIDs.contains(instance.id) }?.deal
    }

    func collectorPreview(for goal: CollectorGoal, respectingReservations: Bool = true) -> CollectorPreview? {
        guard let deal = collectorDeal(for: goal) else { return nil }
        let tracked = respectingReservations ? collectorTrackedPreviews : []
        if let preview = tracked.first(where: { $0.deal.goal == goal }) {
            return preview
        }
        let reserved = Set(tracked.flatMap { $0.supplied.map(\.id) })
        return allocateCollectorCopies(to: deal, from: collectorEligibleExtras.filter { !reserved.contains($0.id) })
    }

    mutating func setCollectorGoalTracked(_ goal: CollectorGoal, tracked: Bool) throws {
        if !tracked {
            collectors.trackedGoals.removeAll { $0 == goal }
            return
        }
        refreshCollectorGoals()
        guard collectorDeal(for: goal) != nil else { throw CollectorError.unavailable }
        guard !collectors.trackedGoals.contains(goal) else { return }
        guard collectors.trackedGoals.count < CollectorEconomy.maximumTrackedGoals else {
            throw CollectorError.trackingFull
        }
        collectors.trackedGoals.append(goal)
    }

    mutating func completeCollectorDeal(_ goal: CollectorGoal, expectedInstanceIDs: Set<UUID>) throws -> CollectorReceipt {
        guard let preview = collectorPreview(for: goal) else { throw CollectorError.unavailable }
        guard preview.isReady else { throw CollectorError.missingCopies }
        guard preview.suppliedIDs == expectedInstanceIDs else { throw CollectorError.changedOffer }
        let deal = preview.deal
        instances.removeAll { expectedInstanceIDs.contains($0.id) }
        cash += deal.cashReward
        stats.moneyEarned += deal.cashReward
        let received = deal.rewardCard.map { CardInstance(cardId: $0.id) }
        if let received {
            instances.append(received)
            stats.peakCardValue = max(stats.peakCardValue, received.currentValue)
        }
        switch goal {
        case .request(let id): collectors.completedRequestIDs.insert(id)
        case .trade: collectors.tradesCompletedBySet[deal.set, default: 0] += 1
        }
        collectors.trackedGoals.removeAll { $0 == goal }
        let bonuses = checkBonuses()
        return CollectorReceipt(deal: deal, supplied: preview.supplied, received: received, bonuses: bonuses)
    }

    mutating func refreshCollectorGoals() {
        guard !collectors.trackedGoals.isEmpty else { return }
        var seen: Set<CollectorGoal> = []
        let valid = collectors.trackedGoals.filter {
            collectorDeal(for: $0) != nil && seen.insert($0).inserted
        }
        collectors.trackedGoals = Array(valid.prefix(CollectorEconomy.maximumTrackedGoals))
    }

    func hasAvailableCollectorDeal(setLimit: Int = CardDatabase.setCount) -> Bool {
        for set in 1...max(1, min(setLimit, CardDatabase.setCount)) where isUnlocked(set: set) {
            let requests = collectorRequests(inSet: set).map(\.goal)
            // Requirements depend on rarity, not the target's individual identity.
            let targets = collectorTradeTargets(inSet: set)
            let trades = Rarity.allCases.compactMap { rarity in
                targets.first { $0.rarity == rarity }.map { CollectorGoal.trade($0.id) }
            }
            if (requests + trades).contains(where: {
                collectorPreview(for: $0, respectingReservations: false)?.isReady == true
            }) {
                return true
            }
        }
        return false
    }

    private func allocateCollectorCopies(to deal: CollectorDeal, from copies: [CardInstance]) -> CollectorPreview {
        var available = copies
        let progress = deal.requirements.map { requirement in
            var selected: [CardInstance] = []
            var identities: Set<String> = []
            for copy in available where requirement.cardIDs.contains(copy.cardId) {
                guard !requirement.distinct || !identities.contains(copy.cardId) else { continue }
                selected.append(copy)
                identities.insert(copy.cardId)
                if selected.count == requirement.count { break }
            }
            let ids = Set(selected.map(\.id))
            available.removeAll { ids.contains($0.id) }
            return CollectorRequirementProgress(requirement: requirement, instances: selected)
        }
        return CollectorPreview(deal: deal, requirements: progress)
    }
}
