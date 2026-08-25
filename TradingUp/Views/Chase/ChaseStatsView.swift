import SwiftUI

/// Lifetime stats across every Hunt, plus the standing Renown and Binder totals.
struct ChaseStatsView: View {
    @Environment(ChaseState.self) private var state

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)

    var body: some View {
        ScrollView {
            let life = state.meta.lifetime
            VStack(alignment: .leading, spacing: 18) {
                LazyVGrid(columns: columns, spacing: 12) {
                    StatTile(label: "Renown", value: "\(Int(state.renown))", tint: Color(hex: "ffd54a"))
                    StatTile(label: "Binder", value: "\(state.binderUnique)/\(state.totalCards)", tint: Palette.money)
                    StatTile(label: "Hunts Won", value: "\(life.huntsWon)", tint: Palette.money)
                    StatTile(label: "Hunts Started", value: "\(life.huntsStarted)", tint: Palette.tapCue)
                    StatTile(label: "Win Rate", value: winRate(life), tint: Palette.text)
                    StatTile(label: "Leads Run Down", value: "\(life.leadsRunDown)", tint: Palette.text)
                    StatTile(label: "Packs Ripped", value: "\(life.packsRipped)", tint: Palette.tapCue)
                    StatTile(label: "Cards Graded", value: "\(life.cardsGraded)", tint: Palette.tapCue)
                    StatTile(label: "Ultras Pulled", value: "\(life.ultrasPulled)", tint: Color(hex: "b06cf7"))
                    StatTile(label: "Renown Earned", value: "\(Int(life.renownEarned))", tint: Color(hex: "ffd54a"))
                }

                if !state.meta.grailsLanded.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("GRAILS LANDED").font(.system(size: 11, weight: .heavy)).tracking(2).foregroundStyle(Palette.subtle)
                        ForEach(state.meta.grailsLanded.suffix(8).reversed()) { g in
                            HStack(spacing: 8) {
                                Image(systemName: "trophy.fill").font(.system(size: 12)).foregroundStyle(Color(hex: "ffd54a"))
                                Text(g.headline).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                                Spacer(minLength: 0)
                                Text(g.tier.label).font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.subtle)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).panel(14)
                }

                if !state.meta.discoveries.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DISCOVERIES (\(state.meta.discoveries.count)/\(Discovery.allCases.count))")
                            .font(.system(size: 11, weight: .heavy)).tracking(2).foregroundStyle(Palette.subtle)
                        ForEach(Discovery.allCases.filter { state.meta.discoveries.contains($0) }) { d in
                            HStack(spacing: 8) {
                                Image(systemName: "rosette").font(.system(size: 12)).foregroundStyle(Color(hex: "ffd54a"))
                                Text(d.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.text)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).panel(14)
                }
            }
            .padding(16)
            .readableWidth()
        }
        .navigationTitle("Stats")
        .navigationBarTitleDisplayMode(.inline)
        .background(Palette.screen.ignoresSafeArea())
    }

    private func winRate(_ life: ChaseLifetime) -> String {
        guard life.huntsStarted > 0 else { return "—" }
        return "\(Int(Double(life.huntsWon) / Double(life.huntsStarted) * 100))%"
    }
}
