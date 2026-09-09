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
            .frame(minWidth: 44, minHeight: 44)
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
            CatalystEmblem(element: element)
                .padding(10 * s)
            RoundedRectangle(cornerRadius: 10 * s)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        }
        .frame(height: 150 * s)
        .clipShape(RoundedRectangle(cornerRadius: 10 * s))
    }

    private var valueBar: some View {
        HStack {
            Spacer()
            Text(catalyst.saleValue.money)
                .font(.system(size: 15 * s, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.money)
        }
    }
}

/// A Catalyst's element rendered as a clean, glowing icon (req: element icons).
/// Style "Emblem glow": a filled SF Symbol in the element tint with a soft halo
/// behind it, so each Catalyst reads instantly as its element — Fire (flame),
/// Water (droplet), Grass (leaf), Electric (bolt), Shadow (crescent moon). Scales
/// with the art window it fills, so it works from the 76pt pull row up to a full
/// card. Replaces the old procedural sigil on Catalyst faces.
struct CatalystEmblem: View {
    let element: Element

    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [element.badgeTint.opacity(0.55), .clear],
                                         center: .center, startRadius: 0, endRadius: d * 0.5))
                    .frame(width: d, height: d)
                    .blur(radius: d * 0.04)
                Image(systemName: element.glyphSymbol)
                    .font(.system(size: d * 0.46, weight: .black))
                    .foregroundStyle(element.badgeTint)
                    .shadow(color: .black.opacity(0.45), radius: d * 0.02, x: 0, y: d * 0.015)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

// MARK: - Run screen (the round loop)

struct RunScreen: View {
    let state: GauntletState
    var onHome: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var detail: ShowcaseSelection?
    @State private var confirmingEnd = false
    /// Measured height of the HUD panel, so the Home button can match it and the
    /// two tiles read as one row (req 4).
    @State private var hudHeight: CGFloat = 0

    var body: some View {
        if let run = state.run {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    GauntletHomeButton(side: hudHeight > 0 ? hudHeight : 76, action: onHome)
                    HUDPanel(run: run)
                        .background(GeometryReader { geo in
                            Color.clear.preference(key: HUDHeightKey.self, value: geo.size.height)
                        })
                }
                .onPreferenceChange(HUDHeightKey.self) { hudHeight = $0 }
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
                if state.isLastChance {
                    LastChancePanel(onEnd: { confirmingEnd = true })
                } else {
                    PackRail(state: state, run: run)
                }
            }
            .overlay {
                if state.confettiBurst > 0 && !reduceMotion {
                    ParticleBurst(colors: [Palette.money, Color(hex: "ffd54a"),
                                           Color(hex: "6d5cf7"), Color(hex: "b06cf7")])
                        .id(state.confettiBurst)
                        .allowsHitTesting(false)
                }
            }
            .fullScreenCover(isPresented: revealBinding) {
                GauntletRevealView(state: state, set: state.lastRippedSet)
            }
            .sheet(item: $detail, onDismiss: { state.finishGrading() }) { sel in
                ShowcaseCardDetail(state: state, index: sel.index) { detail = nil }
            }
            .alert("End this run?", isPresented: $confirmingEnd) {
                Button("End Run", role: .destructive) { state.endRound() }
                Button("Keep Playing", role: .cancel) {}
            } message: {
                Text("You still have an affordable grade to try. Your best pulls and earned Trainer milestones stay saved either way.")
            }
        }
    }

    private var revealBinding: Binding<Bool> {
        Binding(get: { state.revealActive }, set: { state.revealActive = $0 })
    }
}

/// Aura counted against the bar is shown **floored**, and the target **ceiled**, so
/// the integer readout can only reach "n / n" once the round is genuinely won
/// (`showcaseAura >= target`). Aura and targets are fractional (e.g. Medium round 2
/// is 26 × 1.88 ≈ 48.9), so plain rounding let a Showcase a hair short read as full
/// — 48.7 toward a 48.9 bar rounded to "49 / 49". Flooring the numerator keeps the
/// count honest; ceiling the goal keeps the pair from tying before the win.
private func fmtAura(_ v: Double) -> String { String(format: "%.0f", v.rounded(.down)) }
private func fmtGoal(_ v: Double) -> String { String(format: "%.0f", v.rounded(.up)) }
private func fmtChange(_ v: Double) -> String { String(format: "%+.2f", v) }

private struct LastChancePanel: View {
    let onEnd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Out of rips, not out of options", systemImage: "seal.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color(hex: "ffd54a"))
            Text("Grade a Showcase card for one last chance. Grades can lower Aura, too.")
                .font(.caption)
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(role: .destructive, action: onEnd) {
                    Text("End Run")
                        .font(.subheadline.weight(.bold))
                        .frame(minWidth: 120, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(Color(hex: "ff8a80"))
                .accessibilityIdentifier("gauntletEndRun")
                Spacer()
            }
        }
        .panel(12)
    }
}

