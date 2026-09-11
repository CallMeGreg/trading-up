import AVFoundation
import XCTest
@testable import TradingUp

@MainActor
final class AudioPreferencesTests: XCTestCase {
    private func makePreferences(_ configure: (UserDefaults) -> Void = { _ in }) throws -> AudioPreferences {
        let name = "TradingUp.AudioTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        configure(defaults)
        return AudioPreferences(defaults: defaults)
    }

    func testFreshInstallStartsWithQuietMusicAndFullEffectMix() throws {
        let preferences = try makePreferences()
        XCTAssertEqual(preferences.sfx.volume, 1)
        XCTAssertEqual(preferences.music.volume, 0.28, accuracy: 0.0001)
    }

    func testLegacyMutedGameDoesNotUnexpectedlyStartMusic() throws {
        let preferences = try makePreferences { $0.set(false, forKey: "tradingup_sound_enabled") }
        XCTAssertTrue(preferences.sfx.isMuted)
        XCTAssertTrue(preferences.music.isMuted)
    }

    func testExplicitMusicPreferenceTakesPrecedenceOverLegacyMute() throws {
        let preferences = try makePreferences {
            $0.set(false, forKey: "tradingup_sound_enabled")
            $0.set(true, forKey: "tradingup_music_enabled")
            $0.set(0.4, forKey: "tradingup_music_volume")
        }
        XCTAssertEqual(preferences.sfx.volume, 0)
        XCTAssertEqual(preferences.music.volume, 0.4)
    }

    func testLegacyMigrationRunsOnceAndLaterSFXChangesCannotChangeMusicOnRelaunch() throws {
        for legacyMuted in [false, true] {
            let name = "TradingUp.AudioTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }
            defaults.set(!legacyMuted, forKey: "tradingup_sound_enabled")
            let first = AudioPreferences(defaults: defaults)
            XCTAssertEqual(first.music.isMuted, legacyMuted)
            first.sfx.toggleMute()
            let second = AudioPreferences(defaults: defaults)
            XCTAssertEqual(second.music.isMuted, legacyMuted)
            XCTAssertEqual(second.sfx.isMuted, !legacyMuted)
        }
    }

    func testOneTapMuteRestoresPreviousLevelIndependently() throws {
        let preferences = try makePreferences()
        preferences.sfx.volume = 0.63
        preferences.music.volume = 0.19
        preferences.sfx.toggleMute()
        XCTAssertEqual(preferences.sfx.volume, 0)
        XCTAssertEqual(preferences.music.volume, 0.19)
        preferences.sfx.toggleMute()
        XCTAssertEqual(preferences.sfx.volume, 0.63)
        preferences.music.toggleMute()
        XCTAssertEqual(preferences.music.volume, 0)
        XCTAssertEqual(preferences.sfx.volume, 0.63)
        preferences.music.toggleMute()
        XCTAssertEqual(preferences.music.volume, 0.19)
    }

    func testDraggingToZeroRemembersVolumeAndDraggingUpUnmutes() throws {
        let preferences = try makePreferences()
        preferences.music.volume = 0.46
        preferences.music.volume = 0
        XCTAssertTrue(preferences.music.isMuted)
        preferences.music.toggleMute()
        XCTAssertEqual(preferences.music.volume, 0.46)
        preferences.music.isEnabled = false
        preferences.music.volume = 0.32
        XCTAssertTrue(preferences.music.isEnabled)
        XCTAssertEqual(preferences.music.volume, 0.32)
    }

    func testMuteAndRememberedVolumeSurviveRelaunch() throws {
        let name = "TradingUp.AudioTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let first = AudioPreferences(defaults: defaults)
        first.music.volume = 0.41
        first.music.toggleMute()
        first.sfx.volume = 0.72
        let restored = AudioPreferences(defaults: defaults)
        XCTAssertEqual(restored.music.volume, 0)
        XCTAssertEqual(restored.sfx.volume, 0.72)
        restored.music.toggleMute()
        XCTAssertEqual(restored.music.volume, 0.41)
        XCTAssertTrue(defaults.bool(forKey: "tradingup_sound_enabled"))
    }

