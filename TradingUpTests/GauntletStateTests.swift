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
        let state = GauntletState(game: game, store: pstore, seed: seed)
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
        let s2 = GauntletState(game: game2, store: GauntletProgressStore(directory: dir), seed: 1)
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
        // Costs and gates delegate straight to the underlying run.
        XCTAssertNil(s.packUnlockCost(1), "the free starter has no unlock price")
        XCTAssertEqual(s.packUnlockCost(2), GauntletEconomy.packUnlockCost(set: 2))
        XCTAssertEqual(s.packUnlockCost(GauntletEconomy.maxPackTier),
                       GauntletEconomy.packUnlockCost(set: GauntletEconomy.maxPackTier))
        // At the starting stake nothing on the rail is affordable yet, and an
        // unaffordable unlock is a no-op that opens nothing. (Successful out-of-order
        // unlocking is proven at the model layer in GauntletCoreTests.)
        XCTAssertFalse(s.canUnlockPack(2))
        XCTAssertFalse(s.unlockPack(2))
        XCTAssertFalse(s.isPackUnlocked(2))
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

    func testAbandonReturnsToTrainerSelectWithoutBanking() {
        let (s, _) = makeState(seed: 3)
        s.chooseTrainer(.neutral)
        s.startRun(tier: .easy)
        s.abandonRun()
        XCTAssertEqual(s.phase, .trainerSelect)
        XCTAssertNil(s.run)
        XCTAssertEqual(s.progress.xp(forTrainer: "neutral"), 0, "an abandoned run banks nothing")
        XCTAssertFalse(s.progress.isUnlocked(.medium, forTrainer: "neutral"))
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
            XCTAssertGreaterThan(clear!.xpGained, 0)
            XCTAssertEqual(clear!.unlockedTier, .medium, "clearing Easy unlocks Medium")
            XCTAssertTrue(s.progress.isUnlocked(.medium, forTrainer: "neutral"))

            // Durable: the clear is on disk in the progress file.
            let reloaded = GauntletProgressStore(directory: dir).load()
            XCTAssertTrue(reloaded.isUnlocked(.medium, forTrainer: "neutral"))
            XCTAssertGreaterThan(reloaded.xp(forTrainer: "neutral"), 0)

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
                      run.marginalAppraisal(of: card) > contribution(of: idx, in: run) {
                s.swap(card, forShowcaseIndex: idx)
            } else {
                s.sell(card)
            }
        }
    }

    /// How much the Showcase card at `idx` currently contributes to the appraisal.
    private func contribution(of idx: Int, in run: GauntletRun) -> Double {
        var without = run.showcase
        without.remove(at: idx)
        let base = GauntletRun.appraise(without,
                                        evoLineBonus: run.evoLineBonus,
                                        appraisalMult: run.mods.appraisalMult)
        return run.showcaseAppraisal - base
    }
}