/// Subtitle for the Championship (final round) shop CTA: current Aura and the
/// goal (gold) picked out against the button's gold skin. The Hard finale also
/// grants a bonus rip, so it appends "+1 rip" (green); Easy/Medium finales don't.
private func championshipSubtitle(_ run: GauntletRun) -> AttributedString {
    let base = AttributedString("Aura \(fmtAura(run.showcaseAura)) · Goal ")
    var goal = AttributedString(fmtGoal(run.target))
    goal.foregroundColor = Color(hex: "fff0c2")
    var result = base + goal
    if run.isBossRound {
        let sep = AttributedString(" · ")
        var rip = AttributedString("+1 rip")
        rip.foregroundColor = Color(hex: "bff7d4")
        result += sep + rip
    }
    return result
}

// MARK: Pack rail — one tile per element set (req 5)

/// Replaces the single "Rip a Pack" button. Each of the five element sets is a
/// tile: rippable once unlocked, otherwise shown locked. New sets are opened in
/// the between-rounds shop, so the rail itself only ever rips an already-open set
/// — the player picks which unlocked element to rip to chase its evolution lines.
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
            SectionTitle(text: "Packs — pick a set to rip")
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
            Text("Unlock other sets in the shop between rounds.")
                .font(.caption2)
                .foregroundStyle(Palette.subtle)
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
    /// Locked sets are opened only in the between-rounds shop, so on the mid-round
    /// rail this tile is inert unless the set is already unlocked and rippable.
    private var enabled: Bool { unlocked && state.canRip }

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
        .accessibilityIdentifier("gauntletPack-\(set)")
        .accessibilityLabel("\(CardDatabase.setName(set)) pack — \(statusLine)")
    }

    /// A miniature of the Classic pack wrapper, dimmed and locked when it isn't
    /// open this run. Locked sets are unlocked in the shop between rounds, so on the
    /// rail they always read as inert — there's no mid-round "afford to buy" state.
    private var packArt: some View {
        ZStack {
            PackWrapper(set: set, width: packWidth, detail: .mini)
                .saturation(unlocked ? 1 : 0.12)
                .opacity(unlocked ? (enabled ? 1 : 0.6) : 0.42)
            if !unlocked {
                ZStack {
                    Circle().fill(.black.opacity(0.55))
                        .frame(width: packWidth * 0.5, height: packWidth * 0.5)
                    Image(systemName: "lock.fill")
                        .font(.system(size: packWidth * 0.24, weight: .bold))
                        .foregroundStyle(.white.opacity(0.92))
                }
            }
        }
        .shadow(color: glow, radius: glow == .clear ? 0 : 6)
    }

    /// A tint halo that marks a pack you can rip right now. Locked sets never glow
    /// on the rail — they're opened in the shop, not here.
    private var glow: Color {
        unlocked && enabled ? element.badgeTint.opacity(0.55) : .clear
    }

    private var statusLine: String {
        unlocked ? "Rip" : "Locked"
    }
    private var statusTint: Color {
        if unlocked { return enabled ? element.badgeTint : Palette.subtle }
        return Palette.subtle
    }

    private func act() {
        // Locked sets are unlocked in the between-rounds shop, never mid-round.
        guard unlocked else { return }
        Haptics.play(.medium); state.rip(set: set)
    }
}

// MARK: HUD

private struct RipsRemainingBadge: View {
    let count: Int

    private var tint: Color {
        count <= 1 ? Color(hex: "ffd54a") : Color(hex: "cbb5ff")
    }