    func testContinuousDragToZeroRestoresItsStartingLevelNotTheLastTinyStep() throws {
        let preferences = try makePreferences()
        preferences.music.volume = 0.46
        preferences.music.beginVolumeAdjustment()
        for level in [0.31, 0.1, 0.01, 0] { preferences.music.volume = level }
        preferences.music.endVolumeAdjustment()
        XCTAssertTrue(preferences.music.isMuted)
        preferences.music.toggleMute()
        XCTAssertEqual(preferences.music.volume, 0.46)
    }

    func testDragEndingAboveZeroRemembersTheNewLevel() throws {
        let preferences = try makePreferences()
        preferences.music.beginVolumeAdjustment()
        for level in [0.2, 0, 0.15, 0.52] { preferences.music.volume = level }
        preferences.music.endVolumeAdjustment()
        preferences.music.toggleMute()
        preferences.music.toggleMute()
        XCTAssertEqual(preferences.music.volume, 0.52)
    }

    func testFirstSliderUpdateBeforeEditingCallbackStillRestoresTheOriginalLevel() throws {
        let preferences = try makePreferences()
        preferences.music.volume = 0.46
        preferences.music.beginVolumeAdjustment()
        preferences.music.volume = 0.01
        preferences.music.beginVolumeAdjustment()
        preferences.music.volume = 0
        preferences.music.toggleMute()
        XCTAssertEqual(preferences.music.volume, 0.46)
        preferences.music.beginVolumeAdjustment()
        preferences.music.volume = 0.61
        preferences.music.toggleMute()
        preferences.music.toggleMute()
        XCTAssertEqual(preferences.music.volume, 0.61)
    }

    func testClampsFiniteInputAndRejectsNonFiniteInput() throws {
        let preferences = try makePreferences()
        preferences.sfx.volume = 3
        XCTAssertEqual(preferences.sfx.volume, 1)
        preferences.sfx.volume = -.infinity
        XCTAssertEqual(preferences.sfx.volume, 1)
        preferences.sfx.volume = .nan
        XCTAssertEqual(preferences.sfx.volume, 1)
        preferences.sfx.volume = -1
        XCTAssertEqual(preferences.sfx.volume, 0)
        preferences.sfx.toggleMute()
        XCTAssertEqual(preferences.sfx.volume, 1)
    }

    func testLiveVolumeCallbacksSeeTheEffectiveMutedLevel() throws {
        let preferences = try makePreferences()
        var levels: [Double] = []
        preferences.sfx.onChange = { levels.append(preferences.sfx.volume) }
        preferences.sfx.volume = 0.5
        preferences.sfx.toggleMute()
        preferences.sfx.toggleMute()
        XCTAssertEqual(levels, [0.5, 0, 0.5])
        preferences.sfx.onChange = nil
    }
}

@MainActor
final class GauntletAudioFeedbackTests: XCTestCase {
    func testRestoringAnUnchangedRunDoesNotReplayItsStartOrCelebration() {
        let restored = GauntletAudioSnapshot(phase: .ripping, round: 3, aura: 120, rips: 2)
        XCTAssertNil(restored.feedback(after: restored))
    }

    func testNewRunAndChampionshipHaveDistinctEntryCues() {
        XCTAssertEqual(GauntletAudioSnapshot(phase: .ripping, round: 1)
            .feedback(after: .init(phase: .tierSelect)), .runStart)
        XCTAssertEqual(GauntletAudioSnapshot(phase: .ripping, round: 8, championship: true)
            .feedback(after: .init(phase: .shop, round: 8)), .bossRound)
        XCTAssertEqual(GauntletAudioSnapshot(phase: .ripping, round: 2)
            .feedback(after: .init(phase: .shop, round: 2)), .roundStart)
    }

    func testRoundTargetTakesPriorityOverEvolutionAndAura() {
        let old = GauntletAudioSnapshot(phase: .ripping, round: 1, aura: 10)
        let new = GauntletAudioSnapshot(phase: .ripping, round: 1, confetti: 1,
                                       aura: 100, lines: ["line-1"])
        XCTAssertEqual(new.feedback(after: old), .roundClear)
    }

    func testClosingTheRevealDoesNotCelebrateTheSameTargetAgain() {
        let old = GauntletAudioSnapshot(phase: .ripping, round: 2, confetti: 1,
                                       aura: 100, revealing: true)
        let new = GauntletAudioSnapshot(phase: .shop, round: 3, confetti: 1, aura: 100)
        XCTAssertNil(new.feedback(after: old))
    }

