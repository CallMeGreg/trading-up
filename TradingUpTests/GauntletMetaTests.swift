import XCTest
@testable import TradingUp

/// Gauntlet meta progression and rewards: the tunable economy knobs (target curve,
/// interest, XP), the cross-run `GauntletProgress` (tier unlocks + Trainer levels)
/// and its store, the choose-1-of-3 Extended-Art win reward, and the Binder's
/// cosmetic Extended-Art layer. See docs/DESIGN.md §14.3/§14.6/§14.8.
final class GauntletMetaTests: XCTestCase {

    // MARK: Economy knobs

    func testTargetCurveRisesAndBossSpikes() {
        for tier in GauntletTier.allCases {
            for r in 2...GauntletEconomy.rounds(tier) {
                XCTAssertGreaterThan(GauntletEconomy.target(tier, round: r),
                                     GauntletEconomy.target(tier, round: r - 1),
                                     "\(tier) target must rise every round")
            }
        }
        // Only Hard has a boss finale, and it spikes the bar above the smooth ramp.
        let bossR = GauntletEconomy.rounds(.hard)
        XCTAssertTrue(GauntletEconomy.isBossRound(.hard, round: bossR))
        XCTAssertFalse(GauntletEconomy.isBossRound(.easy, round: GauntletEconomy.rounds(.easy)))
        let unspiked = GauntletEconomy.baseTarget(.hard) * pow(GauntletEconomy.targetGrowth(.hard), Double(bossR - 1))
        XCTAssertGreaterThan(GauntletEconomy.target(.hard, round: bossR), unspiked * 1.4)
    }

    func testInterestIsCappedAndLinearBelowIt() {
        XCTAssertEqual(GauntletEconomy.interest(on: 100), 100 * GauntletEconomy.interestRate, accuracy: 1e-9)
        XCTAssertEqual(GauntletEconomy.interest(on: 1_000_000), GauntletEconomy.interestCap)
    }

    func testStipendRewardsOvershoot() {
        let base = GauntletEconomy.roundClearStipend(.easy, round: 1, appraisal: GauntletEconomy.target(.easy, round: 1))
        let over = GauntletEconomy.roundClearStipend(.easy, round: 1, appraisal: GauntletEconomy.target(.easy, round: 1) + 100)
        XCTAssertGreaterThan(over, base, "pushing past the bar pays more")
    }

    // MARK: XP / level curve

    func testTrainerLevelCurveIsMonotonicAndCapped() {
        var last = 0
        for xp in 0...200 {
            let l = GauntletEconomy.trainerLevel(forXP: xp)
            XCTAssertGreaterThanOrEqual(l, last)
            last = l
        }
        XCTAssertEqual(GauntletEconomy.trainerLevel(forXP: 0), 1)
        XCTAssertEqual(GauntletEconomy.trainerLevel(forXP: 1_000_000), GauntletEconomy.maxTrainerLevel)
        XCTAssertNil(GauntletEconomy.xpToNextLevel(fromXP: 1_000_000))
    }

    func testHardClearPaysTheMostXP() {
        XCTAssertGreaterThan(GauntletEconomy.clearXP(.hard), GauntletEconomy.clearXP(.medium))
        XCTAssertGreaterThan(GauntletEconomy.clearXP(.medium), GauntletEconomy.clearXP(.easy))
    }

    // MARK: Progress — unlock ladder

    func testFreshProgressHasOnlyEasy() {
        let p = GauntletProgress()
        XCTAssertTrue(p.isUnlocked(.easy))
        XCTAssertFalse(p.isUnlocked(.medium))
        XCTAssertFalse(p.isUnlocked(.hard))
        XCTAssertEqual(p.unlockedTiers, [.easy])
    }

    func testClearingUnlocksTheNextTierAndBanksXP() {
        var p = GauntletProgress()
        let r1 = p.recordClear(trainerId: "ripper", tier: .easy)
        XCTAssertEqual(r1.unlockedTier, .medium)
        XCTAssertEqual(r1.xpGained, GauntletEconomy.clearXP(.easy))
        XCTAssertTrue(p.isUnlocked(.medium))
        XCTAssertFalse(p.isUnlocked(.hard))

        let r2 = p.recordClear(trainerId: "ripper", tier: .medium)
        XCTAssertEqual(r2.unlockedTier, .hard)
        XCTAssertTrue(p.isUnlocked(.hard))

        // Clearing Hard unlocks nothing further, but still banks XP.
        let r3 = p.recordClear(trainerId: "ripper", tier: .hard)
        XCTAssertNil(r3.unlockedTier)
        XCTAssertEqual(p.xp(forTrainer: "ripper"),
                       GauntletEconomy.clearXP(.easy) + GauntletEconomy.clearXP(.medium) + GauntletEconomy.clearXP(.hard))
        XCTAssertEqual(p.level(forTrainer: "ripper"), GauntletEconomy.trainerLevel(forXP: p.xp(forTrainer: "ripper")))
    }

