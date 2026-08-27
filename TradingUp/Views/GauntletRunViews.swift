import SwiftUI

// MARK: - Small building blocks

/// A compact pill button used inside the run's dense keep/sell rows.
private struct MiniButton: View {
    let title: String
    var systemImage: String? = nil
    var tint: Color = Color(hex: "6d5cf7")
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage { Image(systemName: systemImage).font(.system(size: 11, weight: .bold)) }
                Text(title).font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(enabled ? tint : Palette.stroke))
            .opacity(enabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

private struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .black)).tracking(2)
            .foregroundStyle(Palette.subtle)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A small element-tinted chip for attuned Catalysts.
private struct CatalystChip: View {
    let catalyst: Catalyst
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(catalyst.element.badgeTint).frame(width: 8, height: 8)
            Text(catalyst.name).font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.text)
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(Capsule().fill(catalyst.element.badgeTint.opacity(0.14)))
        .overlay(Capsule().strokeBorder(catalyst.element.badgeTint.opacity(0.4), lineWidth: 1))
    }
}

// MARK: - Run screen (the round loop)

struct RunScreen: View {
    let state: GauntletState
    @State private var swapCandidate: CardInstance?
    @State private var detail: ShowcaseSelection?

    var body: some View {
        if let run = state.run {
            VStack(spacing: 12) {
                HUDPanel(run: run)
                ScrollView {
                    VStack(spacing: 12) {
                        if state.pendingCards.isEmpty && state.pendingCatalyst == nil {
                            ShowcasePanel(run: run) { idx in
                                detail = ShowcaseSelection(index: idx)
                            }
                        } else {
                            PullPanel(state: state, run: run) { card in swapCandidate = card }
                        }
                        if !run.attunedCatalysts.isEmpty {
                            AttunedPanel(run: run)
                        }
                    }
                    .padding(.bottom, 4)
                }
                actionBar(run)
            }
            .confirmationDialog("Swap in — replace which card?",
                                isPresented: swapBinding, presenting: swapCandidate) { cand in
                ForEach(run.showcase.indices, id: \.self) { i in
                    Button("Replace \(run.showcase[i].card.name) · \(run.showcase[i].currentValue.money)") {
                        state.swap(cand, forShowcaseIndex: i)
                        swapCandidate = nil
                        Haptics.play(.light)
                    }
                }
                Button("Cancel", role: .cancel) { swapCandidate = nil }
            }
            .sheet(item: $detail) { sel in
                ShowcaseCardDetail(state: state, index: sel.index) { detail = nil }
            }
        }
    }

    private var swapBinding: Binding<Bool> {
        Binding(get: { swapCandidate != nil }, set: { if !$0 { swapCandidate = nil } })
    }

    private func actionBar(_ run: GauntletRun) -> some View {
        VStack(spacing: 8) {
            if !(state.pendingCards.isEmpty && state.pendingCatalyst == nil) {
                Text("Resolve your pull to keep ripping")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.subtle)
            }
            PackRail(state: state, run: run)
            BigButton(title: "End Round",
                      subtitle: "Score \(fmt(run.showcaseAppraisal)) vs \(fmt(run.target)) needed",
                      systemImage: "flag.checkered",
                      tint: GauntletTheme.tint,
                      enabled: state.canEndRound) {
                let willClear = run.showcaseAppraisal >= run.target
                Haptics.play(willClear ? .success : .warning)
                state.endRound()
            }
        }
    }
}

private func fmt(_ v: Double) -> String { String(format: "%.0f", v) }

// MARK: Pack rail — one tile per element set (req 5)

/// Replaces the single "Rip a Pack" button. Each of the five element sets is a
/// tile: rippable once unlocked, buy-to-unlock when it's next in line, or greyed
/// out further up the rail. The player picks which unlocked element to rip, so
/// they can chase a set for Showcase synergy.
private struct PackRail: View {
    let state: GauntletState
    let run: GauntletRun

