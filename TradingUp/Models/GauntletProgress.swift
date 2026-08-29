import Foundation

// MARK: - Gauntlet meta progression

/// The durable, cross-run Gauntlet record: which difficulty tiers each Trainer
/// has cleared (which drives the accomplishment badges *and* the mystery
/// Trainer's reveal), which specialist Trainers the player has earned, and the
/// lifetime stat counters those unlocks read. Like the `Binder`, it only ever
/// grows and deliberately outlives any single run, so it lives in its own file
/// (`GauntletProgressStore`) rather than the per-run save. Pure and
/// Foundation-only, like everything under `Models/`.
///
/// Everything decodes leniently and every field is additive (§12): an old
/// progress file — including one still carrying the retired per-Trainer XP, which
/// is simply ignored — or none at all on first launch still yields a valid record
/// with Easy unlocked and nothing cleared. See docs/DESIGN.md §14.3/§14.8.
struct GauntletProgress: Codable, Equatable {

    /// Which difficulty tiers each Trainer has *cleared*, keyed by Trainer id →
    /// the set of tier rawValues won with that Trainer. This one map does triple
    /// duty: it gates the per-Trainer ladder (req 4 — a Trainer unlocks Medium only
    /// once *it* has cleared Easy, Hard once *it* has cleared Medium), it lights the
    /// card's accomplishment badges, and it decides when the mystery Trainer is
    /// earned (every other Trainer has cleared Hard). Easy is always available, so
    /// it need not be stored. Additive: an old file with no entry starts every
    /// Trainer at Easy. See docs/DESIGN.md §14.5.
    private(set) var clearedTiersByTrainer: [String: Set<String>]

    /// The specialist Trainers the player has earned. The starter Joe (neutral) is
    /// *always* available (enforced in `isTrainerUnlocked`) as the starter, so it
    /// need not be stored; every other Trainer is unlocked by a Gauntlet milestone
    /// (or, for the mystery Trainer, by beating Hard with all the rest).
    private(set) var unlockedTrainerKeys: Set<String>

    /// Lifetime Gauntlet stat counters (see `GauntletStat`). Some are running sums
    /// (packs ripped), others high-water marks (widest Showcase). They're the seam
    /// Trainer unlocks read, and — like everything here — only ever grow.
    private(set) var stats: [String: Int]

    /// Whether the player has seen the mode's how-to at least once. Drives the
    /// first-launch explainer; additive so an old file simply shows it once.
    private(set) var hasSeenIntro: Bool

    init(clearedTiersByTrainer: [String: Set<String>] = [:],
         unlockedTrainerKeys: Set<String> = [],
         stats: [String: Int] = [:],
         hasSeenIntro: Bool = false) {
        self.clearedTiersByTrainer = clearedTiersByTrainer
        self.unlockedTrainerKeys = unlockedTrainerKeys
        self.stats = stats
        self.hasSeenIntro = hasSeenIntro
    }