    var body: some View {
        HStack(spacing: 6) {
            Text("\(count)")
                .font(.system(size: 26, weight: .black, design: .rounded))
                .monospacedDigit()
            VStack(alignment: .leading, spacing: 0) {
                Text(count == 1 ? "RIP" : "RIPS")
                Text("LEFT")
            }
            .font(.system(size: 10, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.panel))
        .overlay(RoundedRectangle(cornerRadius: 12).fill(tint.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(tint.opacity(0.45), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) rip\(count == 1 ? "" : "s") left")
        .accessibilityIdentifier("gauntletRipsRemaining")
    }
}

private struct HUDPanel: View {
    let run: GauntletRun

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                RipsRemainingBadge(count: run.ripsLeft)
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(run.isFinalRound ? "Final round" : "Round") \(run.round) / \(run.roundsTotal)")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(run.isFinalRound ? Color(hex: "ffd54a") : .white)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(run.cash.moneyShort)
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(Palette.money)
                        .monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
            }

            HStack(spacing: 8) {
                Text("AURA")
                    .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(Palette.subtle)
                ProgressBar(value: run.showcaseAura, total: run.target,
                            tint: run.showcaseAura >= run.target ? Palette.money : Color(hex: "b06cf7"),
                            height: 8)
                Text("\(fmtAura(run.showcaseAura)) / \(fmtGoal(run.target))")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(run.showcaseAura >= run.target ? Palette.money : Palette.subtle)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("gauntletAura")
            .accessibilityLabel("Aura \(fmtAura(run.showcaseAura)) of \(fmtGoal(run.target))")
        }
        .panel()
    }
}

/// The Home control on the run screen: a circle that matches the HUD panel's
/// height so the two sit as one balanced row (req 4). Shaped like Classic mode's
/// round home button, sized up to anchor the HUD beside it.
private struct GauntletHomeButton: View {
    let side: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "house.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Palette.text)
                .frame(width: side, height: side)
                .background(Circle().fill(Palette.panel))
                .overlay(Circle().strokeBorder(Palette.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Home")
    }
}

/// Reports the HUD panel's measured height up to `RunScreen` so the Home button
/// can size itself to match.
private struct HUDHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

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
            CardView(card: inst.card, instance: inst, width: 76,
                     series: .gauntlet(inst.card, showcase: run.showcase))
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
                Text(auraPreview)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Palette.subtle)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    if state.canKeepPending {
                        MiniButton(title: "Keep", systemImage: "tray.and.arrow.down.fill",
                                   tint: Color(hex: "3fbf7f")) {
                            Haptics.play(.light); state.keep(inst)
                        }
                        .accessibilityIdentifier("gauntletKeep-\(inst.cardId)")
                    } else {
                        MiniButton(title: "Swap", systemImage: "arrow.left.arrow.right",
                                   tint: Color(hex: "3b82f6")) { onSwap(inst) }
                            .accessibilityIdentifier("gauntletSwap-\(inst.cardId)")
                    }
                    MiniButton(title: "Sell \(sellPreview)", systemImage: "dollarsign.circle.fill",
                               tint: Color(hex: "6d5cf7")) {
                        Haptics.play(.light); state.sell(inst)
                    }
                    .accessibilityIdentifier("gauntletSell-\(inst.cardId)")
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

    private var auraPreview: String {
        if run.canKeep { return "\(fmtChange(run.marginalAura(of: inst))) Aura if kept" }
        if let best = run.swapPreviews(for: inst).first {
            return "Best swap: \(fmtChange(best.auraChange)) Aura"
        }
        return "Showcase full"
    }
}

private struct ShowcaseSwapPicker: View {
    let state: GauntletState
    let incoming: CardInstance
    let onClose: () -> Void
    @State private var selectedId: UUID?

    var body: some View {
        NavigationStack {
            if let run = state.run {
                let previews = run.swapPreviews(for: incoming)
                let selected = previews.first { $0.id == selectedId }
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        CardView(card: incoming.card, instance: incoming, width: 54)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Make room for \(incoming.card.name)")
                                .font(.headline)
                                .foregroundStyle(.white)
                            Text("Compare the whole Showcase, including evolution bonuses. The replaced card is sold.")
                                .font(.caption)
                                .foregroundStyle(Palette.subtle)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(16)

                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(previews) { preview in
                                Button {
                                    Haptics.play(.light)
                                    selectedId = preview.id
                                } label: {
                                    swapOption(preview, run: run,
                                               isBest: preview.id == previews.first?.id)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("gauntletReplace-\(preview.index)")
                                .accessibilityAddTraits(selectedId == preview.id ? .isSelected : [])
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .accessibilityIdentifier("gauntletSwapOptions")

                    BigButton(title: selected.map { "Swap & sell \($0.outgoing.card.name)" } ?? "Choose a card to replace",
                              subtitle: selected.map { "Receive \($0.cashGain.money) · \(fmtChange($0.auraChange)) Aura" },
                              systemImage: "arrow.left.arrow.right", tint: GauntletTheme.tint,
                              enabled: selected != nil) {
                        if let selected {
                            state.swap(incoming, forShowcaseIndex: selected.index)
                            Haptics.play(.light)
                            onClose()
                        }
                    }
                    .accessibilityIdentifier("gauntletConfirmSwap")
                    .padding(16)
                    .background(.ultraThinMaterial)
                }
                .readableWidth()
                .background(GauntletBackdrop())
                .navigationTitle("Compare swaps")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: onClose)
                    }
                }
            }
        }
    }

    private func swapOption(_ preview: ShowcaseSwapPreview, run: GauntletRun, isBest: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selectedId == preview.id ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedId == preview.id ? Color(hex: "b06cf7") : Palette.subtle)
                VStack(alignment: .leading, spacing: 3) {
                    Text(preview.outgoing.card.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                    Text("Sell for \(preview.cashGain.money)")
                        .font(.caption)
                        .foregroundStyle(Palette.subtle)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(fmtChange(preview.auraChange)) Aura")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(preview.auraChange >= 0 ? Palette.money : Color(hex: "ff8a80"))
                        .monospacedDigit()
                    if isBest {
                        Text("MOST AURA")
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(Color(hex: "bfa3ff"))
                    }
                }
            }
            Text("Showcase after swap: \(fmtAura(preview.auraAfter)) / \(fmtGoal(run.target)) Aura")
                .font(.caption)
                .foregroundStyle(Palette.subtle)
            if !preview.brokenLineIds.isEmpty {
                Label("Breaks a completed evolution line", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(hex: "ffd54a"))
            }
            if !preview.completedLineIds.isEmpty {
                Label("Completes an evolution line", systemImage: "link")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.money)
            }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(12)
        .overlay(RoundedRectangle(cornerRadius: 18)
            .strokeBorder(selectedId == preview.id ? Color(hex: "b06cf7") : .clear, lineWidth: 2))
        .accessibilityElement(children: .combine)
    }
}