    /// Cap so a pack thumbnail never balloons on iPad; the row still fits five
    /// across on a phone by shrinking to the column width below this.
    private let maxPack: CGFloat = 62
    private let gap: CGFloat = 6
    private var railHeight: CGFloat { PackWrapper.height(forWidth: maxPack) + 22 }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                SectionTitle(text: "Packs — pick a set to rip")
                Spacer(minLength: 6)
                Text("\(run.ripsLeft) rip\(run.ripsLeft == 1 ? "" : "s") left")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(run.ripsLeft > 0 ? Palette.text : Palette.subtle)
            }
            // Fixed row (no horizontal scroll): every set gets an equal column and
            // the pack shrinks to fit whatever width is available.
            GeometryReader { geo in
                let n = CGFloat(state.packTiers.count)
                let col = max(1, (geo.size.width - gap * (n - 1)) / n)
                let w = max(28, min(maxPack, col))
                HStack(spacing: gap) {
                    ForEach(state.packTiers, id: \.self) { set in
                        PackTile(state: state, run: run, set: set, packWidth: w)
                            .frame(width: col)
                    }
                }
                .frame(width: geo.size.width, height: railHeight, alignment: .center)
            }
            .frame(height: railHeight)
        }
    }
}

private struct PackTile: View {
    let state: GauntletState
    let run: GauntletRun
    let set: Int
    var packWidth: CGFloat

    private var element: Element { Element.theme(forSet: set) }
    private var unlocked: Bool { state.isPackUnlocked(set) }
    private var isNext: Bool { state.nextPackTier == set }
    private var enabled: Bool {
        if unlocked { return state.canRip }
        if isNext { return state.canUnlockNextPack }
        return false
    }

    var body: some View {
        Button(action: act) {
            VStack(spacing: 5) {
                packArt
                Text(statusLine)
                    .font(.system(size: 10.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(statusTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel("\(CardDatabase.setName(set)) pack — \(statusLine)")
    }

    /// A miniature of the Classic pack wrapper, dimmed and locked when it isn't
    /// yet available this run.
    private var packArt: some View {
        ZStack {
            PackWrapper(set: set, width: packWidth, detail: .mini)
                .saturation(unlocked ? 1 : 0.12)
                .opacity(unlocked ? (enabled ? 1 : 0.6) : (isNext ? 0.72 : 0.42))
            if !unlocked {
                ZStack {
                    Circle().fill(.black.opacity(0.55))
                        .frame(width: packWidth * 0.5, height: packWidth * 0.5)
                    Image(systemName: isNext ? "lock.open.fill" : "lock.fill")
                        .font(.system(size: packWidth * 0.24, weight: .bold))
                        .foregroundStyle(.white.opacity(0.92))
                }
            }
        }
        .shadow(color: glow, radius: glow == .clear ? 0 : 6)
    }

    /// A tint halo that marks a pack you can act on right now.
    private var glow: Color {
        if unlocked && enabled { return element.badgeTint.opacity(0.55) }
        if isNext && state.canUnlockNextPack { return Color(hex: "ffd54a").opacity(0.6) }
        return .clear
    }

    private var statusLine: String {
        if unlocked { return "Rip" }
        if isNext, let cost = state.packUnlockCost { return "Unlock \(cost.moneyShort)" }
        return "Locked"
    }
    private var statusTint: Color {
        if unlocked { return enabled ? element.badgeTint : Palette.subtle }
        if isNext { return state.canUnlockNextPack ? Palette.money : Palette.subtle }
        return Palette.subtle
    }

    private func act() {
        if unlocked {
            Haptics.play(.medium); state.rip(set: set)
        } else if isNext {
            Haptics.play(.success); state.unlockNextPack()
        }
    }
}

// MARK: HUD

private struct HUDPanel: View {
    let run: GauntletRun

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Round \(run.round) / \(run.roundsTotal)")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                if run.isBossRound {
                    Text("BOSS").font(.system(size: 10, weight: .black)).tracking(1)
                        .foregroundStyle(Color(hex: "1a0d2e"))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color(hex: "ffd54a")))
                }
                Spacer()
                Text(CardDatabase.setName(run.packTier))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(run.packTier <= 5 ? Element.theme(forSet: run.packTier).badgeTint : Palette.subtle)
            }

            VStack(spacing: 4) {
                ProgressBar(value: run.showcaseAppraisal, total: run.target,
                            tint: run.showcaseAppraisal >= run.target ? Palette.money : Color(hex: "b06cf7"),
                            height: 10)
                HStack {
                    Text("Score \(fmt(run.showcaseAppraisal))")
                        .foregroundStyle(run.showcaseAppraisal >= run.target ? Palette.money : Palette.text)
                    Spacer()
                    Text("Target \(fmt(run.target))").foregroundStyle(Palette.subtle)
                }
                .font(.system(size: 12, weight: .bold))
            }

            HStack(spacing: 8) {
                StatTile(label: "Cash", value: run.cash.moneyShort, tint: Palette.money)
                StatTile(label: "Rips", value: "\(run.ripsLeft)")
                StatTile(label: "Reprints", value: "\(run.retriesLeft)")
                StatTile(label: "Slots", value: "\(run.showcase.count)/\(run.effectiveSlots)")
            }
        }
        .panel()
    }
}