    /// Decode leniently: a missing key falls back to its default rather than
    /// failing the whole decode, so a future additive field — or a retired one like
    /// the old per-Trainer XP — can't break an existing progress file.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clearedTiersByTrainer = try c.decodeIfPresent([String: Set<String>].self, forKey: .clearedTiersByTrainer) ?? [:]
        unlockedTrainerKeys = try c.decodeIfPresent(Set<String>.self, forKey: .unlockedTrainerKeys) ?? []
        stats = try c.decodeIfPresent([String: Int].self, forKey: .stats) ?? [:]
        hasSeenIntro = try c.decodeIfPresent(Bool.self, forKey: .hasSeenIntro) ?? false
    }

    // MARK: Derived — tiers & badges

    /// Whether a Trainer has already cleared (won) a given tier.
    func hasCleared(_ tier: GauntletTier, trainer id: String) -> Bool {
        clearedTiersByTrainer[id]?.contains(tier.rawValue) ?? false
    }

    /// The set of tiers a Trainer has cleared — the data behind its card's
    /// accomplishment badges.
    func clearedTiers(forTrainer id: String) -> Set<GauntletTier> {
        Set((clearedTiersByTrainer[id] ?? []).compactMap(GauntletTier.init(rawValue:)))
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
    /// starter; every specialist (and the mystery Trainer) must be earned.
    func isTrainerUnlocked(_ id: String) -> Bool {
        id == Trainer.neutral.id || unlockedTrainerKeys.contains(id)
    }

    /// The Trainers whose Hard clear is required to reveal the mystery Trainer:
    /// every selectable Trainer except the mystery one itself (the Rookie plus the
    /// earned specialists).
    private var mysteryPrerequisites: [String] {
        ([Trainer.neutral] + Trainer.roster.filter { !$0.mysteryUntilUnlocked }).map(\.id)
    }

    /// Whether the mystery Trainer has been earned: every other Trainer has cleared
    /// Hard.
    var isMysteryTrainerEarned: Bool {
        mysteryPrerequisites.allSatisfy { hasCleared(.hard, trainer: $0) }
    }

    /// How close the player is to unlocking a Trainer, for the locked card's
    /// progress line: `(have, need)` clamped so `have` never exceeds `need`. The
    /// mystery Trainer measures how many other Trainers have cleared Hard; a stat
    /// specialist measures its milestone stat; the Rookie has neither and returns
    /// `nil`.
    func unlockProgress(for trainer: Trainer) -> (have: Int, need: Int)? {
        if trainer.mysteryUntilUnlocked {
            let reqs = mysteryPrerequisites
            let have = reqs.filter { hasCleared(.hard, trainer: $0) }.count
            return (have, reqs.count)
        }
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

    /// Unlock any Trainer whose criterion the current record now satisfies —
    /// stat-milestone specialists, then the mystery Trainer once every other
    /// Trainer has cleared Hard. Returns the newly unlocked ids, roster order.
    @discardableResult
    private mutating func evaluateTrainerUnlocks() -> [String] {
        var newly: [String] = []
        for trainer in Trainer.roster where !isTrainerUnlocked(trainer.id) {
            let earned: Bool
            if trainer.mysteryUntilUnlocked {
                earned = isMysteryTrainerEarned
            } else if let u = trainer.unlock {
                earned = stat(u.stat) >= u.threshold
            } else {
                earned = false
            }
            if earned, unlockedTrainerKeys.insert(trainer.id).inserted {
                newly.append(trainer.id)
            }
        }
        return newly
    }

    /// What a single cleared run changed about the meta progression — enough for
    /// the UI to celebrate a freshly unlocked tier.
    struct ClearResult: Equatable {
        var unlockedTier: GauntletTier?
    }

    /// Bank a run clear: record that this Trainer cleared this tier, which opens the
    /// next tier *for that Trainer* (and, once every Trainer has cleared Hard,
    /// contributes toward the mystery unlock, evaluated in `ingest`). Returns the
    /// newly opened tier, if any, so the results screen can celebrate it.
    @discardableResult
    mutating func recordClear(trainerId: String, tier: GauntletTier) -> ClearResult {
        let alreadyCleared = hasCleared(tier, trainer: trainerId)
        clearedTiersByTrainer[trainerId, default: []].insert(tier.rawValue)
        var newlyUnlocked: GauntletTier? = nil
        if !alreadyCleared, let next = GauntletTier.allCases.first(where: { $0.requires == tier }) {
            newlyUnlocked = next
        }
        return ClearResult(unlockedTier: newlyUnlocked)
    }

    /// Drop entries for Trainers no longer in the roster — the same load hygiene the
    /// Binder does — so a record written against an older roster doesn't keep dead
    /// ids around. Returns how many cleared-tier entries were removed.
    @discardableResult
    mutating func sanitize() -> Int {
        let known = Set(Trainer.roster.map(\.id) + [Trainer.neutral.id])
        let beforeCleared = clearedTiersByTrainer.count
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
        return beforeCleared - clearedTiersByTrainer.count
    }
}
