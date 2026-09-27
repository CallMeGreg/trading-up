#if DEBUG
import Foundation

enum DebugTutorialScenario {
    @MainActor
    static func prepare(environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard environment["TU_TEST_TUTORIAL"] == "fresh" else {
            if environment[DebugLaunchState.key] != nil || environment[DebugGauntletScenario.key] != nil {
                for mode in ["classic", "gauntlet"] {
                    UserDefaults.standard.set("complete", forKey: "tradingup_tutorial_v1_\(mode)")
                }
            }
            return
        }
        for mode in ["classic", "gauntlet"] {
            let key = "tradingup_tutorial_v1_\(mode)"
            UserDefaults.standard.removeObject(forKey: key)
            UserDefaults.standard.removeObject(forKey: key + "_steps")
        }
        precondition(SaveStore().save(GameCore()), "Could not seed tutorial save")
        precondition(GauntletProgressStore().save(GauntletProgress()), "Could not seed tutorial progress")
        GauntletRunStore().clear()
    }
}
#endif
