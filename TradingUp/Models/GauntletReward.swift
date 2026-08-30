import Foundation

// MARK: - Win reward

/// One offered Extended-Art reward. The durable prize is the **art unlock** for
/// `cardId`; the copy itself arrives as a guaranteed **foil** (§14.6). Extended
/// Art is purely cosmetic, so the option carries no value beyond the foil copy —
/// the Binder still keeps the highest-value copy per card across both modes.
struct GauntletRewardOption: Identifiable, Equatable {
    let id = UUID()
    let cardId: String

    /// The reward is a Foil Extended Art copy — a guaranteed foil is the sweetener.
    var instance: CardInstance { CardInstance(cardId: cardId, foil: true) }
    var card: Card { CardDatabase.byId[cardId] ?? .unknown(id: cardId) }
    var rarity: Rarity { card.rarity }
}

/// Builds the reward a cleared run offers. This is pure, seeded logic so the
/// harness and tests can exercise the weighting, promotion and consolation rules
/// exactly. Applying a chosen option (mark the art earned + fold the foil copy
/// into the value-best record) is the Binder's job, done by the state layer.
enum GauntletReward {

    /// What a win pays out.
    enum Payout: Equatable {
        /// Choose one of these Foil Extended Art cards (§14.6's choose-1-of-3).
        case extendedArt([GauntletRewardOption])
        /// The whole catalogue's Extended Art is already earned — pay a
        /// cash-and-Catalyst consolation instead (resolved by the state layer).
        case consolation
    }

    /// Rarity ladder used when a tier's rarity is fully earned and the pull
    /// promotes to the next rarity up.
    static let rarityLadder: [Rarity] = [.common, .uncommon, .rare, .ultra]

    /// Generate the payout for clearing `tier`. Options are drawn at the tier's
    /// reward rarity (Easy → common, Medium → uncommon, Hard → rare/ultra),
    /// **weighted toward cards whose Extended Art is still unearned**. If every
    /// card at that rarity is already earned the pull **promotes** to the next
    /// rarity up; if the entire catalogue is earned it returns `.consolation`.
    ///
    /// `ownedCardIds` are the cards already banked in the Binder. When the rolled
    /// rarity still has an unearned card the player *doesn't own yet*, the row is
    /// guaranteed to include at least one such **brand-new** card, so a win can
    /// always grow the collection when there's room to — never offering only fresh
    /// art on Sprytes already owned while a genuinely new one waits at that rarity.
    static func payout<G: RandomNumberGenerator>(tier: GauntletTier,
                                                 earnedExtendedArt earned: Set<String>,
                                                 ownedCardIds owned: Set<String> = [],
                                                 count: Int = GauntletEconomy.rewardOptionCount,
                                                 using rng: inout G) -> Payout {
        let rolled = GauntletEconomy.rewardRarity(tier, using: &rng)
        guard var idx = rarityLadder.firstIndex(of: rolled) else { return .consolation }

        while idx < rarityLadder.count {
            let rarity = rarityLadder[idx]
            let pool = CardDatabase.all.filter { $0.rarity == rarity }
            let unearned = pool.filter { !earned.contains($0.id) }

            // Promote only when *every* card at this rarity is already earned.
            if unearned.isEmpty {
                idx += 1
                continue
            }

            let shuffledUnearned = unearned.shuffled(using: &rng)
            var chosen: [Card] = []

            // Guarantee at least one brand-new card (one not yet in the Binder) when
            // the unearned pool holds one, so the shuffle can't crowd it out with
            // re-art of already-owned Sprytes.
            if let firstNew = shuffledUnearned.first(where: { !owned.contains($0.id) }) {
                chosen.append(firstNew)
            }
            // Fill the rest from the unearned pool, then pad with earned dupes of the
            // same rarity only if fewer than `count` unearned remain (so a
            // near-complete rarity still offers a full row).
            for c in shuffledUnearned where chosen.count < count {
                if !chosen.contains(where: { $0.id == c.id }) { chosen.append(c) }
            }
            if chosen.count < count {
                let earnedPool = pool.filter { earned.contains($0.id) }.shuffled(using: &rng)
                chosen.append(contentsOf: earnedPool.prefix(count - chosen.count))
            }
            return .extendedArt(chosen.map { GauntletRewardOption(cardId: $0.id) })
        }

        return .consolation
    }

    /// Whether every card's Extended Art has been earned — the catalogue is
    /// complete and future wins pay the consolation.
    static func isCatalogueComplete(earnedExtendedArt earned: Set<String>) -> Bool {
        earned.count >= CardDatabase.all.count && !CardDatabase.all.isEmpty
    }
}
