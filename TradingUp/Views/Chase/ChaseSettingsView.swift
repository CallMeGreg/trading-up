import SwiftUI

/// Settings: revisit the 2.0 explainer, read what The Chase is, and — behind a
/// confirmation — wipe all progress for a fresh career.
struct ChaseSettingsView: View {
    @Environment(ChaseState.self) private var state
    @State private var showReset = false
    @State private var showWhatsNew = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("HOW IT PLAYS").font(.system(size: 11, weight: .heavy)).tracking(2).foregroundStyle(Palette.subtle)
                    Text("Each run is a Hunt. Pick a Grail at the Guild, then chase it across escalating Leads — meet each Lead's Ask by ripping packs with Energy, grading, and trading through the Bazaar — until you can hold the Grail and pay its price at the Score. Win or bust, the best copy of every card you held is kept forever in your Binder, and you earn Renown to recruit Trainers and buy Guild upgrades.")
                        .font(.system(size: 13)).foregroundStyle(Palette.text).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading).panel(16)

                Button { showWhatsNew = true } label: {
                    settingsRow("Show \"What's New\"", "sparkles", Palette.tapCue)
                }.buttonStyle(.plain)

                Button(role: .destructive) { showReset = true } label: {
                    settingsRow("Reset all progress", "trash.fill", Color(hex: "ff6b6b"))
                }.buttonStyle(.plain)

                Text("Trading Up \(appVersion) · No ads, no in-app purchases, no tracking. Plays offline.")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.subtle)
                    .frame(maxWidth: .infinity, alignment: .center).padding(.top, 8)
            }
            .padding(16)
            .readableWidth()
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .background(Palette.screen.ignoresSafeArea())
        .confirmationDialog("Reset everything? Your Binder, Renown and unlocks are erased. This can't be undone.",
                            isPresented: $showReset, titleVisibility: .visible) {
            Button("Erase all progress", role: .destructive) { state.resetEverything() }
            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showWhatsNew) {
            WhatsNewView(issue: .resetForNewVersion(previousSaveQuarantinedAs: "your previous save"))
        }
    }

    private func settingsRow(_ title: String, _ icon: String, _ tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(tint).frame(width: 24)
            Text(title).font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.text)
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.subtle)
        }
        .panel(14)
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0"
        return "v\(v)"
    }
}
