import SwiftUI

// MARK: - Header

/// The always-on Hunt status: the Grail, the current Lead's Ask and progress,
/// and the run's Energy / cash.
struct HuntHeader: View {
    let run: RunState

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(run.grail.tier.label.uppercased()) GRAIL")
                        .font(.system(size: 9, weight: .heavy)).tracking(2).foregroundStyle(Color(hex: "ffd54a"))
                    Text(run.grail.headline).font(.system(size: 15, weight: .heavy)).foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Land for $\(Int(run.grail.price))")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.subtle)
                }
                Spacer(minLength: 0)
                Image(systemName: run.grail.isHeld(in: run.stock) ? "target" : "trophy.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(run.grail.isHeld(in: run.stock) ? Palette.money : Color(hex: "ffd54a"))
            }

            Divider().overlay(Palette.stroke)

            HStack {
                Text(run.lead.isScore ? "THE SCORE" : "LEAD \(run.lead.index) / \(run.totalLeads)")
                    .font(.system(size: 10, weight: .heavy)).tracking(2)
                    .foregroundStyle(run.lead.isScore ? Color(hex: "ffd54a") : Palette.subtle)
                Spacer()
                if run.lead.complication != .none {
                    Text(run.lead.complication.title.uppercased())
                        .font(.system(size: 9, weight: .heavy))
                        .padding(.vertical, 3).padding(.horizontal, 7)
                        .background(Capsule().fill(Color(hex: "ff8a4a").opacity(0.2)))
                        .foregroundStyle(Color(hex: "ff9a6b"))
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(run.lead.ask.describe).font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.text)
                let p = run.lead.ask.progress(cash: run.cash, stock: run.stock)
                ProgressBar(value: p.current, total: p.target,
                            tint: run.lead.ask.isSatisfied(cash: run.cash, stock: run.stock) ? Palette.money : Palette.tapCue)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                stat("⚡ Energy", "\(run.energy)", Palette.tapCue)
                stat("Cash", "$\(Int(run.cash))", Palette.money)
                stat("Renown", "+\(Int(run.renownBanked))", Color(hex: "ffd54a"))
            }
        }
        .panel(16)
    }

    private func stat(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(tint)
            Text(label.uppercased()).font(.system(size: 8, weight: .bold)).foregroundStyle(Palette.subtle)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.bg0.opacity(0.5)))
    }
}

// MARK: - Draft

/// Post-Lead reward: pick one of the offered Items or Energy chunks.
struct DraftSection: View {
    @Environment(ChaseState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            phaseTitle("Draft a reward", "Pick one to carry into the next Lead")
            ForEach(state.run?.draft ?? []) { opt in
                Button { _ = state.pickDraft(opt.id) } label: {
                    optionRow(icon: draftIcon(opt), title: opt.title, blurb: opt.blurb, tint: Palette.tapCue)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func draftIcon(_ opt: DraftOption) -> String {
        switch opt.kind {
        case .item(let i): return i.isPassive ? "bolt.shield.fill" : "wand.and.stars"
        case .energy:      return "bolt.fill"
        }
    }
}

// MARK: - Bazaar

/// Spend cash on Items between Leads (using them later is free), reroll the
/// stock, or move on to routing.
struct BazaarSection: View {
    @Environment(ChaseState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            phaseTitle("The Bazaar", "Buy Items with cash — using them is free")
            let cash = state.run?.cash ?? 0
            ForEach(state.run?.bazaarOffers ?? [], id: \.self) { item in
                let price = Economy.itemPrice(item)
                let canBuy = cash >= price
                Button { _ = state.bazaarBuy(item) } label: {
                    optionRow(icon: item.isPassive ? "bolt.shield.fill" : "wand.and.stars",
                              title: item.title, blurb: item.blurb,
                              trailing: "$\(Int(price))", tint: canBuy ? Palette.money : Palette.subtle)
                }
                .buttonStyle(.plain).disabled(!canBuy).opacity(canBuy ? 1 : 0.55)
            }

            HStack(spacing: 10) {
                let reroll = state.rerollCost()
                Button { _ = state.rerollBazaar() } label: {
                    Label("Reroll $\(Int(reroll))", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.tapCue)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Palette.panelHi))
                }
                .buttonStyle(.plain).disabled(cash < state.rerollCost()).opacity(cash < state.rerollCost() ? 0.55 : 1)
            }

            BigButton(title: "Leave the Bazaar", systemImage: "arrow.right",
                      tint: [Palette.tapCue, Color(hex: "6d5cf7")]) {
                _ = state.leaveBazaar()
            }
        }
    }
}

// MARK: - Route

/// Choose the branch to the next Lead: each shows its Ask, any Complication, its
/// Energy budget and a bonus.
struct RouteSection: View {
    @Environment(ChaseState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            phaseTitle("Route to the next Lead", "You see each Ask up front — plan two ahead")
            ForEach(state.run?.route ?? []) { opt in
                Button { _ = state.chooseRoute(opt.id) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(opt.isScore ? "THE SCORE" : opt.ask.describe)
                                .font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.text)
                            Spacer(minLength: 0)
                            Text("\(opt.energyBudget)⚡").font(.system(size: 12, weight: .heavy)).foregroundStyle(Palette.tapCue)
                        }
                        HStack(spacing: 6) {
                            Text("Bonus: \(opt.bonus.describe)").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.money)
                            if opt.complication != .none {
                                Text("· \(opt.complication.title)").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(hex: "ff9a6b"))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panel(14)
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Palette.stroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Shared row helpers

private func optionRow(icon: String, title: String, blurb: String, trailing: String? = nil, tint: Color) -> some View {
    HStack(spacing: 12) {
        Image(systemName: icon).font(.system(size: 18)).foregroundStyle(tint).frame(width: 26)
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.text)
            Text(blurb).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.subtle)
                .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 0)
        if let trailing {
            Text(trailing).font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(tint)
        }
    }
    .panel(14)
    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Palette.stroke, lineWidth: 1))
}

private func phaseTitle(_ title: String, _ sub: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(Palette.text)
        Text(sub).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.subtle)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}