    func testInstantStandingShowcaseClearIsNotMissed() {
        let old = GauntletAudioSnapshot(phase: .shop, round: 3, confetti: 1, aura: 500)
        let new = GauntletAudioSnapshot(phase: .shop, round: 4, confetti: 1, aura: 500)
        XCTAssertEqual(new.feedback(after: old), .roundClear)
    }

    func testEvolutionTakesPriorityOverTheSmallAuraAccent() {
        let old = GauntletAudioSnapshot(phase: .ripping, aura: 10)
        XCTAssertEqual(GauntletAudioSnapshot(phase: .ripping, aura: 30, lines: ["line-1"])
            .feedback(after: old), .evolutionComplete)
        XCTAssertEqual(GauntletAudioSnapshot(phase: .ripping, aura: 15)
            .feedback(after: old), .auraGain)
    }

    func testLastRipWarningWaitsUntilTheRevealCloses() {
        let before = GauntletAudioSnapshot(phase: .ripping, round: 2, rips: 2)
        let open = GauntletAudioSnapshot(phase: .ripping, round: 2, rips: 1, revealing: true)
        XCTAssertNil(open.feedback(after: before))
        let closed = GauntletAudioSnapshot(phase: .ripping, round: 2, rips: 1)
        XCTAssertEqual(closed.feedback(after: open), .lastRip)
    }

    func testWinLossAndConsolationAreOneShotPhaseChanges() {
        let ripping = GauntletAudioSnapshot(phase: .ripping, round: 8)
        let reward = GauntletAudioSnapshot(phase: .reward, round: 8)
        let results = GauntletAudioSnapshot(phase: .results, round: 8)
        XCTAssertEqual(reward.feedback(after: ripping), .gauntletWin)
        XCTAssertEqual(results.feedback(after: ripping), .gauntletWin)
        XCTAssertNil(results.feedback(after: reward))
        XCTAssertEqual(GauntletAudioSnapshot(phase: .lost, round: 8)
            .feedback(after: ripping), .gauntletLoss)
    }

    func testGradingUsesTheActualValueDirectionNotAnArbitraryGradeCutoff() {
        XCTAssertEqual(Sound.gradingResult(grade: 10, oldValue: 10, newValue: 30), .gradePerfect)
        XCTAssertEqual(Sound.gradingResult(grade: 7, oldValue: 10, newValue: 8), .gradeLow)
        XCTAssertEqual(Sound.gradingResult(grade: 6, oldValue: 10, newValue: 10), .gradeHigh)
        XCTAssertEqual(Sound.gradingResult(grade: 8, oldValue: 10, newValue: 12), .gradeHigh)
    }
}

final class AudioCatalogueTests: XCTestCase {
    func testEveryApprovedEffectAndAlternateTakeIsBundledAndDecodes() throws {
        XCTAssertEqual(Sound.allCases.count, 48)
        let names = Sound.allCases.flatMap(\.resourceNames)
        XCTAssertEqual(names.count, 60)
        XCTAssertEqual(Set(names).count, names.count)
        for name in names {
            let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "wav"), name)
            let file = try AVAudioFile(forReading: url)
            XCTAssertEqual(file.fileFormat.channelCount, 2, name)
            XCTAssertEqual(file.fileFormat.sampleRate, 48000, name)
            XCTAssertGreaterThan(file.length, 0, name)
            XCTAssertLessThan(file.length, 48000 * 4, name)
        }
    }

    func testBothModeMusicLoopsAreBundledAndDecodable() throws {
        let expectedFrames: [Music: AVAudioFramePosition] = [
            .classic: 1_772_544,
            .gauntlet: 2_490_368
        ]
        for music in Music.allCases {
            let url = try XCTUnwrap(Bundle.main.url(forResource: music.rawValue, withExtension: "m4a"))
            let player = try AVAudioPlayer(contentsOf: url)
            let frames = try XCTUnwrap(expectedFrames[music])
            XCTAssertEqual(player.duration, Double(frames) / 48_000,
                           accuracy: 1.0 / 48_000, music.rawValue)
            XCTAssertEqual(player.numberOfChannels, 2)
            player.numberOfLoops = -1
            XCTAssertEqual(player.numberOfLoops, -1)
        }
    }
}
