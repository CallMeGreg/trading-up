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

/// A card-shaped face for a Catalyst so it reads as its own pull — distinct,
/// element-tinted artwork (a sigil) rather than a Spryte. Catalysts are never
/// part of the Binder; this only ever appears inside Gauntlet's rip/reveal flow.
/// Mirrors `CardView`'s proportions so it sits naturally beside real cards. (req 8b)
struct CatalystCardView: View {
    let catalyst: Catalyst
    var width: CGFloat = 230

    private var s: CGFloat { width / 230 }
    private var height: CGFloat { width * 1.4 }
    private var corner: CGFloat { 16 * s }
    private var element: Element { catalyst.element }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner)
                .fill(LinearGradient(colors: [Palette.panelHi, Palette.panel],
                                     startPoint: .top, endPoint: .bottom))

            VStack(spacing: 6 * s) {
                header
                artWindow
                Text("CATALYST")
                    .font(.system(size: 10 * s, weight: .black)).tracking(2 * s)
                    .foregroundStyle(element.badgeTint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(catalyst.blurb)
                    .font(.system(size: 10.5 * s, weight: .regular, design: .serif)).italic()
                    .foregroundStyle(Palette.text.opacity(0.78))
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
                valueBar
            }
            .padding(10 * s)

            RoundedRectangle(cornerRadius: corner)
                .strokeBorder(
                    LinearGradient(colors: [element.badgeTint, element.badgeTint.opacity(0.5)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 2 * s)
        }
        .frame(width: width, height: height)
        .shadow(color: .black.opacity(0.45), radius: 8 * s, x: 0, y: 4 * s)
    }

    private var header: some View {
        HStack(spacing: 4 * s) {
            Text(catalyst.name)
                .font(.system(size: 16 * s, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.text)
                .lineLimit(1).minimumScaleFactor(0.6)
            Spacer(minLength: 2 * s)
            Text(element.display)
                .font(.system(size: 9 * s, weight: .bold))
                .foregroundStyle(element.badgeTint)
                .padding(.horizontal, 6 * s).padding(.vertical, 3 * s)
                .background(Capsule().fill(element.badgeTint.opacity(0.14)))
        }
    }

    private var artWindow: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10 * s).fill(element.artGradient)
            SigilView(seed: catalyst.id + element.rawValue, element: element)
                .padding(6 * s)
            RoundedRectangle(cornerRadius: 10 * s)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        }
        .frame(height: 150 * s)
        .clipShape(RoundedRectangle(cornerRadius: 10 * s))
    }

    private var valueBar: some View {
        HStack {
            Text("SELL")
                .font(.system(size: 9.5 * s, weight: .heavy))
                .foregroundStyle(element.badgeTint)
                .padding(.horizontal, 7 * s).padding(.vertical, 3 * s)
                .background(Capsule().fill(element.badgeTint.opacity(0.16)))
            Spacer()
            Text(catalyst.saleValue.money)
                .font(.system(size: 15 * s, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.money)
        }
    }
}

// MARK: - Run screen (the round loop)

struct RunScreen: View {
    let state: GauntletState
    @State private var detail: ShowcaseSelection?

    var body: some View {
        if let run = state.run {
            VStack(spacing: 12) {
                HUDPanel(run: run)
                ScrollView {
                    VStack(spacing: 12) {
                        ShowcasePanel(run: run) { idx in
                            detail = ShowcaseSelection(index: idx)
                        }
                        if !run.attunedCatalysts.isEmpty {
                            AttunedPanel(run: run)
                        }
                    }
                    .padding(.bottom, 4)
                }
                PackRail(state: state, run: run)
            }
            .overlay {
                if state.confettiBurst > 0 {
                    ParticleBurst(colors: [Palette.money, Color(hex: "ffd54a"),
                                           Color(hex: "6d5cf7"), Color(hex: "b06cf7")])
                        .id(state.confettiBurst)
                        .allowsHitTesting(false)
                }
            }
            .fullScreenCover(isPresented: revealBinding) {
                GauntletRevealView(state: state, set: state.lastRippedSet)
            }
            .sheet(item: $detail) { sel in
                ShowcaseCardDetail(state: state, index: sel.index) { detail = nil }
            }
        }
    }

