import Foundation

/// Presentation-only snapshots keep audio decisions out of the game models.
struct GauntletAudioSnapshot: Equatable {
    var phase: GauntletState.Phase
    var round = 0
    var confetti = 0
    var aura = 0.0
    var lines: Set<String> = []
    var rips = 0
    var revealing = false
    var championship = false

    @MainActor
    init(_ state: GauntletState) {
        phase = state.phase
        round = state.run?.round ?? 0
        confetti = state.confettiBurst
        aura = state.run?.showcaseAura ?? 0
        lines = state.run?.completedShowcaseLineIds ?? []
        rips = state.run?.ripsLeft ?? 0
        revealing = state.revealActive
        championship = state.run?.isFinalRound ?? false
    }

    init(phase: GauntletState.Phase, round: Int = 0, confetti: Int = 0,
         aura: Double = 0, lines: Set<String> = [], rips: Int = 0,
         revealing: Bool = false, championship: Bool = false) {
        self.phase = phase
        self.round = round
        self.confetti = confetti
        self.aura = aura
        self.lines = lines
        self.rips = rips
        self.revealing = revealing
        self.championship = championship
    }

    func feedback(after old: Self) -> Sound? {
        if phase != old.phase {
            switch phase {
            case .tierSelect: return .trainerSelect
            case .lost: return .gauntletLoss
            case .reward: return .gauntletWin
            case .results where old.phase == .ripping: return .gauntletWin
            case .ripping where old.phase == .tierSelect: return .runStart
            case .ripping where old.phase == .shop:
                return championship ? .bossRound : .roundStart
            default: break
            }
        }
        // Shop -> shop can represent an instant clear of a standing Showcase.
        // Ripping -> shop must NOT replay a target already celebrated mid-reveal.
        if confetti > old.confetti ||
            (phase == .shop && old.phase == .shop && round > old.round && confetti > 0) {
            return .roundClear
        }
        guard phase == .ripping, old.phase == .ripping else { return nil }
        if !lines.subtracting(old.lines).isEmpty { return .evolutionComplete }
        if aura > old.aura + 0.001 { return .auraGain }
        if old.revealing && !revealing && rips == 1 { return .lastRip }
        return nil
    }
}
