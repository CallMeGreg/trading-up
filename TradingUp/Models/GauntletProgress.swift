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

    /// Which difficulty tiers each Trainer has *cleared*, keyed by Trainer id →
    /// the set of tier rawValues won with that Trainer. The ladder is per-Trainer
    /// (req 4): a Trainer unlocks Medium only once *it* has cleared Easy, and Hard
    /// once *it* has cleared Medium. Easy is always available, so it need not be
    /// stored. Additive: an old file with no entry simply starts every Trainer at
    /// Easy. See docs/DESIGN.md §14.5.
    private(set) var clearedTiersByTrainer: [String: Set<String>]

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
         clearedTiersByTrainer: [String: Set<String>] = [:],
         unlockedTrainerKeys: Set<String> = [],
         stats: [String: Int] = [:],
         hasSeenIntro: Bool = false) {
        self.xpByTrainer = xpByTrainer
        self.clearedTiersByTrainer = clearedTiersByTrainer
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
        clearedTiersByTrainer = try c.decodeIfPresent([String: Set<String>].self, forKey: .clearedTiersByTrainer) ?? [:]
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

    /// Whether a Trainer has already cleared (won) a given tier.
    func hasCleared(_ tier: GauntletTier, trainer id: String) -> Bool {
        clearedTiersByTrainer[id]?.contains(tier.rawValue) ?? false
    }

    /// Whether a tier is playable *with a given Trainer*. Easy is always unlocked;
    /// Medium and Hard require that same Trainer to have cleared the tier below —
    /// the ladder is walked once per Trainer (req 4).
    func isUnlocked(_ tier: GauntletTier, forTrainer id: String) -> Bool {
        guard let required = tier.requires else { return true }   // Easy: always open
        return hasCleared(required, trainer: id)
    }

    /// The tiers a Trainer may start, in ladder order — what its tier picker offers.
    func unlockedTiers(forTrainer id: String) -> [GauntletTier] {
        GauntletTier.allCases.filter { isUnlocked($0, forTrainer: id) }.sorted { $0.order < $1.order }
    }

    /// The highest tier this Trainer has opened so far.
    func highestUnlocked(forTrainer id: String) -> GauntletTier {
        unlockedTiers(forTrainer: id).last ?? .easy
    }

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

    /// Bank a run clear: grant the tier's XP to the Trainer and record that this
    /// Trainer cleared this tier, which opens the next tier *for that Trainer*.
    /// Returns a summary of what changed (the newly opened tier, if any).
    @discardableResult
    mutating func recordClear(trainerId: String, tier: GauntletTier) -> ClearResult {
        let levelBefore = level(forTrainer: trainerId)
        let gained = GauntletEconomy.clearXP(tier)
        xpByTrainer[trainerId, default: 0] += gained
        let levelAfter = level(forTrainer: trainerId)

        // Record the clear for this Trainer; note whether it *newly* opens the next
        // tier up the ladder (so the results screen can celebrate a first unlock).
        let alreadyCleared = hasCleared(tier, trainer: trainerId)
        clearedTiersByTrainer[trainerId, default: []].insert(tier.rawValue)
        var newlyUnlocked: GauntletTier? = nil
        if !alreadyCleared, let next = GauntletTier.allCases.first(where: { $0.requires == tier }) {
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
        // Keep only cleared-tier entries for known Trainers, naming real tiers.
        let tierKeys = Set(GauntletTier.allCases.map(\.rawValue))
        clearedTiersByTrainer = clearedTiersByTrainer
            .filter { known.contains($0.key) }
            .mapValues { $0.filter { tierKeys.contains($0) } }
            .filter { !$0.value.isEmpty }
        // Drop unlock entries for Trainers no longer in the roster (the Rookie is
        // implicit, never stored here).
        let specialistIds = Set(Trainer.roster.map(\.id))
        unlockedTrainerKeys = unlockedTrainerKeys.filter { specialistIds.contains($0) }
        return before - xpByTrainer.count
    }
}