    private var revealBinding: Binding<Bool> {
        Binding(get: { state.revealActive }, set: { state.revealActive = $0 })
    }
}

private func fmt(_ v: Double) -> String { String(format: "%.0f", v) }

// MARK: Pack rail — one tile per element set (req 5)

/// Replaces the single "Rip a Pack" button. Each of the five element sets is a
/// tile: rippable once unlocked, buy-to-unlock when it's next in line, or greyed
/// out further up the rail. The player picks which unlocked element to rip, so
/// they can chase a set to complete its evolution lines.
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
    /// Cost to open this locked set (every locked set is independently buyable).
    private var unlockCost: Double? { state.packUnlockCost(set) }
    /// Whether the run can afford to open this locked set right now.
    private var affordable: Bool { state.canUnlockPack(set) }
    private var enabled: Bool { unlocked ? state.canRip : affordable }

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
    /// yet available this run. Affordable locked packs read a touch brighter so the
    /// eye lands on what you can buy open.
    private var packArt: some View {
        ZStack {
            PackWrapper(set: set, width: packWidth, detail: .mini)
                .saturation(unlocked ? 1 : 0.12)
                .opacity(unlocked ? (enabled ? 1 : 0.6) : (affordable ? 0.72 : 0.42))
            if !unlocked {
                ZStack {
                    Circle().fill(.black.opacity(0.55))
                        .frame(width: packWidth * 0.5, height: packWidth * 0.5)
                    Image(systemName: affordable ? "lock.open.fill" : "lock.fill")
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
        if !unlocked && affordable { return Color(hex: "ffd54a").opacity(0.6) }
        return .clear
    }

    private var statusLine: String {
        if unlocked { return "Rip" }
        if let cost = unlockCost { return "Unlock \(cost.moneyShort)" }
        return "Locked"
    }
    private var statusTint: Color {
        if unlocked { return enabled ? element.badgeTint : Palette.subtle }
        return affordable ? Palette.money : Palette.subtle
    }

    private func act() {
        if unlocked {
            Haptics.play(.medium); state.rip(set: set)
        } else if affordable {
            Haptics.play(.success); state.unlockPack(set)
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
                Text(run.cash.moneyShort)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(Palette.money)
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
        HStack(alignment: .top, spacing: 12) {
            CatalystCardView(catalyst: catalyst, width: 76)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
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
                }
                if !state.canAttunePending {
                    Text("Catalyst slots full")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.subtle)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(catalyst.element.badgeTint.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(catalyst.element.badgeTint.opacity(0.35), lineWidth: 1))
    }
}

// MARK: Showcase

private struct ShowcasePanel: View {
    let run: GauntletRun
    var interactive: Bool = true
    var titlePrefix: String = "Showcase"
    let onTapCard: (Int) -> Void

    private let cols = [GridItem(.adaptive(minimum: 92), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "\(titlePrefix) \(run.showcase.count)/\(run.effectiveSlots)")
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
                        .disabled(!interactive)
                    }
                }
                if interactive {
                    Text("Tap a card to grade it.")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Palette.subtle)
                }
            }
        }
        .panel()
    }
}

private struct AttunedPanel: View {
    let run: GauntletRun
    @State private var selected: Catalyst?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: "Attuned \(run.attunedCatalysts.count)/\(run.effectiveCatalystSlots)")
            FlowRow(items: run.attunedCatalysts) { catalyst in
                Button {
                    Haptics.play(.light); selected = catalyst
                } label: {
                    CatalystChip(catalyst: catalyst)
                }
                .buttonStyle(.plain)
            }
        }
        .panel()
        .sheet(item: $selected) { CatalystDetailSheet(catalyst: $0) }
    }
}

