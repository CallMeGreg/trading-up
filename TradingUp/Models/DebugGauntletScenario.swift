#if DEBUG
import Foundation

/// Reproducible, playable snapshots for UI tests. Only an explicit DEBUG launch
/// seeds the stores; subsequent Home / Continue navigation uses normal saves.
enum DebugGauntletScenario: String {
    case fresh
    case swap
    case shop
    case lastPack = "last-pack"

    static let key = "TU_TEST_GAUNTLET"

    static func prepare(environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard let name = environment[key] else { return }
        guard let scenario = Self(rawValue: name) else {
            preconditionFailure("Unknown Gauntlet test scenario: \(name)")
        }
        var progress = GauntletProgress()
        _ = progress.markIntroSeen()
        precondition(GauntletProgressStore().save(progress), "Could not seed Gauntlet progress")
        let store = GauntletRunStore()
        if scenario == .fresh {
            store.clear()
        } else {
            precondition(store.save(scenario.snapshot), "Could not seed Gauntlet run")
        }
    }

    var snapshot: GauntletRunSnapshot {
        var run = GauntletRun(tier: self == .swap ? .medium : .easy, trainer: .neutral)
        var pending: [CardInstance] = []
        var phase = GauntletResumePhase.ripping
        switch self {
        case .fresh:
            break
        case .swap:
            run.round = 3
            run.ripsLeft = 2
            run.cash = 36.75
            for id in ["S1-001", "S1-002", "S1-003", "S1-004", "S1-005", "S1-025"] {
                run.keep(CardInstance(cardId: id))
            }
            pending = [CardInstance(cardId: "S1-048"), CardInstance(cardId: "S1-006")]
        case .shop:
            run.cash = 35
            run.ripsLeft = 3
            run.keep(CardInstance(cardId: "S1-050", foil: true))
            run.keep(CardInstance(cardId: "S1-001"))
            run.keep(CardInstance(cardId: "S1-004"))
            var rng = DebugSeededRNG(1)
            precondition(run.endRound(using: &rng) == .cleared)
            phase = .shop
        case .lastPack:
            run.ripsLeft = 0
            run.keep(CardInstance(cardId: "S1-050"))
            pending = [CardInstance(cardId: "S1-001")]
        }
        return GauntletRunSnapshot(run: run, phase: phase, pendingCards: pending,
                                   pendingCatalyst: nil, lastRippedSet: 1,
                                   revealActive: !pending.isEmpty, celebratedRound: 0)
    }
}
#endif
