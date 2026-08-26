import Foundation

// MARK: - Binder

/// The player's permanent showcase: one slot per Spryte (card), each holding the
/// single most valuable copy they have *ever* owned of it — across every Classic
/// run and, once it ships, Gauntlet Mode too.
///
/// Where a Classic run is a roguelike that resets on `newGame()`, the Binder is
/// the opposite: it only ever grows. Pull a foil, land a PSA 10, complete a set —
/// the best copy of each Spryte is stamped here for good, so starting a fresh run
/// never feels like it erased your greatest hits.
///
/// Pure and Foundation-only, like everything else under `Models/`: `GameState`
/// owns an instance and feeds it the current collection after each acquisition;
/// the Binder itself just keeps the running maximum per card. It persists to its
/// own file (`BinderStore`), separate from the per-run save, precisely because it
/// has to outlive the run.
struct Binder: Codable, Equatable {

    /// The best (highest market value) copy recorded for each card id. The stored
    /// `CardInstance` is a value snapshot of the winning copy — its foil/grade,
    /// and therefore its `currentValue` — even after that copy is sold or a new
    /// run wipes the collection it came from.
    private(set) var bestByCardId: [String: CardInstance]

    init(bestByCardId: [String: CardInstance] = [:]) {
        self.bestByCardId = bestByCardId
    }

    /// Decode leniently, like `GameCore`/`Stats`: a missing key falls back to its
    /// default rather than failing the whole decode, so a future additive field
    /// can't break an existing binder file.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bestByCardId = try c.decodeIfPresent([String: CardInstance].self, forKey: .bestByCardId) ?? [:]
    }

    // MARK: Recording

    /// Fold a batch of owned copies in, keeping — per card id — whichever copy is
    /// worth the most. Only ever upgrades or fills a slot; it never clears one, so
    /// selling a card or starting a new run leaves the Binder's record intact.
    /// Ids no longer in the catalogue are ignored. Returns `true` if anything
    /// changed, so the caller knows whether it needs to persist.
    @discardableResult
    mutating func record<S: Sequence>(_ instances: S) -> Bool where S.Element == CardInstance {
        var changed = false
        for inst in instances {
            guard CardDatabase.exists(inst.cardId) else { continue }
            if let existing = bestByCardId[inst.cardId] {
                if inst.currentValue > existing.currentValue {
                    bestByCardId[inst.cardId] = inst
                    changed = true
                }
            } else {
                bestByCardId[inst.cardId] = inst
                changed = true
            }
        }
        return changed
    }

    /// Drop any recorded slots whose card id is no longer in the shipped
    /// catalogue — the same load hygiene `GameCore.sanitized()` does — so a binder
    /// written against an older card list doesn't surface placeholder cards.
    /// Returns how many slots were removed.
    @discardableResult
    mutating func sanitize() -> Int {
        let before = bestByCardId.count
        bestByCardId = bestByCardId.filter { CardDatabase.exists($0.key) }
        return before - bestByCardId.count
    }

    // MARK: Derived

    /// The best copy recorded for a card, or `nil` if that slot is still empty.
    func best(for cardId: String) -> CardInstance? { bestByCardId[cardId] }

    /// Whether a Spryte's slot has been filled at least once.
    func hasCard(_ cardId: String) -> Bool { bestByCardId[cardId] != nil }

    /// How many of the catalogue's Spryte slots are filled.
    var filledCount: Int { bestByCardId.count }

    /// Total number of Spryte slots (the whole catalogue).
    var totalSlots: Int { CardDatabase.all.count }

    /// Filled slots within a single set.
    func filledCount(inSet set: Int) -> Int {
        CardDatabase.cards(inSet: set).reduce(0) { $0 + (hasCard($1.id) ? 1 : 0) }
    }

    /// The summed market value of every showcased copy — a headline number for
    /// how strong the all-time collection is.
    var totalValue: Double {
        bestByCardId.values.reduce(0) { $0 + $1.currentValue }
    }

    /// The single most valuable Spryte in the whole binder — the crown jewel.
    var mostValuable: CardInstance? {
        bestByCardId.values.max { $0.currentValue < $1.currentValue }
    }

    /// Whether every Spryte slot has been filled at least once.
    var isComplete: Bool { filledCount >= totalSlots && totalSlots > 0 }
}