private struct CatalystOfferRow: View {
    let state: GauntletState
    let catalyst: Catalyst

    /// Presents the "replace which attuned Catalyst?" picker when slots are full.
    @State private var swapping = false

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
                Text(catalyst.effectSummary)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.subtle)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    if state.canAttunePending {
                        MiniButton(title: "Attune", systemImage: "sparkles",
                                   tint: Color(hex: "b06cf7")) {
                            Haptics.play(.success); state.attunePendingCatalyst()
                        }
                    } else if state.canSwapPending {
                        MiniButton(title: "Swap", systemImage: "arrow.left.arrow.right",
                                   tint: Color(hex: "b06cf7")) {
                            Haptics.play(.light); swapping = true
                        }
                    }
                    MiniButton(title: "Sell \(catalyst.saleValue.moneyShort)",
                               systemImage: "dollarsign.circle.fill", tint: Color(hex: "6d5cf7")) {
                        Haptics.play(.light); state.sellPendingCatalyst()
                    }
                }
                if state.canSwapPending {
                    Text("Catalyst slots full — swap one out or sell")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.subtle)
                } else if !state.canAttunePending {
                    Text("No catalyst slots — sell only")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.subtle)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(catalyst.element.badgeTint.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(catalyst.element.badgeTint.opacity(0.35), lineWidth: 1))
        .sheet(isPresented: $swapping) {
            CatalystSwapPicker(state: state, incoming: catalyst) { swapping = false }
        }
    }
}

/// The full-slots swap chooser: shows the incoming Catalyst and every attuned one,
/// so the player can trade a live effect for the new pull. Tapping a slot drops the
/// old effect and applies the new immediately (`swapPendingCatalyst`). (req: swap)
private struct CatalystSwapPicker: View {
    let state: GauntletState
    let incoming: Catalyst
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(text: "Swapping in")
                        HStack(alignment: .top, spacing: 12) {
                            CatalystCardView(catalyst: incoming, width: 86)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(incoming.name)
                                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                                    .foregroundStyle(.white)
                                Text(incoming.effectSummary)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(incoming.element.badgeTint)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .panel()

                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(text: "Replace which catalyst?")
                        ForEach(Array((state.run?.attunedCatalysts ?? []).enumerated()), id: \.offset) { idx, cat in
                            Button {
                                Haptics.play(.success)
                                state.swapPendingCatalyst(replacing: idx)
                                onClose()
                            } label: {
                                CatalystSwapOption(outgoing: cat)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .panel()
                }
                .padding(16)
                .readableWidth()
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(GauntletBackdrop().ignoresSafeArea())
            .navigationTitle("Swap Catalyst")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onClose() }
                }
            }
        }
    }
}