/// The tap-to-inspect view for an attuned Catalyst: its full card face plus a
/// plain-language line of the run-long effect it's granting. (req 1)
private struct CatalystDetailSheet: View {
    let catalyst: Catalyst
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            GauntletBackdrop()
            ScrollView {
                VStack(spacing: 18) {
                    CatalystCardView(catalyst: catalyst, width: 220)
                        .padding(.top, 24)

                    VStack(spacing: 8) {
                        Text("ATTUNED EFFECT")
                            .font(.system(size: 11, weight: .black)).tracking(1.5)
                            .foregroundStyle(catalyst.element.badgeTint)
                        Text(catalyst.effectSummary)
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                        Text("Active for the rest of this run.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Palette.subtle)
                    }
                    .frame(maxWidth: .infinity)
                    .panel()
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 24)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 26))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Palette.subtle)
            }
            .buttonStyle(.plain)
            .padding(14)
            .accessibilityLabel("Close catalyst")
        }
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
                          tint: [Color(hex: "6d5cf7")],
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
/// "Round N Cleared" above a stacked payout ledger. Interest is banked first (on
/// the cash carried into the clear), then the round payout, so the player can read
/// exactly how their ending cash was built.
private struct RoundClearedHero: View {
    let run: GauntletRun
    @State private var appeared = false

    private var clearedRound: Int { max(1, run.round - 1) }
    /// Cash carried into the clear, before interest + payout + banked rips were added.
    private var carried: Double {
        max(0, run.cash - run.lastInterest - run.lastStipend - run.lastRipBank)
    }

    var body: some View {
        VStack(spacing: 12) {
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

            VStack(spacing: 9) {
                LedgerRow(label: "Carried over", amount: carried, style: .base)
                LedgerRow(label: "Interest", amount: run.lastInterest,
                          style: .add, tint: Color(hex: "ffd54a"), dim: run.lastInterest <= 0)
                LedgerRow(label: "Round Payout", amount: run.lastStipend,
                          style: .add, tint: Palette.money)
                if run.lastRipBank > 0 {
                    LedgerRow(label: "Rips Banked", amount: run.lastRipBank,
                              style: .add, tint: Color(hex: "b06cf7"))
                }
                Rectangle().fill(Palette.stroke).frame(height: 1).padding(.vertical, 1)
                LedgerRow(label: "Cash", amount: run.cash, style: .total, tint: Palette.money)
            }
            .panel(14)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 8)
        }
        .onAppear {
            appeared = false
            withAnimation(.spring(response: 0.5, dampingFraction: 0.62).delay(0.05)) { appeared = true }
        }
    }
}

/// One line of the round-clear payout ledger: a subtle carried-over base, the two
/// "+" credits (interest, then payout), and the emphasized ending-cash total.
private struct LedgerRow: View {
    enum Style { case base, add, total }
    let label: String
    let amount: Double
    var style: Style
    var tint: Color = Palette.text
    var dim: Bool = false

    private var valueText: String {
        switch style {
        case .base:  return amount.money
        case .add:   return "+\(amount.moneyShort)"
        case .total: return amount.money
        }
    }
    private var labelColor: Color { Palette.subtle }
    private var valueColor: Color {
        if dim { return Palette.subtle }
        switch style {
        case .base:  return Palette.text
        case .add:   return tint
        case .total: return tint
        }
    }

