import SwiftUI

/// The app's root. As of v2.0.0 the entry point is the main menu, which routes to
/// Classic Mode, Gauntlet Mode, and the Binder. The tabbed game that used to live
/// here now lives in `ClassicModeView`.
struct ContentView: View {
    var body: some View {
        MainMenuView()
    }
}
