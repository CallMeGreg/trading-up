import Foundation

// MARK: - Gauntlet meta progression

/// The durable, cross-run Gauntlet record: how much XP each Trainer has banked
/// (and therefore its level), and which difficulty tiers the player has unlocked.
/// Like the `Binder`, it only ever grows and deliberately outlives any single run,
/// so it lives in its own file (`GauntletProgressStore`) rather than the per-run
/// save. Pure and Foundation-only, like everything under `Models/`.
///
/// Everything decodes leniently and every field is additive (§12): an old
/// progress file — or none at all on first launch — still yields a valid record
/// with Easy unlocked and every Trainer at level 0. See docs/DESIGN.md §14.3/§14.8.
struct GauntletProgress: Codable, Equatable {

    /// Lifetime XP earned per Trainer id. A Trainer's *level* is derived from this
    /// via `GauntletEconomy.trainerLevel(forXP:)`, so there's a single source of
    /// truth and no way for the two to drift out of sync.
    private(set) var xpByTrainer: [String: Int]

    /// The difficulty tiers the player has unlocked. Easy is *always* available
    /// (enforced in `isUnlocked`), so it need not be stored; Medium and Hard are
    /// each earned by clearing the tier before them once.
    private(set) var unlockedTierKeys: Set<String>

    /// The specialist Trainers the player has earned. The "Rookie" (neutral) is
    /// *always* available (enforced in `isTrainerUnlocked`) as the starter, so it
    /// need not be stored; every other Trainer is unlocked by a Gauntlet milestone.
    private(set) var unlockedTrainerKeys: Set<String>

    /// Lifetime Gauntlet stat counters (see `GauntletStat`). Some are running sums
    /// (packs ripped), others high-water marks (widest Showcase). They're the seam
    /// Trainer unlocks read, and — like everything here — only ever grow.
    private(set) var stats: [String: Int]

    /// Whether the player has seen the mode's how-to at least once. Drives the
    /// first-launch explainer; additive so an old file simply shows it once.
    private(set) var hasSeenIntro: Bool

    init(xpByTrainer: [String: Int] = [:],
         unlockedTierKeys: Set<String> = [GauntletTier.easy.rawValue],
         unlockedTrainerKeys: Set<String> = [],
         stats: [String: Int] = [:],
         hasSeenIntro: Bool = false) {
        self.xpByTrainer = xpByTrainer
        self.unlockedTierKeys = unlockedTierKeys
        self.unlockedTrainerKeys = unlockedTrainerKeys
        self.stats = stats
        self.hasSeenIntro = hasSeenIntro
    }