// MARK: Pull resolution

private struct PullPanel: View {
    let state: GauntletState
    let run: GauntletRun
    let onSwap: (CardInstance) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "Your Pull — keep or sell")
            ForEach(state.pendingCards) { inst in
                PullRow(state: state, run: run, inst: inst, onSwap: onSwap)
            }
            if let cat = state.pendingCatalyst {
                CatalystOfferRow(state: state, catalyst: cat)
            }
        }
        .panel()
    }
}

private struct PullRow: View {
    let state: GauntletState
    let run: GauntletRun
    let inst: CardInstance
    let onSwap: (CardInstance) -> Void

    var body: some View {
        HStack(spacing: 12) {
            CardView(card: inst.card, instance: inst, width: 76)
            VStack(alignment: .leading, spacing: 6) {
                Text(inst.card.name)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white).lineLimit(1)
                HStack(spacing: 6) {
                    Text(inst.card.rarity.display.uppercased())
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(inst.card.rarity.accent)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(inst.card.rarity.accent.opacity(0.16)))
                    Text(inst.currentValue.money)
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(Palette.money)
                }
                Text("+\(fmt(max(0, run.marginalAppraisal(of: inst)))) score if kept")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.subtle)
                HStack(spacing: 8) {
                    if state.canKeepPending {
                        MiniButton(title: "Keep", systemImage: "tray.and.arrow.down.fill",
                                   tint: Color(hex: "3fbf7f")) {
                            Haptics.play(.light); state.keep(inst)
                        }
                    } else {
                        MiniButton(title: "Swap", systemImage: "arrow.left.arrow.right",
                                   tint: Color(hex: "3b82f6")) { onSwap(inst) }
                    }
                    MiniButton(title: "Sell \(sellPreview)", systemImage: "dollarsign.circle.fill",
                               tint: Color(hex: "6d5cf7")) {
                        Haptics.play(.light); state.sell(inst)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Palette.bg0.opacity(0.4)))
    }

    private var sellPreview: String {
        (inst.currentValue * run.sellbackRate).moneyShort
    }
}

private struct CatalystOfferRow: View {
    let state: GauntletState
    let catalyst: Catalyst

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(catalyst.element.badgeTint)
                Text("Catalyst — \(catalyst.name)")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Text(catalyst.element.display.uppercased())
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(catalyst.element.badgeTint)
            }
            Text(catalyst.blurb)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.subtle)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                MiniButton(title: "Attune", systemImage: "sparkles",
                           tint: Color(hex: "b06cf7"), enabled: state.canAttunePending) {
                    Haptics.play(.success); state.attunePendingCatalyst()
                }
                MiniButton(title: "Sell \(catalyst.saleValue.moneyShort)",
                           systemImage: "dollarsign.circle.fill", tint: Color(hex: "6d5cf7")) {
                    Haptics.play(.light); state.sellPendingCatalyst()
                }
                if !state.canAttunePending {
                    Text("Catalyst slots full")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.subtle)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(catalyst.element.badgeTint.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(catalyst.element.badgeTint.opacity(0.35), lineWidth: 1))
    }
}

// MARK: Showcase

private struct ShowcasePanel: View {
    let run: GauntletRun
    let onTapCard: (Int) -> Void

    private let cols = [GridItem(.adaptive(minimum: 92), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Showcase \(run.showcase.count)/\(run.effectiveSlots)")
            if run.showcase.isEmpty {
                Text("Rip a pack, then keep cards here to build your appraisal. Same-element cards score higher together.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.subtle)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8)
            } else {
                LazyVGrid(columns: cols, spacing: 10) {
                    ForEach(Array(run.showcase.enumerated()), id: \.element.id) { idx, inst in
                        Button { onTapCard(idx) } label: {
                            CardView(card: inst.card, instance: inst, width: 92)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("Tap a card to see its evolution line and grade it.")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.subtle)
            }
        }
        .panel()
    }
}

private struct AttunedPanel: View {
    let run: GauntletRun
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: "Attuned \(run.attunedCatalysts.count)/\(run.effectiveCatalystSlots)")
            FlowRow(items: run.attunedCatalysts) { CatalystChip(catalyst: $0) }
        }
        .panel()
    }
}

