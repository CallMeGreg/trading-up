import Foundation

/// Observable driver for **Gauntlet Mode**: it owns the cross-run meta progression
/// (`GauntletProgress`, persisted via its own store), drives the pure `GauntletRun`
/// state machine through the rip → keep/sell → shop → reward loop, and routes a
/// win's Extended-Art prize into the all-time Binder (owned by `GameState`). Like
/// `GameState`, it keeps randomness and persistence here so the SwiftUI views stay
/// declarative. All the game rules live in the pure `Models/` types this wraps —
/// this layer is only orchestration and phase. See docs/DESIGN.md §14.
@Observable
@MainActor
final class GauntletState {

    /// Where the player is in the Gauntlet flow. The UI switches on this.
    enum Phase: Equatable {
        case intro              // first-time (or replayed) how-to explainer
        case trainerSelect      // pick a Trainer for the run
        case tierSelect         // pick an unlocked difficulty
        case ripping            // an active round: rip, then keep/sell/grade/attune
        case shop               // between rounds, spend cash on upgrades
        case reward             // won: choose one of the Extended-Art prizes
        case results            // post-run summary (XP / level-up / tier unlock)
        case lost               // missed the bar — run over (rounds are single-life)
    }

    // MARK: Meta progression (durable, cross-run)

    private(set) var progress: GauntletProgress
    private let store: GauntletProgressStore

    /// The Binder lives on `GameState`; a Gauntlet win's prize is folded in there
    /// (and persisted) so both modes share one all-time, value-best collection.
    private let game: GameState

    // MARK: Current run

    private(set) var phase: Phase = .trainerSelect
    private(set) var run: GauntletRun?
    private(set) var selectedTrainer: Trainer?

    /// The most recent rip's undecided items. The player must resolve every pending
    /// card (keep or sell) and any Catalyst offer (attune or sell) before the next
    /// rip — the same immediate keep-vs-sell cadence the balance harness models.
    private(set) var pendingCards: [CardInstance] = []
    private(set) var pendingCatalyst: Catalyst?

    /// Which element set the latest rip opened, so the full-screen reveal shows the
    /// matching pack artwork.
    private(set) var lastRippedSet: Int = 1

    /// Drives the full-screen pack-reveal cover. A rip raises it; the reveal's
    /// Continue button lowers it once the pull is fully resolved (`finishReveal`).
    var revealActive = false

    /// The outcome of the last resolved round, so the UI can flash "cleared" /
    /// "missed" without inspecting the state machine.
    private(set) var lastOutcome: RoundOutcome?

    // MARK: Reward / results

    private(set) var rewardOptions: [GauntletRewardOption] = []
    private(set) var lastClear: GauntletProgress.ClearResult?
    /// True when the win paid a consolation because every card's Extended Art was
    /// already earned — the UI explains there was no new art to grant.
    private(set) var rewardWasConsolation = false

    /// Trainers this just-finished run newly unlocked (win or loss), so the results
    /// and lost screens can celebrate them. Reset at the start of each run.
    private(set) var lastUnlockedTrainers: [Trainer] = []

    private var rng: AppRNG

    // MARK: Init

    /// Production wiring: share the Binder-owning `GameState`, persist progress to
    /// the default location. Tests can inject a temp-dir store and a fixed seed.
    init(game: GameState, store: GauntletProgressStore = GauntletProgressStore(), seed: UInt64? = nil) {
        self.game = game
        self.store = store
        self.progress = store.load()
        self.rng = seed.map { AppRNG(seed: $0) } ?? AppRNG()
        // Show the how-to once, the first time Gauntlet is ever opened.
        self.phase = progress.hasSeenIntro ? .trainerSelect : .intro
    }

    // MARK: Roster / meta read-through

    /// Selectable Trainers: the always-available "Rookie" first, then the flavoured
    /// roster (each earned via a Gauntlet milestone — see `isTrainerUnlocked`).
    var trainers: [Trainer] { [Trainer.neutral] + Trainer.roster }