    /// Decode leniently: a missing key falls back to its default rather than
    /// failing the whole decode, so a future additive field can't break an
    /// existing progress file.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        xpByTrainer = try c.decodeIfPresent([String: Int].self, forKey: .xpByTrainer) ?? [:]
        unlockedTierKeys = try c.decodeIfPresent(Set<String>.self, forKey: .unlockedTierKeys)
            ?? [GauntletTier.easy.rawValue]
        unlockedTrainerKeys = try c.decodeIfPresent(Set<String>.self, forKey: .unlockedTrainerKeys) ?? []
        stats = try c.decodeIfPresent([String: Int].self, forKey: .stats) ?? [:]
        hasSeenIntro = try c.decodeIfPresent(Bool.self, forKey: .hasSeenIntro) ?? false
    }

    // MARK: Derived

    /// Lifetime XP banked by a Trainer.
    func xp(forTrainer id: String) -> Int { xpByTrainer[id] ?? 0 }

    /// The Trainer's current level (1…`maxTrainerLevel`), derived from its XP.
    func level(forTrainer id: String) -> Int {
        GauntletEconomy.trainerLevel(forXP: xp(forTrainer: id))
    }

    /// XP still needed for a Trainer's next level, or nil once it's maxed.
    func xpToNextLevel(forTrainer id: String) -> Int? {
        GauntletEconomy.xpToNextLevel(fromXP: xp(forTrainer: id))
    }

    /// Whether a tier is playable. Easy is always unlocked; the rest are earned.
    func isUnlocked(_ tier: GauntletTier) -> Bool {
        tier == .easy || unlockedTierKeys.contains(tier.rawValue)
    }

    /// The unlocked tiers, in ladder order — what the tier picker offers.
    var unlockedTiers: [GauntletTier] {
        GauntletTier.allCases.filter { isUnlocked($0) }.sorted { $0.order < $1.order }
    }

    /// The highest tier the player has unlocked so far.
    var highestUnlocked: GauntletTier { unlockedTiers.last ?? .easy }

    // MARK: Trainers & stats

    /// A lifetime stat's current value (0 if never recorded).
    func stat(_ key: String) -> Int { stats[key] ?? 0 }

    /// Whether a Trainer is selectable. The Rookie is always available as the
    /// starter; every specialist must be earned.
    func isTrainerUnlocked(_ id: String) -> Bool {
        id == Trainer.neutral.id || unlockedTrainerKeys.contains(id)
    }

    /// How close the player is to unlocking a Trainer, for the locked card's
    /// progress line: `(have, need)` clamped so `have` never exceeds `need`.
    func unlockProgress(for trainer: Trainer) -> (have: Int, need: Int)? {
        guard let u = trainer.unlock else { return nil }
        return (min(stat(u.stat), u.threshold), u.threshold)
    }

    // MARK: Mutation

    /// Unlock a tier. Returns `true` if this newly unlocked it (so the caller knows
    /// to persist and can celebrate a first unlock).
    @discardableResult
    mutating func unlock(_ tier: GauntletTier) -> Bool {
        guard !isUnlocked(tier) else { return false }
        return unlockedTierKeys.insert(tier.rawValue).inserted
    }

    /// Mark the how-to explainer as seen. Returns `true` the first time (so the
    /// caller knows to persist).
    @discardableResult
    mutating func markIntroSeen() -> Bool {
        guard !hasSeenIntro else { return false }
        hasSeenIntro = true
        return true
    }

    /// Fold a finished run's stats in — sums accumulate, high-water marks take the
    /// max — then re-evaluate Trainer unlocks. Returns the ids of any Trainers this
    /// newly unlocked, so the UI can celebrate them.
    @discardableResult
    mutating func ingest(_ report: GauntletRunReport) -> [String] {
        stats[GauntletStat.packsRipped, default: 0] += report.packsRipped
        stats[GauntletStat.cardsGraded, default: 0] += report.cardsGraded
        stats[GauntletStat.maxShowcase] = max(stat(GauntletStat.maxShowcase), report.maxShowcase)
        stats[GauntletStat.bestRoundScore] = max(stat(GauntletStat.bestRoundScore), report.bestRoundScore)
        stats[GauntletStat.maxCashHeld] = max(stat(GauntletStat.maxCashHeld), report.maxCashHeld)
        return evaluateTrainerUnlocks()
    }

    /// Unlock any specialist whose milestone the current stats now satisfy. Returns
    /// the newly unlocked ids, roster order.
    @discardableResult
    private mutating func evaluateTrainerUnlocks() -> [String] {
        var newly: [String] = []
        for trainer in Trainer.roster {
            guard let u = trainer.unlock, !isTrainerUnlocked(trainer.id) else { continue }
            if stat(u.stat) >= u.threshold, unlockedTrainerKeys.insert(trainer.id).inserted {
                newly.append(trainer.id)
            }
        }
        return newly
    }

    /// What a single cleared run changed about the meta progression — enough for
    /// the UI to celebrate a level-up or a freshly unlocked tier.
    struct ClearResult: Equatable {
        var xpGained: Int
        var newLevel: Int
        var leveledUp: Bool
        var unlockedTier: GauntletTier?
    }

    /// Bank a run clear: grant the tier's XP to the Trainer and unlock the next
    /// tier up the ladder. Returns a summary of what changed.
    @discardableResult
    mutating func recordClear(trainerId: String, tier: GauntletTier) -> ClearResult {
        let levelBefore = level(forTrainer: trainerId)
        let gained = GauntletEconomy.clearXP(tier)
        xpByTrainer[trainerId, default: 0] += gained
        let levelAfter = level(forTrainer: trainerId)

        var newlyUnlocked: GauntletTier? = nil
        if let next = GauntletTier.allCases.first(where: { $0.requires == tier }), unlock(next) {
            newlyUnlocked = next
        }

        return ClearResult(xpGained: gained,
                           newLevel: levelAfter,
                           leveledUp: levelAfter > levelBefore,
                           unlockedTier: newlyUnlocked)
    }

    /// Bank a *busted* run's partial progress: grant XP for the rounds that were
    /// cleared before the loss (nothing if the player didn't get past round 1) and
    /// do NOT unlock any tier — only a win opens the ladder. Returns what changed so
    /// the loss screen can still celebrate XP and level-ups. (req 3)
    @discardableResult
    mutating func recordLoss(trainerId: String, tier: GauntletTier, roundsCleared: Int) -> ClearResult {
        let levelBefore = level(forTrainer: trainerId)
        let gained = GauntletEconomy.runXP(tier: tier, roundsCleared: roundsCleared, won: false)
        if gained > 0 { xpByTrainer[trainerId, default: 0] += gained }
        let levelAfter = level(forTrainer: trainerId)
        return ClearResult(xpGained: gained,
                           newLevel: levelAfter,
                           leveledUp: levelAfter > levelBefore,
                           unlockedTier: nil)
    }

    /// Drop XP entries for Trainers no longer in the roster — the same load
    /// hygiene the Binder does — so a record written against an older roster
    /// doesn't keep dead ids around. Returns how many entries were removed.
    @discardableResult
    mutating func sanitize() -> Int {
        let before = xpByTrainer.count
        let known = Set(Trainer.roster.map(\.id) + [Trainer.neutral.id])
        xpByTrainer = xpByTrainer.filter { known.contains($0.key) }
        // Only keep tier keys that name a real tier.
        let tierKeys = Set(GauntletTier.allCases.map(\.rawValue))
        unlockedTierKeys = unlockedTierKeys.filter { tierKeys.contains($0) }
        // Drop unlock entries for Trainers no longer in the roster (the Rookie is
        // implicit, never stored here).
        let specialistIds = Set(Trainer.roster.map(\.id))
        unlockedTrainerKeys = unlockedTrainerKeys.filter { specialistIds.contains($0) }
        return before - xpByTrainer.count
    }
}
