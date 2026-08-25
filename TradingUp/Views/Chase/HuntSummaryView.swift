import SwiftUI

/// The post-Hunt recap. Win or bust, it shows what the run banked — Renown,
/// Binder deposits, any Discoveries — then returns to the menu.
struct HuntSummaryView: View {
    @Environment(ChaseState.self) private var state
    let summary: HuntSummary

    var body: some View {
        ZStack {
            Palette.screen.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: summary.won ? "trophy.fill" : "flag.slash.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(summary.won ? Color(hex: "ffd54a") : Palette.subtle)
                        .padding(.top, 24)

                    VStack(spacing: 6) {
                        Text(summary.won ? "Grail Landed!" : "The Hunt Ends")
                            .font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundStyle(Palette.text)
                        Text(summary.grailHeadline)
                            .font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.subtle)
                            .multilineTextAlignment(.center)
                    }

                    HStack(spacing: 12) {
                        StatTile(label: "Renown", value: "+\(Int(summary.renownEarned))", tint: Color(hex: "ffd54a"))
                        StatTile(label: "Leads", value: "\(summary.leadsRunDown)", tint: Palette.tapCue)
                        StatTile(label: "To Binder", value: "\(summary.cardsDeposited)", tint: Palette.money)
                    }

                    if !summary.newDiscoveries.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("NEW DISCOVERIES").font(.system(size: 11, weight: .heavy)).tracking(2).foregroundStyle(Palette.subtle)
                            ForEach(summary.newDiscoveries) { d in
                                HStack(spacing: 8) {
                                    Image(systemName: "rosette").foregroundStyle(Color(hex: "ffd54a"))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(d.title).font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.text)
                                        Text(d.blurb).font(.system(size: 10)).foregroundStyle(Palette.subtle)
                                    }
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).panel(14)
                    }

                    Text("Your Binder now holds \(summary.binderUnique) of \(state.totalCards) cards.")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.subtle)

                    BigButton(title: "Back to the Guild", systemImage: "house.fill",
                              tint: [Palette.money, Color(hex: "39c46e")]) {
                        state.dismissSummary()
                    }
                }
                .padding(20)
                .readableWidth()
            }
        }
        .interactiveDismissDisabled(true)
    }
}
