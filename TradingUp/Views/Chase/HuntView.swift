import SwiftUI

/// The live Hunt. A single screen that shifts with the run's phase: work the
/// Lead (rip / sell / grade / use Items), run it down, draft, shop the Bazaar,
/// route to the next Lead, and finally land the Grail at the Score.
struct HuntView: View {
    @Environment(ChaseState.self) private var state

    /// A one-shot Item awaiting a target card. While set, stock rows are tappable
    /// to apply it (and a banner explains the mode).
    @State private var pendingItem: ItemKind? = nil
    @State private var showGiveUp = false

    var body: some View {
        if let run = state.run {
            ScrollView {
                VStack(spacing: 16) {
                    HuntHeader(run: run)

                    switch run.phase {
                    case .working: workingSection(run)
                    case .draft:   DraftSection()
                    case .bazaar:  BazaarSection()
                    case .route:   RouteSection()
                    case .won, .bust: EmptyView()   // resolved into the summary sheet
                    }
                }
                .padding(16)
                .readableWidth()
            }
            .background(Palette.screen.ignoresSafeArea())
        }
    }

    // MARK: Working a Lead

    @ViewBuilder
    private func workingSection(_ run: RunState) -> some View {
        if let item = pendingItem {
            targetingBanner(item)
        }

        ripPanel(run)
        stockPanel(run)
        itemsPanel(run)
        actionFooter(run)
    }