/// One replaceable slot in the swap picker: the attuned Catalyst that would be
/// dropped, its live effect, and a clear "replace" affordance.
private struct CatalystSwapOption: View {
    let outgoing: Catalyst

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(outgoing.element.badgeTint).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 3) {
                Text(outgoing.name)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text(outgoing.effectSummary)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.subtle)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Image(systemName: "arrow.left.arrow.right").font(.system(size: 11, weight: .bold))
                Text("Replace").font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(Color(hex: "b06cf7")))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Palette.bg0.opacity(0.4)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(outgoing.element.badgeTint.opacity(0.3), lineWidth: 1))
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
                Text("Rip packs and grow your Showcase to meet the round's goal.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.subtle)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8)
            } else {
                LazyVGrid(columns: cols, spacing: 10) {
                    ForEach(Array(run.showcase.enumerated()), id: \.element.id) { idx, inst in
                        if interactive {
                            Button { onTapCard(idx) } label: {
                                ShowcaseCardCell(run: run, inst: inst, width: 92)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("gauntletShowcase-\(idx)")
                        } else {
                            ShowcaseCardCell(run: run, inst: inst, width: 92)
                        }
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

/// A Showcase card cell that flags the evolution-line ("set") multiplier when the
/// card stands in a **completed** line: a set-colour glow frame plus a "×2.25" tab.
/// The cue reuses the same set tint the stage pips use, so a finished line reads as
/// one scoring unit and its Aura multiplier is legible at a glance. (req: cue)
private struct ShowcaseCardCell: View {
    let run: GauntletRun
    let inst: CardInstance
    var width: CGFloat = 92

    private var completed: Bool { run.isInCompletedLine(inst) }
    private var setTint: Color { Element.theme(forSet: inst.card.set).badgeTint }
    private var corner: CGFloat { 16 * (width / 230) }

    var body: some View {
        CardView(card: inst.card, instance: inst, width: width,
                 series: .gauntlet(inst.card, showcase: run.showcase),
                 pipsGlow: false)
            .overlay {
                if completed {
                    RoundedRectangle(cornerRadius: corner)
                        .strokeBorder(setTint, lineWidth: 2)
                        .shadow(color: setTint.opacity(0.85), radius: 6)
                }
            }
            .overlay(alignment: .bottom) {
                if completed { multiplierTab }
            }
    }

    /// A small "×2.25" tab straddling the bottom edge — the gap between the rarity
    /// badge (leading) and value (trailing), so it covers no card content.
    private var multiplierTab: some View {
        Text(String(format: "×%.2f", run.evoLineMultiplier(forSet: inst.card.set)))
            .font(.system(size: 10, weight: .black, design: .rounded))
            .foregroundStyle(Palette.bg0)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(setTint))
            .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
            .offset(y: 9)
            .accessibilityLabel(
                "Completed line, \(String(format: "%.2f", run.evoLineMultiplier(forSet: inst.card.set))) times Aura")
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
    @State private var gradeResult: GradeResult?

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
        .overlay {
            if let result = gradeResult {
                GradeRevealOverlay(result: result) {
                    gradeResult = nil
                    state.finishGrading()
                }
            }
        }
    }

    @ViewBuilder
    private func content(run: GauntletRun, inst: CardInstance) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                CardView(card: inst.card, instance: inst, width: 188,
                         series: .gauntlet(inst.card, showcase: run.showcase),
                         pipsGlow: false)
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
                                  currentCardId: inst.card.id) { id in
                    run.showcase.contains { $0.cardId == id }
                }
                if inst.card.stageCount > 1 && !run.isInCompletedLine(inst) {
                    Text("Only stages in your Showcase count toward the evolution bonus.")
                        .font(.caption)
                        .foregroundStyle(Palette.subtle)
                }

                if run.isInCompletedLine(inst) {
                    completedLineBanner(set: inst.card.set, mult: run.evoLineMultiplier(forSet: inst.card.set))
                }

                gradeSection(run: run, inst: inst)
            }
            .padding(20)
            .readableWidth()
        }
        .accessibilityIdentifier("gauntletCardDetails")
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
                            ? "Can raise or lower Aura. One grade per card."
                            : "Not enough cash — need \(fee.moneyShort)",
                          systemImage: "seal.fill",
                          tint: [Color(hex: "6d5cf7")],
                          enabled: state.canGrade(showcaseIndex: index)) {
                    Haptics.play(.medium)
                    if let result = state.grade(showcaseIndex: index, deferResolution: true) {
                        gradeResult = result
                    } else {
                        Haptics.play(.error)
                    }
                }
                .accessibilityIdentifier("gauntletGradeCard")
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

    /// The evolution-line ("set") multiplier cue in the detail view: a set-coloured
    /// banner that names the completed line and the Aura multiplier it earns, echoing
    /// the glow frame + "×2.25" tab on the Showcase grid. (req: cue)
    private func completedLineBanner(set: Int, mult: Double) -> some View {
        let tint = Element.theme(forSet: set).badgeTint
        return HStack(spacing: 10) {
            Image(systemName: "link.circle.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Evolution line complete")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text("Every card in this line scores more Aura")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.subtle)
            }
            Spacer(minLength: 0)
            Text(String(format: "×%.2f", mult))
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(Palette.bg0)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(tint))
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 14).fill(tint.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(tint.opacity(0.5), lineWidth: 1))
    }
}

// MARK: - Shop (between rounds)

struct ShopScreen: View {
    let state: GauntletState
    @State private var showingAllPacks = false

    private var paidPacks: [Int] { state.packTiers.filter { $0 > 1 } }