    /// Difficulty tiers the player may start, in ladder order.
    var unlockedTiers: [GauntletTier] { progress.unlockedTiers }

    func isUnlocked(_ tier: GauntletTier) -> Bool { progress.isUnlocked(tier) }

    /// Whether a Trainer has been earned yet (the Rookie is always available).
    func isTrainerUnlocked(_ trainer: Trainer) -> Bool { progress.isTrainerUnlocked(trainer.id) }

    /// Milestone progress toward a locked Trainer, for its card's progress line —
    /// `nil` for the Rookie (no criterion).
    func unlockProgress(for trainer: Trainer) -> (have: Int, need: Int)? {
        progress.unlockProgress(for: trainer)
    }

    func level(for trainer: Trainer) -> Int { progress.level(forTrainer: trainer.id) }
    func xp(for trainer: Trainer) -> Int { progress.xp(forTrainer: trainer.id) }
    func xpToNext(for trainer: Trainer) -> Int? { progress.xpToNextLevel(forTrainer: trainer.id) }
    var maxTrainerLevel: Int { GauntletEconomy.maxTrainerLevel }

    /// Whether every card's Extended Art has been earned (future wins pay a
    /// consolation instead of art).
    var catalogueComplete: Bool {
        GauntletReward.isCatalogueComplete(earnedExtendedArt: game.binder.extendedArtEarned)
    }

    // MARK: Flow — intro

    /// Leave the how-to explainer for Trainer select, recording that it's been seen
    /// so it won't auto-show again.
    func dismissIntro() {
        if progress.markIntroSeen() { store.save(progress) }
        phase = .trainerSelect
    }

    /// Re-open the how-to explainer from Trainer select (the ⓘ button).
    func showIntro() { phase = .intro }

    // MARK: Flow — selection

    func chooseTrainer(_ trainer: Trainer) {
        guard progress.isTrainerUnlocked(trainer.id) else { return }
        selectedTrainer = trainer
        phase = .tierSelect
    }

    func backToTrainerSelect() {
        selectedTrainer = nil
        phase = .trainerSelect
    }

    /// Start a run with the chosen Trainer at `tier`. No-ops if the tier isn't
    /// unlocked or no Trainer is selected.
    func startRun(tier: GauntletTier) {
        guard progress.isUnlocked(tier), let trainer = selectedTrainer else { return }
        var t = trainer
        t.level = progress.level(forTrainer: trainer.id)
        t.xp = progress.xp(forTrainer: trainer.id)
        run = GauntletRun(tier: tier, trainer: t)
        pendingCards = []
        pendingCatalyst = nil
        revealActive = false
        lastOutcome = nil
        rewardOptions = []
        lastClear = nil
        rewardWasConsolation = false
        lastUnlockedTrainers = []
        phase = .ripping
    }

    /// Abandon the current run and return to Trainer select. Meta progression is
    /// untouched — nothing is banked until a round is actually cleared/won.
    func abandonRun() {
        run = nil
        pendingCards = []
        pendingCatalyst = nil
        revealActive = false
        selectedTrainer = nil
        phase = .trainerSelect
    }

    // MARK: Flow — ripping

    /// Whether a fresh rip is allowed: rips remain and the last pull is fully
    /// resolved.
    var canRip: Bool {
        guard let run else { return false }
        return run.ripsLeft > 0 && pendingCards.isEmpty && pendingCatalyst == nil
    }

    /// Open one pack, surfacing its cards (and any Catalyst offer) as pending
    /// decisions. `set` picks which unlocked element set to rip (1…`packTier`);
    /// `nil` rips the highest unlocked set, matching the balance harness.
    func rip(set: Int? = nil) {
        guard canRip, var r = run else { return }
        if let set, !r.isPackUnlocked(set) { return }
        let opened = set ?? r.packTier
        let result = r.rip(from: set, using: &rng)
        run = r
        pendingCards = result.cards
        pendingCatalyst = result.catalyst
        lastRippedSet = opened
        revealActive = true
    }

