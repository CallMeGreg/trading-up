import SwiftUI

/// The Chase root. When a Hunt is live it takes the whole screen; otherwise the
/// main menu (New Run · Binder · Stats · Settings) is shown. A one-time reset /
/// load-issue explainer and the post-Hunt summary present on top.
struct ChaseRootView: View {
    @Environment(ChaseState.self) private var state

    var body: some View {
        ZStack {
            Palette.screen.ignoresSafeArea()

            if state.hasActiveRun {
                HuntView()
            } else {
                NavigationStack {
                    MainMenuView()
                        .navigationDestination(for: ChaseRoute.self) { route in
                            switch route {
                            case .guild:    GuildView()
                            case .binder:   BinderView()
                            case .stats:    ChaseStatsView()
                            case .settings: ChaseSettingsView()
                            }
                        }
                }
                .tint(Palette.money)
            }
        }
        .preferredColorScheme(.dark)
        // The post-Hunt recap (win or bust) presents over either surface.
        .sheet(isPresented: summaryBinding) {
            if let summary = state.lastSummary { HuntSummaryView(summary: summary) }
        }
        // The one-time 2.0 reset — or any quarantined-save notice — is a
        // full-screen explainer the player dismisses once.
        .fullScreenCover(isPresented: loadIssueBinding) {
            if let issue = state.loadIssue { WhatsNewView(issue: issue) }
        }
    }

    private var summaryBinding: Binding<Bool> {
        Binding(get: { state.lastSummary != nil },
                set: { if !$0 { state.dismissSummary() } })
    }

    private var loadIssueBinding: Binding<Bool> {
        Binding(get: { state.loadIssue != nil },
                set: { if !$0 { state.dismissLoadIssue() } })
    }
}

/// Menu destinations, so the menu can drive navigation declaratively.
enum ChaseRoute: Hashable {
    case guild, binder, stats, settings
}