    var body: some View {
        if let run = state.run {
            let featuredPacks = paidPacks.filter {
                run.isPackUnlocked($0) || run.canUnlockPack($0) || $0 == run.nextLockedPack
            }
            let otherPacks = paidPacks.filter { !featuredPacks.contains($0) }
            VStack(spacing: 12) {
                RoundClearedHero(run: run)
                    .id(run.round)

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        nextRoundPreview(run)

                        SectionTitle(text: "Unlock packs · this run only")
                            .padding(.top, 4)
                        ForEach(featuredPacks, id: \.self) { set in
                            packRow(set, run: run)
                        }

                        SectionTitle(text: "Grow your build")
                            .padding(.top, 8)
                        ShopRow(glyph: .symbol("square.stack.3d.up.fill", tint: Color(hex: "6d5cf7")),
                                title: "Add Showcase Slot",
                                subtitle: "Now \(run.effectiveSlots) → \(run.effectiveSlots + 1)",
                                cost: run.nextSlotCost, cash: run.cash) {
                            Haptics.play(.light); state.buySlot()
                        }
                        .accessibilityIdentifier("gauntletBuyShowcaseSlot")
                        ShopRow(glyph: .symbol("bolt.circle.fill", tint: Color(hex: "ff9500")),
                                title: "Add Catalyst Slot",
                                subtitle: "Now \(run.effectiveCatalystSlots) → \(run.effectiveCatalystSlots + 1)",
                                cost: run.nextCatalystSlotCost, cash: run.cash) {
                            Haptics.play(.light); state.buyCatalystSlot()
                        }
                        .accessibilityIdentifier("gauntletBuyCatalystSlot")

                        if !otherPacks.isEmpty {
                            DisclosureGroup(isExpanded: $showingAllPacks) {
                                VStack(spacing: 10) {
                                    ForEach(otherPacks, id: \.self) { set in
                                        packRow(set, run: run)
                                    }
                                }
                                .padding(.top, 10)
                            } label: {
                                Text("More pack sets (\(otherPacks.count))")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Palette.text)
                                    .frame(minHeight: 44)
                            }
                            .tint(Palette.subtle)
                        }
                    }
                    .padding(.bottom, 8)
                }
                .scrollBounceBehavior(.basedOnSize)
                .accessibilityIdentifier("gauntletShopOffers")

                if run.isFinalRound {
                    BigButton(title: "Enter the Championship",
                              attributedSubtitle: championshipSubtitle(run),
                              systemImage: "play.fill", tint: GauntletTheme.championship) {
                        Haptics.play(.medium); state.continueFromShop()
                    }
                    .accessibilityIdentifier("gauntletNextRound")
                } else {
                    BigButton(title: run.auraShortfall == 0 ? "Bank Round \(run.round)" : "Start Round \(run.round)",
                              subtitle: run.auraShortfall == 0
                                ? "Target already met · Cash out \(run.ripsLeft) unused rips"
                                : "\(run.ripsLeft) rips · Need \(fmtGoal(run.auraShortfall)) more Aura",
                              systemImage: "play.fill", tint: GauntletTheme.tint) {
                        Haptics.play(.medium); state.continueFromShop()
                    }
                    .accessibilityIdentifier("gauntletNextRound")
                }
            }
        }
    }

    @ViewBuilder
    private func packRow(_ set: Int, run: GauntletRun) -> some View {
        if let cost = state.packUnlockCost(set) {
            ShopRow(glyph: .pack(set),
                    title: "\(CardDatabase.setName(set)) packs",
                    subtitle: "Unlock once, then spend rips to open",
                    cost: cost, cash: run.cash) {
                Haptics.play(.light); state.unlockPack(set)
            }
            .accessibilityIdentifier("gauntletUnlockPack-\(set)")
        } else {
            HStack(spacing: 12) {
                ShopGlyphView(glyph: .pack(set), affordable: true)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(CardDatabase.setName(set)) packs")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                    Label("Unlocked for this run", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Palette.money)
                }
                Spacer(minLength: 0)
            }
            .panel(12)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("gauntletUnlockedPack-\(set)")
        }
    }

    private func nextRoundPreview(_ run: GauntletRun) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(run.isFinalRound ? "Championship ahead" : "Round \(run.round) ahead",
                      systemImage: run.isFinalRound ? "trophy.fill" : "target")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                Spacer(minLength: 4)
                Text("\(run.ripsLeft) rips")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Palette.subtle)
            }
            ProgressBar(value: run.showcaseAura, total: run.target,
                        tint: run.auraShortfall == 0 ? Palette.money : Color(hex: "b06cf7"), height: 7)
            Text("\(fmtAura(run.showcaseAura)) / \(fmtGoal(run.target)) Aura"
                 + (run.auraShortfall == 0 ? " · Target already met" : " · \(fmtGoal(run.auraShortfall)) to go"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(run.auraShortfall == 0 ? Palette.money : Palette.text)
            Text("At this balance: +\(GauntletEconomy.interest(on: run.cash).money) interest at the next clear.")
                .font(.caption2)
                .foregroundStyle(Palette.subtle)
                .fixedSize(horizontal: false, vertical: true)
        }
        .panel(12)
    }
}