/// A simple chip row. Index-keyed because the same Catalyst archetype can be
/// attuned more than once (their `id` is the archetype, not the copy), which would
/// collide under an `Identifiable` `ForEach`.
private struct FlowRow<Item, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content
    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in content(item) }
            Spacer(minLength: 0)
        }
    }
}

// MARK: Showcase card detail (req 6)

/// Identifiable wrapper so a tapped Showcase slot can drive a `.sheet(item:)`.
struct ShowcaseSelection: Identifiable {
    let index: Int
    var id: Int { index }
}

/// The expanded view for a Showcase card: a large render with its foil/grade
/// treatment, the numbers behind its score, its full evolution line, and the
/// grade action — the tap target that used to be a bare confirmation dialog.
private struct ShowcaseCardDetail: View {
    let state: GauntletState
    let index: Int
    let onClose: () -> Void

    var body: some View {
        ZStack {
            GauntletBackdrop()
            if let run = state.run, run.showcase.indices.contains(index) {
                content(run: run, inst: run.showcase[index])
            } else {
                Color.clear.onAppear(perform: onClose)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 26))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Palette.subtle)
            }
            .buttonStyle(.plain)
            .padding(14)
            .accessibilityLabel("Close card")
        }
    }

    @ViewBuilder
    private func content(run: GauntletRun, inst: CardInstance) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                CardView(card: inst.card, instance: inst, width: 188)
                    .padding(.top, 12)

                VStack(spacing: 8) {
                    Text(inst.card.name)
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 8) {
                        badge(inst.card.rarity.display.uppercased(), inst.card.rarity.accent)
                        if inst.foil { badge("FOIL", Color(hex: "ffd54a")) }
                        if let g = inst.grade { badge("PSA \(g)", gradeColor(g)) }
                    }
                }

                HStack(spacing: 8) {
                    StatTile(label: "Value", value: inst.currentValue.moneyShort, tint: Palette.money)
                    StatTile(label: "Base", value: inst.card.baseValue.moneyShort)
                    StatTile(label: "Element", value: inst.card.element.display,
                             tint: inst.card.element.badgeTint)
                }

                EvolutionLineView(line: CardDatabase.line(inst.card.lineId),
                                  currentCardId: inst.card.id) { _ in true }

                gradeSection(run: run, inst: inst)
            }
            .padding(20)
            .readableWidth()
        }
    }

    @ViewBuilder
    private func gradeSection(run: GauntletRun, inst: CardInstance) -> some View {
        let fee = run.gradeFee(for: inst.card)
        if let g = inst.grade {
            VStack(spacing: 4) {
                Text("Graded PSA \(g)")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(gradeColor(g))
                Text(Economy.gradeLabel(g))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.subtle)
            }
            .frame(maxWidth: .infinity)
            .panel()
        } else {
            VStack(spacing: 8) {
                BigButton(title: "Grade for \(fee.moneyShort)",
                          subtitle: state.canGrade(showcaseIndex: index)
                            ? "Gambles a grade onto the card, changing its value"
                            : "Not enough cash — need \(fee.moneyShort)",
                          systemImage: "seal.fill",
                          tint: GauntletTheme.gold,
                          enabled: state.canGrade(showcaseIndex: index)) {
                    Haptics.play(.medium)
                    state.grade(showcaseIndex: index)
                }
            }
        }
    }

    private func badge(_ text: String, _ tint: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy))
            .foregroundStyle(tint)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.16)))
    }
}

// MARK: - Shop (between rounds)

struct ShopScreen: View {
    let state: GauntletState

    var body: some View {
        if let run = state.run {
            VStack(spacing: 14) {
                RoundClearedHero(run: run)

                VStack(spacing: 6) {
                    HStack {
                        Text("Cash").foregroundStyle(Palette.subtle)
                        Spacer()
                        Text(run.cash.money).foregroundStyle(Palette.money)
                    }
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    HStack(spacing: 5) {
                        Image(systemName: "banknote.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(hex: "ffd54a"))
                        Text("Keep it and earn +\(GauntletEconomy.interest(on: run.cash).moneyShort) interest at the next clear")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.subtle)
                        Spacer(minLength: 0)
                    }
                }
                .panel(12)

                ScrollView {
                    VStack(spacing: 10) {
                        ShopRow(icon: "rectangle.stack.badge.plus",
                                title: "Add Showcase Slot",
                                subtitle: "Now \(run.effectiveSlots) → \(run.effectiveSlots + 1)",
                                cost: run.nextSlotCost, affordable: run.cash >= run.nextSlotCost) {
                            Haptics.play(.light); state.buySlot()
                        }
                        ShopRow(icon: "bolt.badge.plus",
                                title: "Add Catalyst Slot",
                                subtitle: "Now \(run.effectiveCatalystSlots) → \(run.effectiveCatalystSlots + 1)",
                                cost: run.nextCatalystSlotCost, affordable: run.cash >= run.nextCatalystSlotCost) {
                            Haptics.play(.light); state.buyCatalystSlot()
                        }
                        Text("New element packs unlock on the pack rail during a round, not here.")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Palette.subtle)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 2)
                    }
                }

                BigButton(title: "Start Round \(run.round)",
                          subtitle: "Target \(fmt(run.target))",
                          systemImage: "play.fill", tint: GauntletTheme.tint) {
                    Haptics.play(.medium); state.continueFromShop()
                }
            }
        }
    }
}

