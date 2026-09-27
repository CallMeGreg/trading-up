import Foundation

/// Installation-level teaching progress, deliberately separate from either run's save.
@Observable
@MainActor
final class ModeTutorial {
    enum Mode: String { case classic, gauntlet }
    enum Step: String {
        case classicBuy, classicSummary, classicCollection, classicInspect
        case classicGrade, classicSell, classicDetailDone, classicCollectors
        case classicChooseTrade, classicTradeTarget
        case gauntletTrainer, gauntletTier, gauntletRip, gauntletKeep, gauntletSell
        case gauntletCatalyst, gauntletPack, gauntletInspect, gauntletGrade
        case gauntletDetailDone, gauntletUpgrade, gauntletShop
    }

    let mode: Mode
    private let defaults: UserDefaults
    private var prepared = false
    private(set) var isActive = false
    private(set) var completed: Set<String>

    private var key: String { "tradingup_tutorial_v1_\(mode.rawValue)" }

    init(mode: Mode, defaults: UserDefaults = .standard) {
        self.mode = mode
        self.defaults = defaults
        completed = Set(defaults.stringArray(forKey: "tradingup_tutorial_v1_\(mode.rawValue)_steps") ?? [])
    }

    func prepare(hasPlayed: Bool) {
        guard !prepared else { return }
        prepared = true
        if let status = defaults.string(forKey: key) {
            isActive = status == "active"
        } else {
            isActive = !hasPlayed
            defaults.set(isActive ? "active" : "complete", forKey: key)
        }
    }

    func needs(_ step: Step) -> Bool { isActive && !completed.contains(step.rawValue) }

    func record(_ step: Step) {
        guard isActive else { return }
        completed.insert(step.rawValue)
        defaults.set(completed.sorted(), forKey: key + "_steps")
    }

    func finish() {
        guard isActive else { return }
        isActive = false
        defaults.set("complete", forKey: key)
    }

    /// Classic saves acquisitions immediately, but not the transient pack presentation.
    /// Resume at the collection rather than charging for another introductory pack.
    func resumeClassic(hasCards: Bool) {
        guard mode == .classic, isActive else { return }
        if hasCards {
            record(.classicBuy)
            record(.classicSummary)
        } else if completed.contains(Step.classicBuy.rawValue) {
            completed = []
            defaults.set([], forKey: key + "_steps")
        }
    }
}
