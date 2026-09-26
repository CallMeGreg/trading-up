import Foundation

enum Collector: String, CaseIterable, Codable {
    case mira, rowan, tess

    var name: String {
        switch self {
        case .mira: return "Matthew"
        case .rowan: return "Emilie"
        case .tess: return "Jonny"
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
    var cashEarned = 0.0

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        completedRequestIDs = try c.decodeIfPresent(Set<String>.self, forKey: .completedRequestIDs) ?? []
        tradesCompletedBySet = try c.decodeIfPresent([Int: Int].self, forKey: .tradesCompletedBySet) ?? [:]
        // Older saves retain completed requests, so their rewards can be recovered.
        cashEarned = try c.decodeIfPresent(Double.self, forKey: .cashEarned)
            ?? completedRequestIDs.reduce(0) {
                $0 + (CollectorCatalog.requestsByGoal[.request($1)]?.cashReward ?? 0)
            }
    }

    var requestsCompleted: Int { completedRequestIDs.count }
    var tradesCompleted: Int { tradesCompletedBySet.values.reduce(0, +) }
}

enum CollectorEconomy {
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
            return "Your progress couldn't be saved, so no cards, cash, or offers were changed. Please try again."
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

    func collectorPreview(for goal: CollectorGoal, excluding instanceIDs: Set<UUID> = []) -> CollectorPreview? {
        guard let deal = collectorDeal(for: goal) else { return nil }
        return allocateCollectorCopies(to: deal, from: collectorEligibleExtras.filter { !instanceIDs.contains($0.id) })
    }

    mutating func completeCollectorDeal(_ goal: CollectorGoal, expectedInstanceIDs: Set<UUID>) throws -> CollectorReceipt {
        guard let preview = collectorPreview(for: goal) else { throw CollectorError.unavailable }
        guard preview.isReady else { throw CollectorError.missingCopies }
        guard preview.suppliedIDs == expectedInstanceIDs else { throw CollectorError.changedOffer }
        let deal = preview.deal
        instances.removeAll { expectedInstanceIDs.contains($0.id) }
        cash += deal.cashReward
        stats.moneyEarned += deal.cashReward
        collectors.cashEarned += deal.cashReward
        let received = deal.rewardCard.map { CardInstance(cardId: $0.id) }
        if let received {
            instances.append(received)
            stats.peakCardValue = max(stats.peakCardValue, received.currentValue)
        }
        switch goal {
        case .request(let id): collectors.completedRequestIDs.insert(id)
        case .trade: collectors.tradesCompletedBySet[deal.set, default: 0] += 1
        }
        let bonuses = checkBonuses()
        return CollectorReceipt(deal: deal, supplied: preview.supplied, received: received, bonuses: bonuses)
    }

    func collectorReadyCount(inSet set: Int) -> Int {
        let requests = collectorRequests(inSet: set).filter {
            collectorPreview(for: $0.goal)?.isReady == true
        }.count
        let targets = collectorTradeTargets(inSet: set)
        // Jonny counts once, regardless of how many missing cards share a bundle.
        let tradeReady = Rarity.allCases.contains { rarity in
            guard let card = targets.first(where: { $0.rarity == rarity }) else { return false }
            return collectorPreview(for: .trade(card.id))?.isReady == true
        }
        return requests + (tradeReady ? 1 : 0)
    }

    func hasAvailableCollectorDeal(setLimit: Int = CardDatabase.setCount) -> Bool {
        (1...max(1, min(setLimit, CardDatabase.setCount))).contains {
            collectorReadyCount(inSet: $0) > 0
        }
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
