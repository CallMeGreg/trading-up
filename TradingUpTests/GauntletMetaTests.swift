import XCTest
@testable import TradingUp

/// Gauntlet meta progression and rewards: the tunable economy knobs (target curve,
/// interest, stipends), the cross-run `GauntletProgress` (per-Trainer tier unlocks,
/// accomplishment badges, the roster-earning milestones and the mystery Trainer)
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

    // MARK: Trainer skill profiles (docs/DESIGN.md §14.3)

    /// The shipped roster's skill graphs — the source of truth the cards draw and
    /// the run mods derive from. Locked here so a casual reshuffle can't silently
    /// rebalance the mode.
    func testTrainerSkillProfilesMatchTheDesign() {
        func expect(_ id: String, _ e: Int, _ a: Int, _ s: Int, _ g: Int, _ i: Int) {
            guard let t = Trainer.byId(id) else { return XCTFail("missing \(id)") }
            XCTAssertEqual([t.skills.energy, t.skills.aura, t.skills.selling, t.skills.grading, t.skills.inventory],
                           [e, a, s, g, i], "\(t.name)'s profile drifted")
        }
        expect("neutral",   3, 3, 3, 3, 3)
        expect("ripper",    5, 2, 2, 1, 4)
        expect("curator",   2, 4, 1, 3, 5)
        expect("appraiser", 2, 5, 2, 2, 3)
        expect("grader",    2, 3, 2, 5, 3)
        expect("merchant",  3, 2, 5, 2, 3)
        expect("red",       5, 5, 1, 1, 1)   // the mystery glass cannon
    }

    /// `3` is the neutral pivot: a flat-3 profile confers exactly no edge.
    func testNeutralProfileConfersNoEdge() {
        XCTAssertEqual(TrainerSkills.neutral.runMods, .none)
        XCTAssertEqual(Trainer.neutral.mods, .none)
    }

    /// Skill *magnitudes* are live now, so every spiky Trainer derives a real,
    /// correctly-signed edge: a specialty helps on its axis and a weakness bites an
    /// equal amount. The verify harness proves the balance stays a sidegrade; this
    /// guards the *shape* so a future retune can't silently flip a sign. Wiring up
    /// or removing a lever must update this test.
    func testSkillMagnitudesShapeEachTrainersEdge() {
        // The Rookie stays the exact neutral pivot.
        XCTAssertEqual(Trainer.neutral.mods, .none)

        // Each specialist's high axis is a bonus of the right kind…
        XCTAssertGreaterThan(Trainer.byId("ripper")!.mods.bonusRipChance, 0,
                             "the Ripper's 5-Energy is a bonus-rip chance")
        XCTAssertGreaterThan(Trainer.byId("appraiser")!.mods.auraMult, 1,
                             "Fred's 5-Aura multiplies score above ×1")
        let sally = Trainer.byId("merchant")!.mods
        XCTAssertGreaterThan(sally.sellbackBonus, 0, "the Merchant's 5-Selling lifts sell-back")
        XCTAssertGreaterThan(sally.stipendMult, 1, "…and the round stipend")
        XCTAssertGreaterThan(sally.startingCashBonus, 0, "…and the seed cash")
        let lucy = Trainer.byId("grader")!.mods
        XCTAssertGreaterThan(lucy.gradeLuckBonus, 0, "the Grader's 5-Grading rolls with luck")
        XCTAssertLessThan(lucy.gradeFeeMult, 1, "…and pays cheaper fees")
        XCTAssertGreaterThan(Trainer.byId("curator")!.mods.extraSlots, 0,
                             "the Curator's 5-Inventory adds Showcase slots")

        // …and each low axis bites, equal and opposite.
        let ripper = Trainer.byId("ripper")!.mods
        XCTAssertGreaterThan(ripper.gradeFeeMult, 1, "the Ripper's 1-Grading pays pricier fees")
        XCTAssertLessThan(ripper.gradeLuckBonus, 0, "…and rolls grades with disadvantage")
        let curator = Trainer.byId("curator")!.mods
        XCTAssertLessThan(curator.startingCashBonus, 0, "the Curator's 1-Selling opens with less cash")
        XCTAssertLessThan(curator.bonusRipChance, 0, "the Curator's 2-Energy risks losing a rip")

        // The model is symmetric: a flat 5 and a flat 1 are equal and opposite.
        let hi = GauntletSkillTuning.runMods(for: TrainerSkills(energy: 5, aura: 5, selling: 5, grading: 5, inventory: 5))
        let lo = GauntletSkillTuning.runMods(for: TrainerSkills(energy: 1, aura: 1, selling: 1, grading: 1, inventory: 1))
        XCTAssertEqual(hi.bonusRipChance, -lo.bonusRipChance, accuracy: 1e-9)
        XCTAssertEqual(hi.auraMult - 1, -(lo.auraMult - 1), accuracy: 1e-9)
        XCTAssertEqual(hi.sellbackBonus, -lo.sellbackBonus, accuracy: 1e-9)
        XCTAssertEqual(hi.startingCashBonus, -lo.startingCashBonus, accuracy: 1e-9)
        XCTAssertEqual(hi.gradeFeeMult - 1, -(lo.gradeFeeMult - 1), accuracy: 1e-9)
        XCTAssertEqual(hi.extraSlots, -lo.extraSlots)
    }

    /// The card / harness / docs read a Trainer's real effects off `effectLines`,
    /// derived from the same tuning constants as the mods. Neutral lists nothing;
    /// a spiky Trainer lists exactly the axes that sit off the neutral 3.
    func testEffectLinesMatchOffNeutralSkills() {
        XCTAssertTrue(TrainerSkills.neutral.effectLines.isEmpty, "a flat-3 Rookie has no effects to show")
        let ripper = Trainer.byId("ripper")!               // E5 A2 S2 G1 I4 — every axis off neutral
        XCTAssertEqual(ripper.skills.effectLines.map(\.axis), [.energy, .aura, .selling, .grading, .inventory])
        let grader = Trainer.byId("grader")!               // E2 A3 S2 G5 I3 — Aura & Inventory sit at 3
        XCTAssertEqual(grader.skills.effectLines.map(\.axis), [.energy, .selling, .grading])
    }

    // MARK: Progress — unlock ladder

    func testFreshProgressHasOnlyEasy() {
        let p = GauntletProgress()
        XCTAssertTrue(p.isUnlocked(.easy, forTrainer: "ripper"))
        XCTAssertFalse(p.isUnlocked(.medium, forTrainer: "ripper"))
        XCTAssertFalse(p.isUnlocked(.hard, forTrainer: "ripper"))
        XCTAssertEqual(p.unlockedTiers(forTrainer: "ripper"), [.easy])
    }

    func testClearingUnlocksTheNextTierForThatTrainer() {
        var p = GauntletProgress()
        let r1 = p.recordClear(trainerId: "ripper", tier: .easy)
        XCTAssertEqual(r1.unlockedTier, .medium)
        XCTAssertTrue(p.isUnlocked(.medium, forTrainer: "ripper"))
        XCTAssertFalse(p.isUnlocked(.hard, forTrainer: "ripper"))

        let r2 = p.recordClear(trainerId: "ripper", tier: .medium)
        XCTAssertEqual(r2.unlockedTier, .hard)
        XCTAssertTrue(p.isUnlocked(.hard, forTrainer: "ripper"))

        // Clearing Hard opens nothing further; re-clearing a tier announces nothing.
        XCTAssertNil(p.recordClear(trainerId: "ripper", tier: .hard).unlockedTier)
        XCTAssertNil(p.recordClear(trainerId: "ripper", tier: .easy).unlockedTier)
        XCTAssertEqual(p.clearedTiers(forTrainer: "ripper"), [.easy, .medium, .hard])
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

    /// A Trainer's cleared-tier set is exactly the accomplishment-badge data its
    /// card renders — one entry per difficulty beaten with that Trainer, isolated
    /// per Trainer.
    func testAccomplishmentBadgesTrackClearedTiers() {
        var p = GauntletProgress()
        XCTAssertTrue(p.clearedTiers(forTrainer: "grader").isEmpty)
        p.recordClear(trainerId: "grader", tier: .easy)
        p.recordClear(trainerId: "grader", tier: .medium)
        XCTAssertEqual(p.clearedTiers(forTrainer: "grader"), [.easy, .medium])
        XCTAssertFalse(p.hasCleared(.hard, trainer: "grader"))
        XCTAssertTrue(p.clearedTiers(forTrainer: "ripper").isEmpty, "badges don't bleed across Trainers")
    }

    // MARK: Progress — the mystery Trainer (Red)

    /// Red stays locked until every *other* Trainer has cleared Hard; the final
    /// Hard clear reveals it, announced exactly once through `ingest`.
    func testMysteryTrainerRevealsOnlyAfterEveryTrainerClearsHard() {
        var p = GauntletProgress()
        let others = ([Trainer.neutral] + Trainer.roster.filter { !$0.mysteryUntilUnlocked }).map(\.id)

        for id in others.dropLast() { p.recordClear(trainerId: id, tier: .hard) }
        XCTAssertFalse(p.isMysteryTrainerEarned)
        XCTAssertTrue(p.ingest(GauntletRunReport()).isEmpty)
        XCTAssertFalse(p.isTrainerUnlocked("red"))

        p.recordClear(trainerId: others.last!, tier: .hard)
        XCTAssertTrue(p.isMysteryTrainerEarned)
        XCTAssertEqual(p.ingest(GauntletRunReport()), ["red"], "the final Hard clear reveals Red, once")
        XCTAssertTrue(p.isTrainerUnlocked("red"))
        XCTAssertFalse(p.ingest(GauntletRunReport()).contains("red"), "never re-announced")
    }

    /// A concealed Red card counts how many other Trainers have cleared Hard — the
    /// "beat Hard with everyone" progress line.
    func testMysteryUnlockProgressCountsHardClears() {
        var p = GauntletProgress()
        let red = Trainer.byId("red")!
        let need = ([Trainer.neutral] + Trainer.roster.filter { !$0.mysteryUntilUnlocked }).count
        XCTAssertEqual(p.unlockProgress(for: red)?.need, need)
        XCTAssertEqual(p.unlockProgress(for: red)?.have, 0)
        p.recordClear(trainerId: "ripper", tier: .hard)
        XCTAssertEqual(p.unlockProgress(for: red)?.have, 1)
    }

    func testProgressSanitizeDropsUnknownClearedTiers() {
        var p = GauntletProgress(clearedTiersByTrainer: ["ripper": ["easy"],
                                                         "ghost_trainer": ["easy", "hard"]])
        p.sanitize()
        XCTAssertEqual(p.clearedTiers(forTrainer: "ripper"), [.easy])
        XCTAssertTrue(p.clearedTiers(forTrainer: "ghost_trainer").isEmpty, "a dead Trainer id is dropped on load")
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

    func testRewardGuaranteesABrandNewCardWhenOneExists() {
        // Own every common but one, with no art earned yet: the whole rarity is
        // eligible, but only the unowned common would be brand new. However the
        // shuffle falls, that lone new card must always be offered.
        let commons = CardDatabase.all.filter { $0.rarity == .common }
        XCTAssertGreaterThan(commons.count, GauntletEconomy.rewardOptionCount)
        let newCard = commons.first!.id
        let owned = Set(commons.dropFirst().map(\.id))
        for seed: UInt64 in [1, 2, 3, 7, 42, 99, 128, 512] {
            var rng = SeededRNG(seed)
            guard case .extendedArt(let opts) = GauntletReward.payout(
                tier: .easy, earnedExtendedArt: [], ownedCardIds: owned, using: &rng) else {
                return XCTFail("expected extended-art options")
            }
            XCTAssertTrue(opts.contains { $0.cardId == newCard },
                          "the lone brand-new common must always be offered (seed \(seed))")
        }
    }

    func testRewardStillFillsRowWithReArtWhenNothingNewRemains() {
        // Own every common but earn no art: there's nothing brand new to offer, so
        // the row falls back to a full set of re-art options on owned Sprytes.
        let commons = CardDatabase.all.filter { $0.rarity == .common }
        let owned = Set(commons.map(\.id))
        var rng = SeededRNG(4)
        guard case .extendedArt(let opts) = GauntletReward.payout(
            tier: .easy, earnedExtendedArt: [], ownedCardIds: owned, using: &rng) else {
            return XCTFail("expected extended-art options")
        }
        XCTAssertEqual(opts.count, GauntletEconomy.rewardOptionCount)
        XCTAssertTrue(opts.allSatisfy { $0.rarity == .common })
        XCTAssertTrue(opts.allSatisfy { owned.contains($0.cardId) }, "every option is already-owned re-art")
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

    func testOwnedCardIdsTracksBankedCopiesNotArtUnlocks() {
        var binder = Binder()
        XCTAssertTrue(binder.ownedCardIds.isEmpty)
        binder.record([CardInstance(cardId: "S1-001"), CardInstance(cardId: "S1-002")])
        XCTAssertEqual(binder.ownedCardIds, ["S1-001", "S1-002"])
        // Unlocking art without banking a copy is not ownership.
        XCTAssertTrue(binder.earnExtendedArt("S1-003"))
        XCTAssertFalse(binder.ownedCardIds.contains("S1-003"))
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
/// a player's unlocked tiers or cleared-tier badges.
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
        p.recordClear(trainerId: "ripper", tier: .easy)   // unlock medium + bank the clear
        XCTAssertTrue(store.save(p))
        let back = store.load()
        XCTAssertTrue(back.isUnlocked(.medium, forTrainer: "ripper"))
        XCTAssertTrue(back.hasCleared(.easy, trainer: "ripper"))
    }

    func testNewerSchemaFileIsNotClobbered() {
        // A file written by a hypothetical future build.
        let futuristic = """
        {"schemaVersion": \(GauntletProgressFile.currentVersion + 1), "progress": {"clearedTiersByTrainer": {"ripper": ["easy","medium","hard"]}, "unlockedTrainerKeys": ["ripper"]}}
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
        XCTAssertTrue(onDisk.contains("\"ripper\": [\"easy\",\"medium\",\"hard\"]"))
    }
}