    var body: some View {
        HStack {
            Text(label.uppercased())
                .font(.system(size: style == .total ? 12 : 11, weight: .heavy)).tracking(1)
                .foregroundStyle(labelColor)
            Spacer()
            Text(valueText)
                .font(.system(size: style == .total ? 20 : 16,
                              weight: style == .base ? .heavy : .black, design: .rounded))
                .foregroundStyle(valueColor)
        }
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
                            VStack(spacing: 5) {
                                CardView(card: option.card, instance: option.instance,
                                         width: 128, extendedArt: true)
                                Text("EXTENDED ART")
                                    .font(.system(size: 9, weight: .black)).tracking(1)
                                    .foregroundStyle(Color(hex: "ffd54a"))
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

// MARK: - Full-screen pack reveal (req 5)

/// Gauntlet's pack opening. Reuses Classic's sealed-pack tear (`SealedPackView`)
/// and card-by-card flip (`RevealingCardView`), then lands on a Gauntlet summary
/// where the pull is kept/sold/swapped and any Catalyst attuned — with the live
/// Showcase shown beneath so the trade-offs are obvious. A Catalyst flows through
/// the reveal as its own card face (`CatalystRevealCard`), taking a card's slot
/// (req 8b). Presented as a `fullScreenCover`; `state.finishReveal()` dismisses it
/// once the pull is fully resolved.
struct GauntletRevealView: View {
    let state: GauntletState
    let set: Int

    @State private var phase: Phase = .sealed
    @State private var items: [RevealItem] = []
    @State private var swapCandidate: CardInstance?

    private enum Phase: Equatable { case sealed, revealing(Int), summary }

    /// A pull entry to reveal — a real card, or the Catalyst that took a slot.
    private enum RevealItem: Identifiable {
        case card(CardInstance)
        case catalyst(Catalyst)
        var id: String {
            switch self {
            case .card(let c):     return "c-\(c.id.uuidString)"
            case .catalyst(let c): return "k-\(c.id)"
            }
        }
    }

    private var element: Element { Element.theme(forSet: set) }
    private var resolved: Bool { state.pendingCards.isEmpty && state.pendingCatalyst == nil }

    var body: some View {
        ZStack {
            Palette.bg0.ignoresSafeArea()
            RadialGradient(gradient: Gradient(colors: [element.palette[2].opacity(0.35), .clear]),
                           center: .center, startRadius: 20, endRadius: 400)
                .ignoresSafeArea()

            switch phase {
            case .sealed:          SealedPackView(set: set, isBox: false) { advance() }
            case .revealing(let i): revealingView(i)
            case .summary:          summaryView
            }
        }
        .overlay {
            if state.confettiBurst > 0 {
                ParticleBurst(colors: [Palette.money, Color(hex: "ffd54a"),
                                       Color(hex: "6d5cf7"), Color(hex: "b06cf7")])
                    .id(state.confettiBurst)
                    .allowsHitTesting(false)
            }
        }
        .onAppear(perform: snapshot)
    }

    /// Freeze the pull into an ordered reveal list the first time we appear — the
    /// live `pendingCards` shrinks as the summary resolves cards, so the flip
    /// sequence must run off a snapshot.
    private func snapshot() {
        guard items.isEmpty else { return }
        var list: [RevealItem] = state.pendingCards.map { .card($0) }
        if let cat = state.pendingCatalyst { list.append(.catalyst(cat)) }
        items = list
        if list.isEmpty { phase = .summary }
    }

    // MARK: Revealing

    private func revealingView(_ i: Int) -> some View {
        GeometryReader { geo in
            let chrome: CGFloat = 170
            let availableForCard = max(120, geo.size.height - chrome)
            let cardWidth = min(280, availableForCard / 1.4, geo.size.width * 0.78)
            let item = items[i]

            VStack(spacing: 20) {
                HStack(spacing: 7) {
                    ForEach(items.indices, id: \.self) { idx in
                        Circle()
                            .fill(idx <= i ? dotColor(items[idx]) : Palette.stroke)
                            .frame(width: 9, height: 9)
                    }
                }
                .padding(.top, 24)

                Spacer()

                Group {
                    switch item {
                    case .card(let inst):    RevealingCardView(inst: inst, width: cardWidth, playFlipSound: i != 0)
                    case .catalyst(let cat): CatalystRevealCard(catalyst: cat, width: cardWidth)
                    }
                }
                .id(i)
                .transition(.opacity)

                Spacer()

                VStack(spacing: 4) {
                    Text(label(item).uppercased())
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(labelColor(item))
                    Text(i + 1 == items.count ? "Tap to finish" : "Tap for next card")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.subtle)
                }
                .padding(.bottom, 44)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .contentShape(Rectangle())
        .onTapGesture { advance() }
    }

    private func dotColor(_ item: RevealItem) -> Color {
        switch item {
        case .card(let inst):    return inst.card.rarity.accent
        case .catalyst(let cat): return cat.element.badgeTint
        }
    }
    private func label(_ item: RevealItem) -> String {
        switch item {
        case .card(let inst): return inst.card.rarity.display
        case .catalyst:       return "Catalyst"
        }
    }
    private func labelColor(_ item: RevealItem) -> Color {
        switch item {
        case .card(let inst):    return inst.card.rarity.accent
        case .catalyst(let cat): return cat.element.badgeTint
        }
    }

    // MARK: Summary

    private var summaryView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 14) {
                    Text("Pack Opened")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.top, 16)

                    if let run = state.run {
                        if resolved {
                            Text("Pull resolved — here's your showcase.")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Palette.subtle)
                        } else {
                            PullPanel(state: state, run: run) { card in swapCandidate = card }
                        }
                        ShowcasePanel(run: run, interactive: false, titlePrefix: "Your Showcase") { _ in }
                        if !run.attunedCatalysts.isEmpty { AttunedPanel(run: run) }
                    }
                }
                .padding(16)
                .readableWidth()
            }
            continueBar
        }
        .confirmationDialog("Swap in — replace which card?",
                            isPresented: swapBinding, presenting: swapCandidate) { cand in
            if let run = state.run {
                ForEach(run.showcase.indices, id: \.self) { i in
                    Button("Replace \(run.showcase[i].card.name) · \(run.showcase[i].currentValue.money)") {
                        state.swap(cand, forShowcaseIndex: i)
                        swapCandidate = nil
                        Haptics.play(.light)
                    }
                }
            }
            Button("Cancel", role: .cancel) { swapCandidate = nil }
        }
    }

    private var continueBar: some View {
        VStack(spacing: 6) {
            if !resolved {
                Text("Keep or sell every card to continue")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.subtle)
            }
            BigButton(title: "Continue",
                      systemImage: "checkmark.circle.fill",
                      tint: GauntletTheme.gold,
                      enabled: resolved) {
                Haptics.play(.success)
                state.finishReveal()
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
    }

    private var swapBinding: Binding<Bool> {
        Binding(get: { swapCandidate != nil }, set: { if !$0 { swapCandidate = nil } })
    }

    // MARK: Flow

    private func advance() {
        switch phase {
        case .sealed:
            guard !items.isEmpty else { phase = .summary; return }
            haptic(items[0])
            withAnimation(.spring(response: 0.5, dampingFraction: 0.68)) { phase = .revealing(0) }
        case .revealing(let i):
            let next = i + 1
            if next < items.count {
                haptic(items[next])
                withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { phase = .revealing(next) }
            } else {
                Haptics.play(.success)
                withAnimation(.easeOut(duration: 0.35)) { phase = .summary }
            }
        case .summary:
            break
        }
    }

    private func haptic(_ item: RevealItem) {
        switch item {
        case .card(let inst):
            if inst.foil || inst.card.rarity == .ultra { Haptics.play(.heavy) }
            else if inst.card.rarity == .rare { Haptics.play(.medium) }
            else { Haptics.play(.light) }
        case .catalyst:
            Haptics.play(.medium)
        }
    }
}

/// A Catalyst turning up during a reveal: its card face springs in behind an
/// element-tinted glow with a short sting, so it reads as a genuine pull rather
/// than a menu item.
private struct CatalystRevealCard: View {
    let catalyst: Catalyst
    var width: CGFloat = 280

    @State private var appear = false

    var body: some View {
        CatalystCardView(catalyst: catalyst, width: width)
            .scaleEffect(appear ? 1 : 0.82)
            .opacity(appear ? 1 : 0)
            .background {
                GlowBurst(color: catalyst.element.badgeTint, diameter: width * 1.5)
                    .scaleEffect(appear ? 1 : 0.55)
                    .opacity(appear ? 1 : 0)
                    .animation(.easeOut(duration: 0.45), value: appear)
            }
            .onAppear {
                Sound.play(.rare)
                withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) { appear = true }
            }
    }
}
