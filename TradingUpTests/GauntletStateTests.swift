import XCTest
@testable import TradingUp

/// Orchestration tests for `GauntletState` — the observable driver that bridges the
/// pure `GauntletRun`/`GauntletProgress`/`GauntletReward` types to the UI. The rules
/// themselves are covered by `GauntletCoreTests`/`GauntletMetaTests`; these lock the
/// phase transitions, the rip → keep/sell gating, and the win → reward → banked-clear
/// path all the way into the shared Binder and the persisted progress file.
@MainActor
final class GauntletStateTests: XCTestCase {
    var dir: URL!

    override func setUp() {
        super.setUp()
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tu_gstate_\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func makeState(seed: UInt64, seenIntro: Bool = true) -> (GauntletState, GameState) {
        let game = GameState(core: GameCore(), store: SaveStore(directory: dir))
        let pstore = GauntletProgressStore(directory: dir)
        if seenIntro {
            var p = pstore.load()
            _ = p.markIntroSeen()
            pstore.save(p)
        }
        let state = GauntletState(game: game, store: pstore,
                                  runStore: GauntletRunStore(directory: dir), seed: seed)
        return (state, game)
    }

    // MARK: Selection flow

    func testSelectionFlowStartsARun() {
        let (s, _) = makeState(seed: 1)
        XCTAssertEqual(s.phase, .trainerSelect)

        s.chooseTrainer(.neutral)
        XCTAssertEqual(s.phase, .tierSelect)
        XCTAssertEqual(s.selectedTrainer?.id, "neutral")

        s.startRun(tier: .easy)
        XCTAssertEqual(s.phase, .ripping)
        XCTAssertEqual(s.run?.tier, .easy)
        XCTAssertEqual(s.run?.trainer.id, "neutral")
    }

    func testLockedTierCannotStart() {
        let (s, _) = makeState(seed: 1)
        s.chooseTrainer(.neutral)
        s.startRun(tier: .hard)     // Hard is locked on a fresh progress file
        XCTAssertEqual(s.phase, .tierSelect, "starting a locked tier is a no-op")
        XCTAssertNil(s.run)
    }

    func testOnlyEasyIsUnlockedInitially() {
        let (s, _) = makeState(seed: 1)
        XCTAssertEqual(s.unlockedTiers, [.easy])
        XCTAssertTrue(s.isUnlocked(.easy))
        XCTAssertFalse(s.isUnlocked(.medium))
        XCTAssertFalse(s.isUnlocked(.hard))
    }

    // MARK: Intro explainer gating

    func testFirstEverOpenShowsIntroAndRemembersDismissal() {
        let (s, _) = makeState(seed: 1, seenIntro: false)
        XCTAssertEqual(s.phase, .intro, "the how-to shows on the first ever open")

        s.dismissIntro()
        XCTAssertEqual(s.phase, .trainerSelect)
        XCTAssertTrue(s.progress.hasSeenIntro)

        // Durable: a fresh state over the same store skips straight past the intro.
        let game2 = GameState(core: GameCore(), store: SaveStore(directory: dir))
        let s2 = GauntletState(game: game2, store: GauntletProgressStore(directory: dir),
                               runStore: GauntletRunStore(directory: dir), seed: 1)
        XCTAssertEqual(s2.phase, .trainerSelect, "the intro never re-shows once seen")
    }

    func testShowIntroReopensTheExplainer() {
        let (s, _) = makeState(seed: 1)               // seenIntro → starts at Trainer select
        XCTAssertEqual(s.phase, .trainerSelect)
        s.showIntro()
        XCTAssertEqual(s.phase, .intro)
        s.dismissIntro()
        XCTAssertEqual(s.phase, .trainerSelect)
    }

    // MARK: Trainer unlock gating

    func testOnlyTheRookieIsUnlockedInitially() {
        let (s, _) = makeState(seed: 1)
        XCTAssertTrue(s.isTrainerUnlocked(.neutral))
        for t in Trainer.roster {
            XCTAssertFalse(s.isTrainerUnlocked(t), "\(t.name) starts locked")
        }
    }

    func testLockedTrainerCannotBeChosen() {
        let (s, _) = makeState(seed: 1)
        let locked = Trainer.roster.first { $0.id == "ripper" }!
        s.chooseTrainer(locked)
        XCTAssertEqual(s.phase, .trainerSelect, "a locked Trainer can't be selected")
        XCTAssertNil(s.selectedTrainer)
    }

    // MARK: Pack rail (per-set rip gating)

    func testPackRailStartsWithOnlyTheFirstSetUnlocked() {
        let (s, _) = makeState(seed: 1)
        s.chooseTrainer(.neutral)
        s.startRun(tier: .easy)
        XCTAssertEqual(s.packTier, 1)
        XCTAssertTrue(s.isPackUnlocked(1))
        XCTAssertFalse(s.isPackUnlocked(2))
        XCTAssertNotNil(s.packUnlockCost(2), "a locked set advertises an unlock price")
        XCTAssertNil(s.packUnlockCost(1), "the free starter has no unlock price")
        XCTAssertEqual(s.packTiers, Array(1...GauntletEconomy.maxPackTier))
    }

    func testPackRailReadThroughReflectsTheRun() {
        let (s, _) = makeState(seed: 3)
        s.chooseTrainer(.neutral)
        s.startRun(tier: .easy)
        // The advertised unlock price always delegates to the run, so the rail can
        // still label a locked set with its shop price even mid-round.
        XCTAssertNil(s.packUnlockCost(1), "the free starter has no unlock price")
        XCTAssertEqual(s.packUnlockCost(2), GauntletEconomy.packUnlockCost(set: 2))
        XCTAssertEqual(s.packUnlockCost(GauntletEconomy.maxPackTier),
                       GauntletEconomy.packUnlockCost(set: GauntletEconomy.maxPackTier))
        // But *buying* is shop-only: mid-round the unlock gate is closed and the buy
        // is a no-op that opens nothing. (Out-of-order unlocking is proven at the
        // model layer in GauntletCoreTests, and the shop path in the test below.)
        XCTAssertFalse(s.canUnlockPack(2), "the unlock gate is closed outside the shop")
        XCTAssertFalse(s.unlockPack(2), "unlocking mid-round is a no-op")
        XCTAssertFalse(s.isPackUnlocked(2))
    }

    /// Packs are opened **only in the between-rounds shop**, never mid-round on the
    /// rail. This drives a run until it can afford the cheapest paid set and proves
    /// both halves: while a round is live the buy is refused *even though the run
    /// holds the cash*, and once the shop opens the very same buy goes through.
    func testPacksUnlockOnlyInTheShopNotMidRound() {
        let cost = GauntletEconomy.packUnlockCost(set: 2)!   // cheapest paid set
        for seed in UInt64(1)...40 {
            let (s, _) = makeState(seed: seed)
            s.chooseTrainer(.neutral)
            s.startRun(tier: .easy)

            var provedMidRoundRejection = false
            var guardCount = 0
            drive: while guardCount < 5000 {
                guardCount += 1
                switch s.phase {
                case .ripping:
                    // The moment the run can afford set 2, the mid-round gate must
                    // still refuse it — the run has the cash, only the phase blocks it.
                    if !provedMidRoundRejection, let r = s.run,
                       !r.isPackUnlocked(2), r.canUnlockPack(2) {
                        XCTAssertFalse(s.canUnlockPack(2), "mid-round the shop gate is closed")
                        XCTAssertFalse(s.unlockPack(2), "mid-round unlock is a no-op")
                        XCTAssertFalse(s.isPackUnlocked(2), "set 2 stays locked mid-round")
                        provedMidRoundRejection = true
                    }
                    if s.canRip {
                        s.rip(); resolvePending(s)
                    } else if s.canEndRound {
                        s.endRound()
                    } else {
                        resolvePending(s)   // safety net; shouldn't be reached
                    }
                case .shop:
                    // In the shop the identical buy — same run, same cash — succeeds.
                    if provedMidRoundRejection, let r = s.run,
                       !r.isPackUnlocked(2), r.canUnlockPack(2) {
                        XCTAssertTrue(s.canUnlockPack(2), "the shop opens the unlock gate")
                        let cashBefore = r.cash
                        XCTAssertTrue(s.unlockPack(2), "the shop opens the set")
                        XCTAssertTrue(s.isPackUnlocked(2), "set 2 is now rippable")
                        XCTAssertEqual(s.run!.cash, cashBefore - cost, accuracy: 1e-6)
                        return   // both halves proven for this seed
                    }
                    s.continueFromShop()
                default:
                    break drive   // won / lost / reward — try another seed
                }
            }
        }
        XCTFail("no seed reached an affordable unlock both mid-round and in the shop in 40 tries")
    }


    func testRippingRecordsPulledCardsIntoTheSharedBinder() {
        let (s, game) = makeState(seed: 7)
        s.chooseTrainer(.neutral)
        s.startRun(tier: .easy)
        XCTAssertEqual(game.binder.filledCount, 0, "the Binder starts empty in this run's temp dir")

        s.rip(set: 1)
        XCTAssertFalse(s.pendingCards.isEmpty)
        // Every card the pack surfaced should now sit in the all-time Binder at a
        // value at least as high as what was pulled — Gauntlet pulls feed the
        // collection just like Classic (item 1), before any keep/sell decision.
        for card in s.pendingCards {
            let best = game.binder.best(for: card.cardId)
            XCTAssertNotNil(best, "pulled card \(card.cardId) should be recorded in the Binder")
            XCTAssertGreaterThanOrEqual(best!.currentValue, card.currentValue)
        }
    }

    func testGradingAShowcaseCardUpdatesTheBinderValue() {
        let (s, game) = makeState(seed: 11)
        s.chooseTrainer(.neutral)
        s.startRun(tier: .easy)
        // Pull a card, keep it, and settle the rest of the pack. The set-1 grade fee
        // is $2 against the $15 starting stake, so no cash plumbing is needed.
        s.rip(set: 1)
        guard let first = s.pendingCards.first else { return XCTFail("expected a pull") }
        s.keep(first)
        while let c = s.pendingCards.first { s.sell(c) }
        let idx = 0
        let beforeValue = s.run!.showcase[idx].currentValue
        guard s.canGrade(showcaseIndex: idx) else { return }

        if s.grade(showcaseIndex: idx) != nil {
            let graded = s.run!.showcase[idx]
            // The Binder keeps the running max, so it reflects at least the ungraded
            // pull and the graded card — grading never lowers a recorded best.
            let best = game.binder.best(for: graded.cardId)
            XCTAssertNotNil(best)
            XCTAssertGreaterThanOrEqual(best!.currentValue, beforeValue)
            XCTAssertGreaterThanOrEqual(best!.currentValue, graded.currentValue)
        }
    }

    func testRipRejectsALockedPackSetButSpendsNothing() {
        let (s, _) = makeState(seed: 7)
        s.chooseTrainer(.neutral)
        s.startRun(tier: .easy)
        let ripsBefore = s.run!.ripsLeft

        s.rip(set: 2)                                  // set 2 is locked at run start
        XCTAssertTrue(s.pendingCards.isEmpty, "a locked pack can't be ripped")
        XCTAssertEqual(s.run!.ripsLeft, ripsBefore, "a rejected rip spends no rip")

        s.rip(set: 1)                                  // the unlocked set works
        XCTAssertFalse(s.pendingCards.isEmpty)
        XCTAssertEqual(s.run!.ripsLeft, ripsBefore - 1)
    }

    func testRipThenResolveGatesTheNextRip() {
        let (s, _) = makeState(seed: 7)
        s.chooseTrainer(.neutral)
        s.startRun(tier: .easy)

        XCTAssertTrue(s.canRip)
        s.rip()
        XCTAssertFalse(s.pendingCards.isEmpty, "a rip surfaces cards to resolve")
        XCTAssertFalse(s.canRip, "you can't rip again with an unresolved pull")

        resolvePending(s)
        XCTAssertTrue(s.pendingCards.isEmpty)
        XCTAssertNil(s.pendingCatalyst)
        // Either rips remain (can rip again) or the round is spent.
        XCTAssertTrue(s.canRip || s.run!.ripsLeft == 0)
    }

    func testKeepMovesToShowcaseAndSellBanksCash() {
        let (s, _) = makeState(seed: 11)
        s.chooseTrainer(.neutral)
        s.startRun(tier: .easy)
        s.rip()

        // Keep the first card while a slot is free.
        let before = s.run!.showcase.count
        if s.canKeepPending, let card = s.pendingCards.first {
            s.keep(card)
            XCTAssertEqual(s.run!.showcase.count, before + 1)
            XCTAssertFalse(s.pendingCards.contains { $0.id == card.id })
        }

        // Sell the next card straight to cash.
        if let card = s.pendingCards.first {
            let cash = s.run!.cash
            let gained = s.sell(card)
            XCTAssertGreaterThan(gained, 0)
            XCTAssertEqual(s.run!.cash, cash + gained, accuracy: 0.0001)
            XCTAssertFalse(s.pendingCards.contains { $0.id == card.id })
        }
    }

    // MARK: Catalyst swap (full slots)

    /// When a Catalyst is offered but every slot is full, the offer becomes a swap:
    /// tapping a slot drops the old effect and applies the new one immediately.
    /// Catalysts drop ~14% per rip, so a winning Easy run reliably offers a second
    /// one; search a few seeds for the full-slots case and assert the state swap.
    func testSwapPendingCatalystReplacesTheActiveCatalyst() {
        for seed in UInt64(0)..<40 {
            let (s, _) = makeState(seed: seed)
            s.chooseTrainer(.neutral)
            s.startRun(tier: .easy)

            var attunedFirst = false
            var guardCount = 0
            loop: while guardCount < 5000 {
                guardCount += 1
                switch s.phase {
                case .ripping:
                    if s.pendingCatalyst != nil {
                        if s.canAttunePending {
                            s.attunePendingCatalyst()
                            attunedFirst = true
                        } else if s.canSwapPending {
                            XCTAssertTrue(attunedFirst, "a slot had to be filled first")
                            XCTAssertFalse(s.canAttunePending, "swap only when no slot is free")
                            let incomingId = s.pendingCatalyst!.id
                            s.swapPendingCatalyst(replacing: 0)
                            XCTAssertNil(s.pendingCatalyst, "the offer is consumed by the swap")
                            XCTAssertEqual(s.run!.attunedCatalysts.count, 1,
                                           "a swap trades one Catalyst for another")
                            XCTAssertEqual(s.run!.attunedCatalysts[0].id, incomingId,
                                           "the swapped-in Catalyst is now the active one")
                            return
                        } else {
                            s.sellPendingCatalyst()
                        }
                    }
                    while let card = s.pendingCards.first {
                        if s.canKeepPending { s.keep(card) } else { s.sell(card) }
                    }
                    if s.canRip {
                        s.rip()
                    } else if s.canEndRound {
                        s.endRound()
                    } else {
                        break loop
                    }
                case .shop:
                    s.continueFromShop()
                default:
                    break loop
                }
            }
        }
        XCTFail("no seed offered a second Catalyst with full slots within 40 tries")
    }

    func testAbandonReturnsToTrainerSelectWithoutBanking() {
        let (s, _) = makeState(seed: 3)
        s.chooseTrainer(.neutral)
        s.startRun(tier: .easy)
        s.abandonRun()
        XCTAssertEqual(s.phase, .trainerSelect)
        XCTAssertNil(s.run)
        XCTAssertTrue(s.progress.clearedTiers(forTrainer: "neutral").isEmpty, "an abandoned run banks nothing")
        XCTAssertFalse(s.progress.isUnlocked(.medium, forTrainer: "neutral"))
    }

    // MARK: Resume an in-progress run (req 11)

    func testLeavingMidRunResumesItOnReturn() {
        let (s, _) = makeState(seed: 7)
        s.chooseTrainer(.neutral)
        s.startRun(tier: .easy)
        s.rip()
        resolvePending(s)
        guard s.phase == .ripping, let run = s.run else {
            return   // the seeded round resolved immediately; other tests cover that
        }
        let round = run.round
        let cash = run.cash
        let showcase = run.showcase.count
        s.persistForExit()   // what the home button does

        // A brand-new driver over the same stores resumes the run rather than
        // dropping the player back on Trainer select.
        let game2 = GameState(core: GameCore(), store: SaveStore(directory: dir))
        let resumed = GauntletState(game: game2, store: GauntletProgressStore(directory: dir),
                                    runStore: GauntletRunStore(directory: dir), seed: 7)
        XCTAssertEqual(resumed.phase, .ripping, "an in-progress round resumes into the run")
        XCTAssertEqual(resumed.run?.round, round)
        XCTAssertEqual(resumed.run?.cash ?? -1, cash, accuracy: 0.0001)
        XCTAssertEqual(resumed.run?.showcase.count, showcase)
        XCTAssertEqual(resumed.selectedTrainer?.id, "neutral")
    }

    func testAbandoningARunLeavesNothingToResume() {
        let (s, _) = makeState(seed: 3)
        s.chooseTrainer(.neutral)
        s.startRun(tier: .easy)
        s.rip()
        resolvePending(s)
        s.abandonRun()
        XCTAssertFalse(GauntletRunStore(directory: dir).hasSavedRun, "abandoning clears the saved run")

        let game2 = GameState(core: GameCore(), store: SaveStore(directory: dir))
        let resumed = GauntletState(game: game2, store: GauntletProgressStore(directory: dir),
                                    runStore: GauntletRunStore(directory: dir), seed: 3)
        XCTAssertEqual(resumed.phase, .trainerSelect, "an abandoned run is not resumed")
        XCTAssertNil(resumed.run)
    }

    // MARK: GameState reward hook

    func testAwardExtendedArtEarnsArtRecordsFoilAndPersists() {
        let game = GameState(core: GameCore(), store: SaveStore(directory: dir))
        let option = GauntletRewardOption(cardId: "S1-001")

        XCTAssertFalse(game.binder.hasExtendedArt("S1-001"))
        game.awardExtendedArt(option)

        XCTAssertTrue(game.binder.hasExtendedArt("S1-001"), "the art is unlocked")
        XCTAssertEqual(game.binder.best(for: "S1-001")?.foil, true, "the guaranteed foil copy is recorded")

        let reloaded = BinderStore(directory: dir).load()
        XCTAssertTrue(reloaded.hasExtendedArt("S1-001"), "the unlock is persisted to the Binder file")
    }

    /// The reward picker's "New" flag tracks the Extended-Art layer, not plain
    /// ownership: a Spryte already held in standard art is still "New" until its
    /// Extended Art is earned, and an already-earned card never flags.
    func testIsNewCardTracksExtendedArtNotPlainOwnership() {
        let (s, game) = makeState(seed: 7)
        let option = GauntletRewardOption(cardId: "S1-001")

        XCTAssertTrue(s.isNewCard(option), "unowned card with no Extended Art is New")

        // Owning a plain copy must not clear the flag — the Extended Art is still new.
        game.recordGauntletCards([CardInstance(cardId: "S1-001", foil: false)])
        XCTAssertTrue(game.binder.hasCard("S1-001"))
        XCTAssertFalse(game.binder.hasExtendedArt("S1-001"))
        XCTAssertTrue(s.isNewCard(option), "plain copy owned but Extended Art unearned is still New")

        // Once the Extended Art is earned, the same option is no longer New.
        game.awardExtendedArt(option)
        XCTAssertTrue(game.binder.hasExtendedArt("S1-001"))
        XCTAssertFalse(s.isNewCard(option), "earned Extended Art is not New")
    }

    // MARK: Full run — win pays out to the Binder and banks the clear

    func testEasyRunWinAwardsArtAndUnlocksMedium() {
        // Easy is ~100% winnable, but any single run is seeded; search a few seeds
        // for a win, then assert the whole win → reward → progress path.
        for seed in UInt64(0)..<24 {
            let (s, game) = makeState(seed: seed)
            s.chooseTrainer(.neutral)
            s.startRun(tier: .easy)
            driveGreedy(s)

            guard s.phase == .reward, let option = s.rewardOptions.first else { continue }
            let cardId = option.cardId
            XCTAssertEqual(s.rewardOptions.count, GauntletEconomy.rewardOptionCount)

            s.chooseReward(option)
            XCTAssertEqual(s.phase, .results)
            XCTAssertTrue(game.binder.hasExtendedArt(cardId), "the chosen Extended Art lands in the Binder")

            let clear = s.lastClear
            XCTAssertNotNil(clear)
            XCTAssertEqual(clear!.unlockedTier, .medium, "clearing Easy unlocks Medium")
            XCTAssertTrue(s.progress.isUnlocked(.medium, forTrainer: "neutral"))

            // Durable: the clear is on disk in the progress file.
            let reloaded = GauntletProgressStore(directory: dir).load()
            XCTAssertTrue(reloaded.isUnlocked(.medium, forTrainer: "neutral"))
            XCTAssertTrue(reloaded.hasCleared(.easy, trainer: "neutral"))

            s.finish()
            XCTAssertEqual(s.phase, .trainerSelect)
            return
        }
        XCTFail("no seed produced an Easy win in 24 tries — Easy should be ~100% winnable")
    }

    // MARK: - Greedy driver (test-only strategy)

    /// Play a run to a terminal phase: rip out every round, greedily filling the
    /// Showcase (swapping when a pull beats the weakest keeper), never buying in the
    /// shop. Strong enough to clear Easy, which is all this needs.
    private func driveGreedy(_ s: GauntletState) {
        var guardCount = 0
        while guardCount < 5000 {
            guardCount += 1
            switch s.phase {
            case .ripping:
                if s.canRip {
                    s.rip()
                    resolvePending(s)
                } else if s.canEndRound {
                    s.endRound()
                } else {
                    resolvePending(s)   // safety net; shouldn't be reached
                }
            case .shop:
                s.continueFromShop()
            default:
                return
            }
        }
    }

    /// Resolve the current pull: attune a Catalyst if there's room (else sell it),
    /// then keep each card while slots are free, swapping for the weakest keeper when
    /// the pull is a strict upgrade, otherwise selling.
    private func resolvePending(_ s: GauntletState) {
        if s.pendingCatalyst != nil {
            if s.canAttunePending { s.attunePendingCatalyst() } else { s.sellPendingCatalyst() }
        }
        while let card = s.pendingCards.first {
            if s.canKeepPending {
                s.keep(card)
            } else if let run = s.run,
                      let idx = run.weakestShowcaseIndex(),
                      run.marginalAura(of: card) > contribution(of: idx, in: run) {
                s.swap(card, forShowcaseIndex: idx)
            } else {
                s.sell(card)
            }
        }
    }

    /// How much the Showcase card at `idx` currently contributes to the Aura.
    private func contribution(of idx: Int, in run: GauntletRun) -> Double {
        var without = run.showcase
        without.remove(at: idx)
        let base = GauntletRun.aura(without,
                                        evoLineBonusBonus: run.mods.evoLineBonusBonus,
                                        auraMult: run.mods.auraMult)
        return run.showcaseAura - base
    }
}