/// Celebratory header for the between-rounds shop (reqs 2 & 3): an animated
/// "Round N Cleared" with the stipend and interest the clear just paid, so the
/// win and the banking reward both land clearly.
private struct RoundClearedHero: View {
    let run: GauntletRun
    @State private var appeared = false

    private var clearedRound: Int { max(1, run.round - 1) }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(Palette.money.opacity(0.16))
                    .frame(width: 74, height: 74)
                    .scaleEffect(appeared ? 1 : 0.3)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 46, weight: .bold))
                    .foregroundStyle(Palette.money)
                    .scaleEffect(appeared ? 1 : 0.3)
            }
            Text("Round \(clearedRound) Cleared!")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            HStack(spacing: 10) {
                EarningPill(label: "Stipend", amount: run.lastStipend, tint: Palette.money)
                EarningPill(label: "Interest", amount: run.lastInterest,
                            tint: Color(hex: "ffd54a"), dim: run.lastInterest <= 0)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 8)
        }
        .onAppear {
            appeared = false
            withAnimation(.spring(response: 0.5, dampingFraction: 0.62).delay(0.05)) { appeared = true }
        }
    }
}

private struct EarningPill: View {
    let label: String
    let amount: Double
    let tint: Color
    var dim: Bool = false
    var body: some View {
        VStack(spacing: 2) {
            Text("+\(amount.moneyShort)")
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(dim ? Palette.subtle : tint)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .heavy)).tracking(1)
                .foregroundStyle(Palette.subtle)
        }
        .frame(minWidth: 82)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill((dim ? Palette.subtle : tint).opacity(0.12)))
    }
}

private struct ShopRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let cost: Double
    let affordable: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(affordable ? Color(hex: "b06cf7") : Palette.subtle)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                Text(subtitle).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.subtle)
            }
            Spacer(minLength: 0)
            MiniButton(title: cost.moneyShort, tint: Color(hex: "6d5cf7"), enabled: affordable, action: action)
        }
        .panel(12)
    }
}

// MARK: - Reward (choose one Extended Art)

struct RewardScreen: View {
    let state: GauntletState

    private let cols = [GridItem(.adaptive(minimum: 108), spacing: 12)]

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("RUN CLEARED").font(.system(size: 12, weight: .black)).tracking(3)
                    .foregroundStyle(Color(hex: "ffd54a"))
                Text("Claim Extended Art").font(.system(size: 25, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text("Pick one Foil Extended Art for your Binder. Value, foils and grades stack over it.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.subtle)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
            }
            ScrollView {
                LazyVGrid(columns: cols, spacing: 14) {
                    ForEach(state.rewardOptions) { option in
                        Button {
                            Haptics.play(.success); state.chooseReward(option)
                        } label: {
                            VStack(spacing: 6) {
                                ZStack(alignment: .top) {
                                    CardView(card: option.card, instance: option.instance, width: 128)
                                    ExtendedArtRibbon()
                                        .padding(.top, 6)
                                }
                                Text(option.card.rarity.display.uppercased())
                                    .font(.system(size: 10, weight: .heavy))
                                    .foregroundStyle(option.card.rarity.accent)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

/// A gold "EXTENDED ART" ribbon overlaid on reward cards to signal the cosmetic
/// prize (the art swap itself ships with real assets later; this reads the intent).
private struct ExtendedArtRibbon: View {
    var body: some View {
        Text("EXTENDED ART")
            .font(.system(size: 8.5, weight: .black)).tracking(1)
            .foregroundStyle(Color(hex: "1a0d2e"))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(
                LinearGradient(colors: GauntletTheme.gold, startPoint: .leading, endPoint: .trailing)))
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
    }
}