    func testLevelUpIsReported() {
        var p = GauntletProgress()
        var leveledUpAtLeastOnce = false
        for _ in 0..<12 {
            let r = p.recordClear(trainerId: "grader", tier: .hard)
            if r.leveledUp { leveledUpAtLeastOnce = true }
        }
        XCTAssertTrue(leveledUpAtLeastOnce)
        XCTAssertGreaterThan(p.level(forTrainer: "grader"), 1)
    }

    // MARK: Progress — partial runs (req 3)

    func testPartialRunBanksPerRoundXPButUnlocksNothing() {
        var p = GauntletProgress()
        let r = p.recordLoss(trainerId: "ripper", tier: .medium, roundsCleared: 3)
        XCTAssertEqual(r.xpGained, 3 * GauntletEconomy.roundClearXP(.medium))
        XCTAssertNil(r.unlockedTier)
        // A loss on Easy must never open Medium — only a win does.
        let r2 = p.recordLoss(trainerId: "ripper", tier: .easy, roundsCleared: 4)
        XCTAssertNil(r2.unlockedTier)
        XCTAssertFalse(p.isUnlocked(.medium))
        XCTAssertEqual(p.xp(forTrainer: "ripper"),
                       3 * GauntletEconomy.roundClearXP(.medium) + 4 * GauntletEconomy.roundClearXP(.easy))
    }

    func testRoundOneLossBanksNoXP() {
        var p = GauntletProgress()
        let r = p.recordLoss(trainerId: "ripper", tier: .hard, roundsCleared: 0)
        XCTAssertEqual(r.xpGained, 0)
        XCTAssertFalse(r.leveledUp)
        XCTAssertEqual(p.xp(forTrainer: "ripper"), 0)
    }

    func testWinningBeatsLosingWithTheSameRoundsCleared() {
        let tier = GauntletTier.hard
        let rounds = GauntletEconomy.rounds(tier)
        let won = GauntletEconomy.runXP(tier: tier, roundsCleared: rounds, won: true)
        let lost = GauntletEconomy.runXP(tier: tier, roundsCleared: rounds, won: false)
        XCTAssertEqual(won - lost, GauntletEconomy.completionBonus(tier))
        XCTAssertEqual(won, GauntletEconomy.clearXP(tier))
    }

    func testLevelThresholdGapsStrictlyGrow() {
        let t = GauntletEconomy.trainerLevelThresholds
        XCTAssertEqual(t.first, 0)
        XCTAssertEqual(t.count, GauntletEconomy.maxTrainerLevel)
        var lastGap = Int.min
        for i in 1..<t.count {
            let gap = t[i] - t[i - 1]
            XCTAssertGreaterThan(gap, lastGap, "level \(i) gap should exceed the previous")
            lastGap = gap
        }
    }

    func testProgressSanitizeDropsUnknownTrainers() {
        var p = GauntletProgress(xpByTrainer: ["ripper": 5, "ghost_trainer": 99])
        p.sanitize()
        XCTAssertEqual(p.xp(forTrainer: "ripper"), 5)
        XCTAssertEqual(p.xp(forTrainer: "ghost_trainer"), 0)
    }

    // MARK: Trainer unlocks (earning the roster)

    func testFreshProgressUnlocksOnlyTheRookie() {
        let p = GauntletProgress()
        XCTAssertTrue(p.isTrainerUnlocked(Trainer.neutral.id))
        for t in Trainer.roster {
            XCTAssertFalse(p.isTrainerUnlocked(t.id), "\(t.name) must be earned")
        }
    }

    func testIngestUnlocksATrainerOnceItsMilestoneIsMet() {
        var p = GauntletProgress()

        // Below the Ripper's 100-pack bar: still locked, nothing announced.
        var short = GauntletRunReport(); short.packsRipped = 60
        XCTAssertTrue(p.ingest(short).isEmpty)
        XCTAssertFalse(p.isTrainerUnlocked("ripper"))

        // Crossing the bar (60 + 40 ≥ 100) unlocks it and reports the id once.
        var more = GauntletRunReport(); more.packsRipped = 40
        XCTAssertEqual(p.ingest(more), ["ripper"])
        XCTAssertTrue(p.isTrainerUnlocked("ripper"))

        // Idempotent: a later run never re-announces an already-earned Trainer.
        var again = GauntletRunReport(); again.packsRipped = 100
        XCTAssertFalse(p.ingest(again).contains("ripper"))
    }