    private func ripPanel(_ run: RunState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Rip packs")
            ForEach(1...max(1, run.maxSet), id: \.self) { set in
                let price = Economy.packPrice(set: set)
                let free = run.trainer == .speculator && !run.freeFirstPackUsed
                let canRip = free || (run.energy >= 1 && run.cash >= price)
                Button { _ = state.ripPack(set: set) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "shippingbox.fill").foregroundStyle(canRip ? Palette.tapCue : Palette.subtle)
                        Text(CardDatabase.setName(set)).font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.text)
                        Spacer(minLength: 0)
                        Text(free ? "FREE" : "$\(Int(price)) · 1⚡")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(canRip ? Palette.money : Palette.subtle)
                    }
                    .panel(12)
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Palette.stroke, lineWidth: 1))
                }
                .buttonStyle(.plain).disabled(!canRip)
                .opacity(canRip ? 1 : 0.55)
            }
        }
    }

    private func stockPanel(_ run: RunState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("Your stock (\(run.stock.count))")
                Spacer()
                if hasDuplicates(run.stock) {
                    Button("Sell dupes") { state.sellDuplicates() }
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.tapCue)
                }
            }
            if run.stock.isEmpty {
                Text("Empty — rip a pack to start trading up.")
                    .font(.system(size: 12)).foregroundStyle(Palette.subtle)
                    .frame(maxWidth: .infinity, alignment: .leading).panel(14)
            } else {
                ForEach(run.stock.sorted { $0.currentValue > $1.currentValue }) { inst in
                    stockRow(inst, run: run)
                }
            }
        }
    }

    private func stockRow(_ inst: CardInstance, run: RunState) -> some View {
        let gradeable = inst.card.rarity.canBeGraded && inst.grade == nil
        let matchesGrail = run.grail.matches(inst)
        return HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 5).fill(inst.card.rarity.gemGradient).frame(width: 6, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(inst.card.name).font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.text).lineLimit(1)
                    if inst.foil { Image(systemName: "sparkles").font(.system(size: 9)).foregroundStyle(Color(hex: "ffd54a")) }
                    if let g = inst.grade { Text("PSA \(g)").font(.system(size: 9, weight: .heavy)).foregroundStyle(Palette.tapCue) }
                    if matchesGrail { Image(systemName: "target").font(.system(size: 9)).foregroundStyle(Palette.money) }
                }
                Text("$\(Int(inst.currentValue))").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.subtle)
            }
            Spacer(minLength: 0)
            if pendingItem == nil {
                if gradeable {
                    smallButton("Grade", state.gradingIsFree() ? "Free" : "$\(Int(state.gradeFee(for: inst)))", Palette.tapCue) {
                        _ = state.grade(inst.id)
                    }
                }
                smallButton("Sell", "$\(Int(state.sellPreview(inst)))", Palette.money) {
                    _ = state.sell(inst.id)
                }
            }
        }
        .panel(10)
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(pendingItem != nil ? Palette.tapCue : .clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture { if let item = pendingItem { applyItem(item, to: inst) } }
    }

    private func itemsPanel(_ run: RunState) -> some View {
        Group {
            if !run.items.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("Items")
                    ForEach(Array(run.items.enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 10) {
                            Image(systemName: item.isPassive ? "bolt.shield.fill" : "wand.and.stars")
                                .foregroundStyle(item.isPassive ? Palette.money : Palette.tapCue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.text)
                                Text(item.blurb).font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.subtle)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            if item.isPassive {
                                Text("ON").font(.system(size: 10, weight: .heavy)).foregroundStyle(Palette.money)
                            } else {
                                smallButton("Use", nil, Palette.tapCue) { beginUse(item) }
                            }
                        }
                        .panel(10)
                    }
                }
            }
        }
    }

    private func actionFooter(_ run: RunState) -> some View {
        VStack(spacing: 10) {
            if run.lead.isScore {
                if state.canLandGrail() {
                    BigButton(title: "Land the Grail", subtitle: "Pay $\(Int(run.grail.price)) and win the Hunt",
                              systemImage: "trophy.fill", tint: [Color(hex: "ffd54a"), Color(hex: "ff8ad6")]) {
                        state.landGrail()
                    }
                } else {
                    hint(scoreHint(run))
                }
            } else if state.askSatisfied() {
                BigButton(title: "Run down this Lead", subtitle: "Ask met — follow it to the next Lead",
                          systemImage: "arrow.turn.down.right", tint: [Palette.money, Color(hex: "39c46e")]) {
                    _ = state.runDownLead()
                }
            } else {
                hint("Meet the Ask — \(run.lead.ask.describe) — then run the Lead down.")
            }

            Button(role: .destructive) { showGiveUp = true } label: {
                Text("Give up this Hunt").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(hex: "ff6b6b"))
            }
            .confirmationDialog("Give up this Hunt? Your held cards still deposit to the Binder.",
                                isPresented: $showGiveUp, titleVisibility: .visible) {
                Button("Give up", role: .destructive) { state.giveUp() }
                Button("Keep hunting", role: .cancel) {}
            }
        }
        .padding(.top, 4)
    }

    // MARK: Item targeting

    private func targetingBanner(_ item: ItemKind) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.tap.fill").foregroundStyle(Palette.tapCue)
            Text("Tap a card to use \(item.title)").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.text)
            Spacer()
            Button("Cancel") { pendingItem = nil }.font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.subtle)
        }
        .panel(12)
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Palette.tapCue, lineWidth: 1))
    }

    private func beginUse(_ item: ItemKind) {
        if item.needsTarget { pendingItem = item }
        else { _ = state.useItem(item) }
    }

    private func applyItem(_ item: ItemKind, to inst: CardInstance) {
        _ = state.useItem(item, target: inst.id)
        pendingItem = nil
    }

    // MARK: Bits

    private func scoreHint(_ run: RunState) -> String {
        if !run.grail.isHeld(in: run.stock) { return "The Score! Hold a card matching your Grail, then land it." }
        return "You hold the Grail card — raise $\(Int(run.grail.price)) to land it (you have $\(Int(run.cash)))."
    }

    private func hint(_ t: String) -> some View {
        Text(t).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.subtle)
            .frame(maxWidth: .infinity, alignment: .leading).panel(14)
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t.uppercased()).font(.system(size: 11, weight: .heavy)).tracking(2).foregroundStyle(Palette.subtle)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func hasDuplicates(_ stock: [CardInstance]) -> Bool {
        var seen = Set<String>()
        for inst in stock {
            if !seen.insert(inst.cardId).inserted { return true }
        }
        return false
    }

    private func smallButton(_ title: String, _ sub: String?, _ tint: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text(title).font(.system(size: 12, weight: .heavy))
                if let sub { Text(sub).font(.system(size: 9, weight: .semibold)).opacity(0.85) }
            }
            .foregroundStyle(tint)
            .padding(.vertical, 6).padding(.horizontal, 11)
            .background(Capsule().fill(tint.opacity(0.15)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
