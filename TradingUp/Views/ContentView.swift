import SwiftUI

/// The app's root. As of v2.0.0 the entry point is the main menu, which routes to
/// Classic Mode, Gauntlet Mode, and the Binder. The tabbed game that used to live
/// here now lives in `ClassicModeView`.
struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            #if DEBUG
            if let gallery = DebugGallery.selection {
                DebugGalleryView(selection: gallery)
            } else {
                MainMenuView()
            }
            #else
            MainMenuView()
            #endif
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            SoundManager.shared.setApplicationActive(phase == .active)
        }
    }
}