    func testIngestHighWaterMarksUnlockTheirTrainers() {
        var p = GauntletProgress()
        // A single strong run trips several high-water-mark milestones at once.
        var r = GauntletRunReport()
        r.maxShowcase = 9          // Curator
        r.bestRoundScore = 200     // Appraiser
        r.maxCashHeld = 120        // Merchant
        let newly = Set(p.ingest(r))
        XCTAssertTrue(newly.isSuperset(of: ["curator", "appraiser", "merchant"]))
        XCTAssertFalse(p.isTrainerUnlocked("ripper"), "unrelated milestones stay locked")
    }

    func testUnlockProgressClampsToTheThreshold() {
        var p = GauntletProgress()
        let ripper = Trainer.roster.first { $0.id == "ripper" }!
        var r = GauntletRunReport(); r.packsRipped = 140      // overshoots the 100-pack bar
        _ = p.ingest(r)
        let prog = p.unlockProgress(for: ripper)
        XCTAssertEqual(prog?.have, 100, "the progress line clamps have ≤ need")
        XCTAssertEqual(prog?.need, 100)
        XCTAssertNil(p.unlockProgress(for: .neutral), "the Rookie has no criterion")
    }

    func testSanitizeDropsUnknownTrainerUnlocks() {
        var p = GauntletProgress(unlockedTrainerKeys: ["ripper", "ghost_trainer"])
        p.sanitize()
        XCTAssertTrue(p.isTrainerUnlocked("ripper"))
        XCTAssertFalse(p.isTrainerUnlocked("ghost_trainer"), "a dead Trainer id is dropped on load")
    }

    // MARK: Intro explainer flag

    func testIntroSeenFlagIsStickyAndOnlyReportsTheFirstMark() {
        var p = GauntletProgress()
        XCTAssertFalse(p.hasSeenIntro)
        XCTAssertTrue(p.markIntroSeen(), "the first mark reports a change to persist")
        XCTAssertTrue(p.hasSeenIntro)
        XCTAssertFalse(p.markIntroSeen(), "marking an already-seen intro is a no-op")
    }

    // MARK: Reward payout

    func testEasyRewardOffersThreeDistinctFoilCommons() {
        var rng = SeededRNG(11)
        guard case .extendedArt(let opts) = GauntletReward.payout(tier: .easy, earnedExtendedArt: [], using: &rng) else {
            return XCTFail("expected extended-art options")
        }
        XCTAssertEqual(opts.count, GauntletEconomy.rewardOptionCount)
        XCTAssertEqual(Set(opts.map(\.cardId)).count, opts.count, "options are distinct")
        XCTAssertTrue(opts.allSatisfy { $0.rarity == .common })
        XCTAssertTrue(opts.allSatisfy { $0.instance.foil }, "reward copies are foil")
    }

    func testMediumRewardIsUncommon() {
        var rng = SeededRNG(12)
        guard case .extendedArt(let opts) = GauntletReward.payout(tier: .medium, earnedExtendedArt: [], using: &rng) else {
            return XCTFail("expected extended-art options")
        }
        XCTAssertTrue(opts.allSatisfy { $0.rarity == .uncommon })
    }

    func testRewardPrefersUnearnedArt() {
        // Earn every common but one; the offered options must include that one and
        // never exceed the single unearned card with dupes crowding it out.
        let commons = CardDatabase.all.filter { $0.rarity == .common }
        let lastUnearned = commons.last!.id
        let earned = Set(commons.dropLast().map(\.id))
        var rng = SeededRNG(99)
        guard case .extendedArt(let opts) = GauntletReward.payout(tier: .easy, earnedExtendedArt: earned, using: &rng) else {
            return XCTFail("expected extended-art options")
        }
        XCTAssertTrue(opts.contains { $0.cardId == lastUnearned }, "the lone unearned common is offered")
    }

    func testRewardPromotesWhenRarityFullyEarned() {
        // All commons earned → an Easy win promotes to uncommon.
        let earned = Set(CardDatabase.all.filter { $0.rarity == .common }.map(\.id))
        var rng = SeededRNG(5)
        guard case .extendedArt(let opts) = GauntletReward.payout(tier: .easy, earnedExtendedArt: earned, using: &rng) else {
            return XCTFail("expected promoted options")
        }
        XCTAssertTrue(opts.allSatisfy { $0.rarity == .uncommon })
    }

