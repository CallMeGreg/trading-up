import Foundation

/// Studio is the approved production direction. Names match generate_sfx.py.
enum Sound: String, CaseIterable, Sendable {
    case purchase
    case foilShimmer = "foil_shimmer"
    case coin
    case packOpen = "pack_open"
    case cardFlip = "card_flip"
    case rare, ultra
    case uiTap = "ui_tap"
    case uiBack = "ui_back"
    case panelOpen = "panel_open"
    case toggleOn = "toggle_on"
    case blocked
    case newCard = "new_card"
    case keepCard = "keep_card"
    case bulkSell = "bulk_sell"
    case gradeStart = "grade_start"
    case gradeLow = "grade_low"
    case gradeHigh = "grade_high"
    case gradePerfect = "grade_perfect"
    case evolutionComplete = "evolution_complete"
    case binderUpgrade = "binder_upgrade"
    case setUnlock = "set_unlock"
    case setComplete = "set_complete"
    case classicWin = "classic_win"
    case classicLoss = "classic_loss"
    case trainerSelect = "trainer_select"
    case tierSelect = "tier_select"
    case runStart = "run_start"
    case roundStart = "round_start"
    case bossRound = "boss_round"
    case lastRip = "last_rip"
    case showcaseSwap = "showcase_swap"
    case auraGain = "aura_gain"
    case catalystOffer = "catalyst_offer"
    case catalystAttune = "catalyst_attune"
    case catalystSwap = "catalyst_swap"
    case catalystSell = "catalyst_sell"
    case roundClear = "round_clear"
    case roundPayout = "round_payout"
    case showcaseExpand = "showcase_expand"
    case catalystExpand = "catalyst_expand"
    case packUnlock = "pack_unlock"
    case gauntletWin = "gauntlet_win"
    case gauntletLoss = "gauntlet_loss"
    case rewardReveal = "reward_reveal"
    case rewardClaim = "reward_claim"
    case tierUnlock = "tier_unlock"
    case trainerUnlock = "trainer_unlock"

    var resourceNames: [String] {
        switch self {
        case .uiTap, .packOpen, .cardFlip, .keepCard, .coin, .auraGain:
            return [rawValue, rawValue + "_02", rawValue + "_03"]
        default:
            return [rawValue]
        }
    }

    var isCelebration: Bool {
        switch self {
        case .rare, .ultra, .gradePerfect, .evolutionComplete, .setComplete,
             .classicWin, .classicLoss, .bossRound, .catalystOffer, .catalystAttune,
             .roundClear, .gauntletWin, .gauntletLoss, .rewardClaim, .tierUnlock, .trainerUnlock:
            return true
        default:
            return false
        }
    }

    static func gradingResult(grade: Int, oldValue: Double, newValue: Double) -> Sound {
        if grade == 10 { return .gradePerfect }
        return newValue < oldValue - 0.001 ? .gradeLow : .gradeHigh
    }

    @MainActor
    static func play(_ sound: Sound, volume: Float = 1) {
        SoundManager.shared.play(sound, volume: volume)
    }

    /// Presentation tasks use this for queued accents and cancel on dismissal.
    @MainActor
    static func after(_ seconds: Double, play sound: Sound, volume: Float = 1) async {
        let generation = SoundManager.shared.effectGeneration
        do {
            try await Task.sleep(for: .seconds(seconds))
        } catch is CancellationError {
            return
        } catch {
            AudioLog.logger.error("Audio timing failed: \(error.localizedDescription)")
            return
        }
        guard !Task.isCancelled, generation == SoundManager.shared.effectGeneration else { return }
        play(sound, volume: volume)
    }
}

enum Music: String, CaseIterable, Sendable {
    case classic, gauntlet
}
