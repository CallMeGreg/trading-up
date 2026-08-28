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
        let base = GauntletEconomy.roundClearStipend(.easy, round: 1, aura: GauntletEconomy.target(.easy, round: 1))
        let over = GauntletEconomy.roundClearStipend(.easy, round: 1, aura: GauntletEconomy.target(.easy, round: 1) + 100)
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

    // MARK: Trainer level scaling (docs/DESIGN.md §14.3)

    /// A freshly-unlocked Trainer plays at its shipped level-1 values, and levels
    /// below 1 (how the harness constructs a roster Trainer) read as that same floor
    /// — so scaling is a pure upgrade layered on top of the base advantage.
    func testTrainerAdvantageStartsAtBaseline() {
        for base in Trainer.roster {
            var lvl1 = base; lvl1.level = 1
            XCTAssertEqual(lvl1.activeMods, base.baseMods, "\(base.name) at level 1 should equal its base advantage")
            var lvl0 = base; lvl0.level = 0
            XCTAssertEqual(lvl0.activeMods, base.baseMods, "\(base.name) below level 1 clamps to the base advantage")
        }
    }

    /// Scaling climbs monotonically and lands on the exact levers we tuned — a
    /// likelihood or a rate, from a ~20% level-1 baseline to its full ceiling.
    func testTrainerScalingClimbsToItsCeiling() {
        let cap = GauntletEconomy.maxTrainerLevel

        // Ripper: a per-round *chance* of a bonus rip, 0.12 → 0.60; the flat +1 stays.
        let ripper = Trainer.byId("ripper")!
        func ripChance(_ l: Int) -> Double { var t = ripper; t.level = l; return t.activeMods.bonusRipChance }
        XCTAssertEqual(ripChance(1), 0.12, accuracy: 1e-9)
        XCTAssertEqual(ripChance(cap), 0.60, accuracy: 1e-9)
        XCTAssertGreaterThan(ripChance(6), ripChance(3))
        XCTAssertEqual(ripper.baseMods.extraRipsPerRound, 1)
        XCTAssertEqual({ var t = ripper; t.level = cap; return t.activeMods.extraRipsPerRound }(), 1)

        // Farmer (id "appraiser"): global Aura multiplier, ×1.06 → ×1.30.
        let appraiser = Trainer.byId("appraiser")!
        func aura(_ l: Int) -> Double { var t = appraiser; t.level = l; return t.activeMods.auraMult }
        XCTAssertEqual(aura(1), 1.06, accuracy: 1e-9)
        XCTAssertEqual(aura(cap), 1.30, accuracy: 1e-9)
        XCTAssertGreaterThan(aura(cap), aura(1))

        // Grader: grade *luck* 0.09 → 0.45 and a fee that drops 0.86 → 0.3.
        let grader = Trainer.byId("grader")!
        func luck(_ l: Int) -> Double { var t = grader; t.level = l; return t.activeMods.gradeLuckBonus }
        func fee(_ l: Int) -> Double { var t = grader; t.level = l; return t.activeMods.gradeFeeMult }
        XCTAssertEqual(luck(1), 0.09, accuracy: 1e-9)
        XCTAssertEqual(luck(cap), 0.45, accuracy: 1e-9)
        XCTAssertEqual(fee(cap), 0.30, accuracy: 1e-9)
        XCTAssertGreaterThan(luck(cap), luck(1))
        XCTAssertLessThan(fee(cap), fee(1))

        // Merchant: economy rates all grow toward their ceiling.
        let merchant = Trainer.byId("merchant")!
        var mMax = merchant; mMax.level = cap
        XCTAssertEqual(mMax.activeMods.sellbackBonus, 0.16, accuracy: 1e-9)
        XCTAssertEqual(mMax.activeMods.stipendMult, 1.60, accuracy: 1e-9)
        XCTAssertEqual(mMax.activeMods.startingCashBonus, 50, accuracy: 1e-9)

        // Curator: evolution-line bonus rate grows +0.12 → +0.60.
        let curator = Trainer.byId("curator")!
        func evo(_ l: Int) -> Double { var t = curator; t.level = l; return t.activeMods.evoLineBonusBonus }
        XCTAssertEqual(evo(1), 0.12, accuracy: 1e-9)
        XCTAssertEqual(evo(cap), 0.60, accuracy: 1e-9)
        XCTAssertGreaterThan(evo(cap), evo(1))
    }

    /// Every specialist opens level 1 at `baselineFraction` (~20%) of its max
    /// potential on the continuous levers — a reasonable baseline with real room to
    /// grow — and reaches 100% at the cap. Integer identity floors are exempt (you
    /// can't own a fifth of a Showcase slot).
    func testEveryTrainerStartsAtItsBaselineFractionOfMax() {
        let f = Trainer.baselineFraction
        XCTAssertEqual(f, 0.20, accuracy: 1e-9)
        for tr in Trainer.roster {
            guard let maxM = tr.maxMods else { continue }
            var lvl1 = tr; lvl1.level = 1
            let a = lvl1.activeMods
            func frac(_ name: String, _ v: Double, _ vmax: Double) {
                XCTAssertEqual(v, vmax * f, accuracy: 1e-9,
                               "\(tr.name) \(name) should open at \(Int(f * 100))% of its max")
            }
            frac("bonus-rip chance", a.bonusRipChance, maxM.bonusRipChance)
            frac("evolution bonus", a.evoLineBonusBonus, maxM.evoLineBonusBonus)
            frac("grade luck", a.gradeLuckBonus, maxM.gradeLuckBonus)
            frac("sell-back", a.sellbackBonus, maxM.sellbackBonus)
            frac("seed cash", a.startingCashBonus, maxM.startingCashBonus)
            frac("Aura bonus", a.auraMult - 1, maxM.auraMult - 1)
            frac("payout bonus", a.stipendMult - 1, maxM.stipendMult - 1)
            frac("grade-fee cut", 1 - a.gradeFeeMult, 1 - maxM.gradeFeeMult)
        }
    }

    /// The Curator's second Showcase slot is an end-of-track capstone — an integer
    /// lever must not spike mid-track, so it appears only at the very cap.
    func testCuratorSecondSlotIsACapstone() {
        let curator = Trainer.byId("curator")!
        func slots(_ l: Int) -> Int { var t = curator; t.level = l; return t.activeMods.extraSlots }
        XCTAssertEqual(slots(1), 1)
        XCTAssertEqual(slots(GauntletEconomy.maxTrainerLevel - 1), 1, "the second slot must not arrive before the cap")
        XCTAssertEqual(slots(GauntletEconomy.maxTrainerLevel), 2)
    }

    /// The Rookie never scales — it stays the harness's neutral, no-edge baseline.
    func testNeutralTrainerNeverScales() {
        var maxed = Trainer.neutral; maxed.level = GauntletEconomy.maxTrainerLevel
        XCTAssertEqual(maxed.activeMods, .none)
    }

    // MARK: Progress — unlock ladder

    func testFreshProgressHasOnlyEasy() {
        let p = GauntletProgress()
        XCTAssertTrue(p.isUnlocked(.easy, forTrainer: "ripper"))
        XCTAssertFalse(p.isUnlocked(.medium, forTrainer: "ripper"))
        XCTAssertFalse(p.isUnlocked(.hard, forTrainer: "ripper"))
        XCTAssertEqual(p.unlockedTiers(forTrainer: "ripper"), [.easy])
    }

    func testClearingUnlocksTheNextTierAndBanksXP() {
        var p = GauntletProgress()
        let r1 = p.recordClear(trainerId: "ripper", tier: .easy)
        XCTAssertEqual(r1.unlockedTier, .medium)
        XCTAssertEqual(r1.xpGained, GauntletEconomy.clearXP(.easy))
        XCTAssertTrue(p.isUnlocked(.medium, forTrainer: "ripper"))
        XCTAssertFalse(p.isUnlocked(.hard, forTrainer: "ripper"))

        let r2 = p.recordClear(trainerId: "ripper", tier: .medium)
        XCTAssertEqual(r2.unlockedTier, .hard)
        XCTAssertTrue(p.isUnlocked(.hard, forTrainer: "ripper"))

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
        XCTAssertFalse(p.isUnlocked(.medium, forTrainer: "ripper"))
        XCTAssertEqual(p.xp(forTrainer: "ripper"),
                       3 * GauntletEconomy.roundClearXP(.medium) + 4 * GauntletEconomy.roundClearXP(.easy))
    }

    // The ladder is walked once per Trainer (req 4): a clear with one Trainer must
    // not open the next tier for a different Trainer.
    func testTierUnlocksAreIsolatedPerTrainer() {
        var p = GauntletProgress()
        p.recordClear(trainerId: "ripper", tier: .easy)

        XCTAssertTrue(p.isUnlocked(.medium, forTrainer: "ripper"), "the clearing Trainer unlocks Medium")
        XCTAssertFalse(p.isUnlocked(.medium, forTrainer: "grader"),
                       "another Trainer must still earn its own Easy clear first")
        XCTAssertEqual(p.unlockedTiers(forTrainer: "grader"), [.easy])
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
        r.maxShowcase = 12         // Curator (≥ 12)
        r.bestRoundScore = 500     // Farmer (≥ 500)
        r.maxCashHeld = 250        // Merchant (≥ 250)
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
        XCTAssertTrue(p.isUnlocked(.easy, forTrainer: "ripper"))
        XCTAssertFalse(p.isUnlocked(.hard, forTrainer: "ripper"))
    }

    func testSaveAndReloadRoundTrips() {
        var p = GauntletProgress()
        p.recordClear(trainerId: "ripper", tier: .easy)   // unlock medium + xp
        XCTAssertTrue(store.save(p))
        let back = store.load()
        XCTAssertTrue(back.isUnlocked(.medium, forTrainer: "ripper"))
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
        XCTAssertFalse(loaded.isUnlocked(.hard, forTrainer: "ripper"))
        XCTAssertFalse(store.canSave())
        XCTAssertFalse(store.save(GauntletProgress()))

        // The original bytes are still on disk untouched.
        let onDisk = try! String(contentsOf: url)
        XCTAssertTrue(onDisk.contains("\"ripper\": 42"))
    }
}