    func testConsolationWhenCatalogueComplete() {
        let all = Set(CardDatabase.all.map(\.id))
        XCTAssertTrue(GauntletReward.isCatalogueComplete(earnedExtendedArt: all))
        var rng = SeededRNG(1)
        XCTAssertEqual(GauntletReward.payout(tier: .hard, earnedExtendedArt: all, using: &rng), .consolation)
    }

    // MARK: Binder Extended-Art layer

    func testExtendedArtIsCosmeticAndNeverChangesValue() {
        var binder = Binder()
        let id = "S1-001"
        binder.record([CardInstance(cardId: id, foil: true, grade: 9)])
        let valueBefore = binder.best(for: id)!.currentValue

        XCTAssertFalse(binder.hasExtendedArt(id))
        XCTAssertTrue(binder.earnExtendedArt(id))
        XCTAssertTrue(binder.hasExtendedArt(id))
        XCTAssertFalse(binder.earnExtendedArt(id), "earning twice is idempotent")
        XCTAssertEqual(binder.best(for: id)!.currentValue, valueBefore, "art unlock must not touch value")
        XCTAssertEqual(binder.extendedArtCount, 1)
    }

    func testExtendedArtCanBeEarnedBeforeOwningACopy() {
        var binder = Binder()
        let id = "S3-002"
        XCTAssertTrue(binder.earnExtendedArt(id))   // art unlock is independent of the value-best copy
        XCTAssertTrue(binder.hasExtendedArt(id))
        XCTAssertNil(binder.best(for: id))          // still no value copy recorded
    }

    func testEarnExtendedArtRejectsUnknownCard() {
        var binder = Binder()
        XCTAssertFalse(binder.earnExtendedArt("NOT-A-CARD"))
        XCTAssertEqual(binder.extendedArtCount, 0)
    }

    func testBinderExtendedArtSurvivesRoundTrip() {
        var binder = Binder()
        binder.record([CardInstance(cardId: "S1-001", foil: true)])
        binder.earnExtendedArt("S1-001")
        let data = try! JSONEncoder().encode(BinderFile(binder: binder))
        let back = try! JSONDecoder().decode(BinderFile.self, from: data).binder
        XCTAssertTrue(back.hasExtendedArt("S1-001"))
        XCTAssertEqual(back.best(for: "S1-001")!.currentValue, binder.best(for: "S1-001")!.currentValue)
    }
}

/// The Gauntlet progress store, held to the same never-destroy-on-failure bar as
/// `BinderStore`: a transient decode hiccup or a newer-schema file must never wipe
/// a player's unlocked tiers or Trainer XP.
final class GauntletProgressStoreTests: XCTestCase {
    var dir: URL!
    var store: GauntletProgressStore!

    override func setUp() {
        super.setUp()
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tu_gauntlet_tests_\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        store = GauntletProgressStore(directory: dir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    func testMissingFileLoadsFreshProgress() {
        let p = store.load()
        XCTAssertTrue(p.isUnlocked(.easy))
        XCTAssertFalse(p.isUnlocked(.hard))
    }

    func testSaveAndReloadRoundTrips() {
        var p = GauntletProgress()
        p.recordClear(trainerId: "ripper", tier: .easy)   // unlock medium + xp
        XCTAssertTrue(store.save(p))
        let back = store.load()
        XCTAssertTrue(back.isUnlocked(.medium))
        XCTAssertEqual(back.xp(forTrainer: "ripper"), GauntletEconomy.clearXP(.easy))
    }

    func testNewerSchemaFileIsNotClobbered() {
        // A file written by a hypothetical future build.
        let futuristic = """
        {"schemaVersion": \(GauntletProgressFile.currentVersion + 1), "progress": {"xpByTrainer": {"ripper": 42}, "unlockedTierKeys": ["easy","medium","hard"]}}
        """
        let url = dir.appendingPathComponent("tradingup_gauntlet.json")
        try! futuristic.data(using: .utf8)!.write(to: url)

        // Load refuses it (fresh progress) and, crucially, canSave() is false so we
        // never overwrite the newer bytes.
        let loaded = store.load()
        XCTAssertFalse(loaded.isUnlocked(.hard))
        XCTAssertFalse(store.canSave())
        XCTAssertFalse(store.save(GauntletProgress()))

        // The original bytes are still on disk untouched.
        let onDisk = try! String(contentsOf: url)
        XCTAssertTrue(onDisk.contains("\"ripper\": 42"))
    }
}