/// Earnings are historical; spendable cash is live. Never reconstruct a past
/// balance from current cash, which changes as soon as the player buys something.
private struct RoundClearedHero: View {
    let run: GauntletRun
    @State private var expanded = false

    private var clearedRound: Int { max(1, run.round - 1) }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Palette.money)
                Text("Round \(clearedRound) Cleared!")
                    .font(.system(size: 21, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 34)
            .frame(minHeight: 38)

            VStack(spacing: 10) {
                HStack {
                    Text("CASH TO SPEND")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(Palette.subtle)
                    Spacer()
                    Text(run.cash.money)
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(Palette.money)
                        .monospacedDigit()
                        .accessibilityIdentifier("gauntletShopCash")
                }
                DisclosureGroup(isExpanded: $expanded) {
                    VStack(spacing: 8) {
                        LedgerRow(label: "Interest", amount: run.lastInterest)
                        LedgerRow(label: "Round payout", amount: run.lastStipend)
                        LedgerRow(label: "Unused rips", amount: run.lastRipBank)
                    }
                    .padding(.top, 8)
                } label: {
                    HStack {
                        Text("Earned last round")
                        Spacer(minLength: 4)
                        Text("+\(run.lastClearEarnings.money)")
                            .foregroundStyle(Palette.money)
                            .monospacedDigit()
                            .accessibilityIdentifier("gauntletLastEarnings")
                    }
                    .font(.caption.weight(.semibold))
                }
                .tint(Palette.subtle)
                .accessibilityIdentifier("gauntletPayoutDetails")
            }
            .panel(12)
        }
    }
}

private struct LedgerRow: View {
    let label: String
    let amount: Double

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(Palette.subtle)
            Spacer()
            Text("+\(amount.money)")
                .font(.caption.weight(.bold))
                .foregroundStyle(Palette.text)
                .monospacedDigit()
        }
    }
}

/// The leading visual for a shop row. Either an element-tinted SF Symbol (the
/// Showcase / Catalyst slots, coloured to match the welcome screen's primer rows)
/// or an actual pack thumbnail for a set you can unlock.
private enum ShopGlyph {
    case symbol(String, tint: Color)
    case pack(Int)
}

/// Renders a `ShopGlyph`, greyed out until the purchase is affordable — the same
/// desaturate-and-dim treatment the pack rail uses on the run screen, so the eye
/// lands on what you can actually buy.
private struct ShopGlyphView: View {
    let glyph: ShopGlyph
    let affordable: Bool

    var body: some View {
        switch glyph {
        case let .symbol(name, tint):
            Image(systemName: name)
                .font(.system(size: 24))
                .foregroundStyle(tint)
                .saturation(affordable ? 1 : 0.12)
                .opacity(affordable ? 1 : 0.5)
        case let .pack(set):
            PackWrapper(set: set, width: 30, detail: .mini)
                .saturation(affordable ? 1 : 0.12)
                .opacity(affordable ? 1 : 0.5)
        }
    }
}

private struct ShopRow: View {
    let glyph: ShopGlyph
    let title: String
    let subtitle: String
    let cost: Double
    let cash: Double
    let action: () -> Void

    private var affordable: Bool { cash >= cost }

    var body: some View {
        HStack(spacing: 12) {
            ShopGlyphView(glyph: glyph, affordable: affordable)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                Text(subtitle).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.subtle)
                if !affordable {
                    Text("Need \((cost - cash).money) more")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color(hex: "ffd54a"))
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            MiniButton(title: cost.moneyShort, tint: Color(hex: "6d5cf7"), enabled: affordable, action: action)
                .accessibilityLabel("Buy \(title) for \(cost.money)")
                .accessibilityHint(affordable ? "Available for this run" : "Need \((cost - cash).money) more")
        }
        .panel(12)
    }
}

// MARK: - Reward (choose one Extended Art)

struct RewardScreen: View {
    let state: GauntletState