    /// Lower the full-screen reveal cover. Only allowed once the pull is settled,
    /// which the reveal's Continue button enforces.
    func finishReveal() {
        guard pendingCards.isEmpty, pendingCatalyst == nil else { return }
        revealActive = false
    }

    // MARK: Pack rail (which element sets are rippable / unlockable this run)

    /// The element sets, low→high, for the run's pack rail.
    var packTiers: [Int] { GauntletRun.allPackTiers }
    /// The highest set unlocked this run (any set 1…`packTier` is rippable).
    var packTier: Int { run?.packTier ?? 1 }
    func isPackUnlocked(_ set: Int) -> Bool { run?.isPackUnlocked(set) ?? false }
    /// The next set that can be bought open, or `nil` at the top of the rail.
    var nextPackTier: Int? { run?.nextPackTier }
    /// Cash cost to unlock the next set, or `nil` if there's none left.
    var packUnlockCost: Double? { run?.packTierUpgradeCost }
    /// Whether the player can afford to unlock the next set right now.
    var canUnlockNextPack: Bool {
        guard let cost = packUnlockCost, let run else { return false }
        return run.cash >= cost
    }
    /// Buy open the next element set (same mechanic/cost as the old shop upgrade).
    @discardableResult
    func unlockNextPack() -> Bool { mutateRun { $0.upgradePackTier() } }

    var canKeepPending: Bool { run?.canKeep ?? false }

    /// Keep a pulled card, moving it into the Showcase (if a slot is free).
    func keep(_ card: CardInstance) {
        guard var r = run, r.canKeep else { return }
        r.keep(card)
        run = r
        removePending(card)
    }

    /// Sell a pulled card straight to cash at the run's sell-back rate.
    @discardableResult
    func sell(_ card: CardInstance) -> Double {
        guard var r = run else { return 0 }
        let gain = r.sell(card)
        run = r
        removePending(card)
        return gain
    }

    /// Replace a Showcase card with a pulled one, banking the removed card's
    /// sell-back. Used when the Showcase is full but the pull is an upgrade.
    func swap(_ card: CardInstance, forShowcaseIndex index: Int) {
        guard var r = run, r.showcase.indices.contains(index) else { return }
        _ = r.swapIn(card, at: index)
        run = r
        removePending(card)
    }

    private func removePending(_ card: CardInstance) {
        pendingCards.removeAll { $0.id == card.id }
    }

    /// Attune the offered Catalyst (if a Catalyst slot is free), applying its
    /// effect for the rest of the run.
    func attunePendingCatalyst() {
        guard var r = run, let cat = pendingCatalyst, r.canAttune else { return }
        _ = r.attune(cat)
        run = r
        pendingCatalyst = nil
    }

    /// Sell the offered Catalyst for its cash value instead of attuning it.
    func sellPendingCatalyst() {
        guard var r = run, let cat = pendingCatalyst else { return }
        r.sellCatalyst(cat)
        run = r
        pendingCatalyst = nil
    }

    var canAttunePending: Bool {
        guard let run, pendingCatalyst != nil else { return false }
        return run.canAttune
    }

    /// Grade a Showcase card, paying the fee and gambling its score. Returns the
    /// rolled grade (nil if unaffordable or already graded).
    @discardableResult
    func grade(showcaseIndex index: Int) -> Int? {
        guard var r = run else { return nil }
        let g = r.gradeShowcaseCard(at: index, using: &rng)
        run = r
        return g
    }

    func canGrade(showcaseIndex index: Int) -> Bool {
        guard let run, run.showcase.indices.contains(index) else { return false }
        let card = run.showcase[index]
        return card.grade == nil && run.cash >= run.gradeFee(for: card.card)
    }

    // MARK: Flow — round resolution

