import SwiftUI

private struct ModeTutorialKey: EnvironmentKey {
    static let defaultValue: ModeTutorial? = nil
}

extension EnvironmentValues {
    var modeTutorial: ModeTutorial? {
        get { self[ModeTutorialKey.self] }
        set { self[ModeTutorialKey.self] = newValue }
    }
}

extension ModeTutorial {
    func prompt(_ step: Step, target: String, title: String, message: String) -> TutorialPrompt? {
        needs(step) ? TutorialPrompt(target: target, title: title, message: message) : nil
    }
}

extension GauntletState {
    func shopTutorialPrompt(_ tutorial: ModeTutorial?) -> TutorialPrompt? {
        if tutorial?.needs(.gauntletUpgrade) == true, let run, run.cash >= run.nextSlotCost {
            return TutorialPrompt(target: "gauntlet-buy-slot", title: "Grow your Showcase",
                                  message: "Spend \(run.nextSlotCost.money) for another card slot. You can also buy pack sets and Catalyst slots; upgrades last this run.")
        }
        return tutorial?.prompt(
            .gauntletShop, target: "gauntlet-next-round", title: "Between rounds",
            message: "Your Showcase carries over. Saved cash earns interest; unused rips earn cash at each clear. Start the next round!")
    }
}