    // Space between the reward cards, and the breathing room reserved on each side
    // so the outer cards — and the "New" badge that overhangs their top-right —
    // never touch (or get clipped at) the container edges.
    private let cardSpacing: CGFloat = 10
    private let edgeInset: CGFloat = 14

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
            // Size the (always three) cards to the width actually available so all
            // three sit fully on screen — the old fixed 128pt width overflowed the
            // grid cells and clipped the left/right cards at the edges.
            GeometryReader { geo in
                let n = max(CGFloat(state.rewardOptions.count), 1)
                let usable = geo.size.width - edgeInset * 2 - cardSpacing * (n - 1)
                let cardW = min(140, floor(usable / n))
                HStack(alignment: .top, spacing: cardSpacing) {
                    ForEach(state.rewardOptions) { option in
                        rewardCell(option, width: cardW)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 12)   // headroom for the overhanging "New" badge
            }
        }
    }

    private func rewardCell(_ option: GauntletRewardOption, width: CGFloat) -> some View {
        Button {
            Haptics.play(.success); state.chooseReward(option)
        } label: {
            VStack(spacing: 5) {
                CardView(card: option.card, instance: option.instance,
                         width: width, extendedArt: true)
                    .overlay(alignment: .topTrailing) {
                        if state.isNewCard(option) { newFlag }
                    }
                Text("EXTENDED ART")
                    .font(.system(size: 9, weight: .black)).tracking(1)
                    .foregroundStyle(Color(hex: "ffd54a"))
                Text(option.card.rarity.display.uppercased())
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(option.card.rarity.accent)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("gauntletReward-\(option.cardId)")
    }

    /// The gold "New" flag on a reward whose **Extended Art** the Binder doesn't
    /// hold yet — the same ✦ NEW treatment Classic pops onto a first-copy pull. It
    /// tracks the art layer, so a Spryte already owned in standard art still reads
    /// "New" here while its Extended Art is unearned.
    private var newFlag: some View {
        Text("✦ NEW")
            .font(.system(size: 11, weight: .black))
            .foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(Color(hex: "ffd54a")))
            .overlay(Capsule().strokeBorder(.white.opacity(0.4), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
            .offset(x: 6, y: -6)
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        .overlay(alignment: .topTrailing) {
            if phase != .summary, let run = state.run {
                RipsRemainingBadge(count: run.ripsLeft)
                    .padding(16)
            }
        }
        .overlay {
            if state.confettiBurst > 0 && !reduceMotion {
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
                    case .card(let inst):    RevealingCardView(inst: inst, width: cardWidth, playFlipSound: i != 0,
                                                                series: state.run.map { CardSeries.gauntlet(inst.card, showcase: $0.showcase) })
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
            if let run = state.run {
                HUDPanel(run: run)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial)
            }
            ScrollView {
                VStack(spacing: 14) {
                    Text("Build your Showcase")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(.white)

                    if let run = state.run {
                        if !resolved {
                            PullPanel(state: state, run: run) { card in swapCandidate = card }
                        }
                        ShowcasePanel(run: run, interactive: false, titlePrefix: "Showcase") { _ in }
                        if !run.attunedCatalysts.isEmpty { AttunedPanel(run: run) }
                    }
                }
                .padding(16)
                .readableWidth()
            }
            .accessibilityIdentifier("gauntletSummaryScroll")
            continueBar
        }
        .sheet(item: $swapCandidate) { candidate in
            ShowcaseSwapPicker(state: state, incoming: candidate) {
                swapCandidate = nil
            }
        }
    }

    private var continueBar: some View {
        VStack(spacing: 6) {
            if !resolved {
                Text(pendingPrompt)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.subtle)
            }
            BigButton(title: continueTitle, subtitle: continueSubtitle,
                      systemImage: "checkmark.circle.fill",
                      tint: GauntletTheme.gold,
                      enabled: resolved) {
                Haptics.play(.success)
                state.finishReveal()
            }
            .accessibilityIdentifier("gauntletFinishPack")
        }
        .padding(16)
        .background(.ultraThinMaterial)
    }

    private var pendingPrompt: String {
        var parts: [String] = []
        let count = state.pendingCards.count
        if count > 0 { parts.append("\(count) card\(count == 1 ? "" : "s")") }
        if state.pendingCatalyst != nil { parts.append("1 Catalyst") }
        return parts.joined(separator: " + ") + " left to decide"
    }

    private var continueTitle: String {
        guard resolved, let run = state.run else { return "Finish pack" }
        if run.showcaseAura >= run.target { return run.isFinalRound ? "Claim your prize" : "Collect round rewards" }
        if run.ripsLeft == 0 { return run.hasAffordableGrade ? "Review last chance" : "See results" }
        return "Back to round \(run.round)"
    }

    private var continueSubtitle: String? {
        guard resolved, let run = state.run else { return nil }
        if run.showcaseAura >= run.target {
            let bank = GauntletEconomy.leftoverRipValue(round: run.round, rips: run.ripsLeft)
            return "Target reached · \(run.ripsLeft) unused rips bank \(bank.moneyShort)"
        }
        if run.ripsLeft == 0 {
            return run.hasAffordableGrade ? "No rips left. You can still try grading." : "No rips or affordable grades remain."
        }
        return "\(run.ripsLeft) rips left · Need \(fmtGoal(run.auraShortfall)) more Aura"
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
