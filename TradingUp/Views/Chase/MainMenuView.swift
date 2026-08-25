import SwiftUI

/// The between-Hunts home. Shows the permanent Binder's completion and Renown,
/// and routes to New Run (the Guild), the Binder, Stats and Settings.
struct MainMenuView: View {
    @Environment(ChaseState.self) private var state

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header

                NavigationLink(value: ChaseRoute.guild) {
                    BigButtonLabel(title: "New Run",
                                   subtitle: "Pick a Grail at the Collectors' Guild and start a Hunt",
                                   systemImage: "sparkle.magnifyingglass",
                                   tint: [Color(hex: "3b82f6"), Color(hex: "6d5cf7")])
                }
                .buttonStyle(.plain)

                HStack(spacing: 12) {
                    menuTile(.binder, "Binder", "square.grid.3x3.fill", Palette.money)
                    menuTile(.stats, "Stats", "chart.bar.fill", Palette.tapCue)
                }
                HStack(spacing: 12) {
                    menuTile(.settings, "Settings", "gearshape.fill", Palette.subtle)
                    renownTile
                }
            }
            .padding(20)
            .readableWidth()
        }
        .navigationTitle("Trading Up")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Text("THE CHASE")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .tracking(4)
                .foregroundStyle(Palette.subtle)

            Text("\(Int(state.binderCompletion * 100))% complete")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.text)

            ProgressBar(value: state.binderCompletion, total: 1, tint: Palette.money, height: 10)
                .frame(maxWidth: 260)

            Text("\(state.binderUnique) of \(state.totalCards) cards in your Binder")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.subtle)
        }
        .frame(maxWidth: .infinity)
        .panel(20)
    }

    private func menuTile(_ route: ChaseRoute, _ title: String, _ icon: String, _ tint: Color) -> some View {
        NavigationLink(value: route) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 22, weight: .bold)).foregroundStyle(tint)
                Text(title).font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.text)
            }
            .frame(maxWidth: .infinity).frame(height: 84)
            .panel(12)
        }
        .buttonStyle(.plain)
    }

    private var renownTile: some View {
        VStack(spacing: 8) {
            Image(systemName: "seal.fill").font(.system(size: 22, weight: .bold)).foregroundStyle(Color(hex: "ffd54a"))
            Text("\(Int(state.renown)) Renown").font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.text)
        }
        .frame(maxWidth: .infinity).frame(height: 84)
        .panel(12)
    }
}