    /// Whether the round can be resolved yet: the current pull must be settled.
    var canEndRound: Bool {
        run != nil && pendingCards.isEmpty && pendingCatalyst == nil
    }

    /// Resolve the current round against its target, routing into the next phase:
    /// a clear opens the shop, a win rolls the reward, a miss ends the run (rounds
    /// are single-life).
    func endRound() {
        guard canEndRound, var r = run else { return }
        let outcome = r.endRound(using: &rng)
        run = r
        lastOutcome = outcome
        switch outcome {
        case .cleared:
            phase = .shop
        case .won:
            rollReward()
        case .lost:
            // Bank XP for any rounds cleared before the bust (none if the player
            // didn't get past round 1); losses never unlock a tier. (req 3)
            let roundsCleared = max(0, r.round - 1)
            lastClear = progress.recordLoss(trainerId: r.trainer.id, tier: r.tier, roundsCleared: roundsCleared)
            ingestRunStats()
            store.save(progress)
            phase = .lost
        }
    }

    /// Leave the between-round shop and begin the next round (already primed by the
    /// clear).
    func continueFromShop() {
        guard run != nil else { return }
        phase = .ripping
    }

    // MARK: Shop (between rounds)

    @discardableResult
    func upgradePackTier() -> Bool { mutateRun { $0.upgradePackTier() } }
    @discardableResult
    func buySlot() -> Bool { mutateRun { $0.buySlot() } }
    @discardableResult
    func buyCatalystSlot() -> Bool { mutateRun { $0.buyCatalystSlot() } }

    private func mutateRun(_ body: (inout GauntletRun) -> Bool) -> Bool {
        guard var r = run else { return false }
        let ok = body(&r)
        run = r
        return ok
    }

    // MARK: Reward + banking the clear

    /// Roll the win's payout. Extended-Art wins present a choose-one row; a
    /// complete catalogue pays the consolation and banks the clear immediately.
    private func rollReward() {
        guard let r = run else { return }
        let payout = GauntletReward.payout(tier: r.tier,
                                           earnedExtendedArt: game.binder.extendedArtEarned,
                                           using: &rng)
        switch payout {
        case .extendedArt(let options):
            rewardOptions = options
            rewardWasConsolation = false
            phase = .reward
        case .consolation:
            rewardOptions = []
            rewardWasConsolation = true
            bankClear()                // nothing to choose; record and summarise
            phase = .results
        }
    }

    /// Apply the player's chosen Extended-Art prize to the Binder (via `GameState`,
    /// which owns and persists it), then bank the clear and show the summary.
    func chooseReward(_ option: GauntletRewardOption) {
        game.awardExtendedArt(option)
        bankClear()
        phase = .results
    }

    /// Record the run's clear into durable progress (Trainer XP + next-tier unlock)
    /// and persist. Idempotent per win: only called once from the reward/consolation
    /// paths.
    private func bankClear() {
        guard let r = run else { return }
        lastClear = progress.recordClear(trainerId: r.trainer.id, tier: r.tier)
        ingestRunStats()
        store.save(progress)
    }

    /// Fold the finished run's lifetime stats into durable progress and note any
    /// Trainers it newly unlocked (for the results / lost screens to celebrate).
    /// Called exactly once per run end — from `bankClear` on a win, from the lost
    /// path on a loss — before persisting.
    private func ingestRunStats() {
        guard let r = run else { return }
        let newIds = progress.ingest(r.runReport)
        lastUnlockedTrainers = newIds.compactMap { id in Trainer.roster.first { $0.id == id } }
    }

    // MARK: Flow — leaving a finished run

    /// Return to Trainer select after a win or loss, ready for another run.
    func finish() {
        run = nil
        pendingCards = []
        pendingCatalyst = nil
        selectedTrainer = nil
        rewardOptions = []
        lastOutcome = nil
        lastUnlockedTrainers = []
        phase = .trainerSelect
    }
}
