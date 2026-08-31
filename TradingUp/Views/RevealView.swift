import SwiftUI

/// Dramatic pack / box opening. Packs reveal one card at a time with a tap.
/// A booster box reveals each of its packs in turn — the same card-by-card
/// flip and keep/sell summary as a single pack — advancing automatically to
/// the next pack once its cards are kept or sold, with a "Pack X of N" counter.
struct RevealView: View {
    let content: RevealContent
    let set: Int
    let onDone: () -> Void

    @Environment(GameState.self) private var game: GameState

    @State private var phase: Phase = .sealed
    @State private var packIndex = 0
    /// The pack currently being revealed. For a box, the next pack's result.
    @State private var current: OpenResult? = nil
    /// Short-lived "Evolution Complete!" toasts, shown on the exact card that
    /// finishes each line during the reveal. Several can stack when multiple
    /// lines finish in one pack, and each lingers on its own 3s timer even as the
    /// player taps on to later cards. The permanent banners still live on the
    /// summary; these are just the in-the-moment celebration (req 2).
    @State private var evoBanners: [BonusEvent] = []

    private enum Phase: Equatable {
        case sealed
        case revealing(Int)
        case summary
    }

    private var element: Element { Element.theme(forSet: set) }

    private var isBox: Bool { if case .box = content { return true }; return false }
    private var packCount: Int {
        switch content {
        case .pack:             return 1
        case .box(let results): return results.count
        }
    }

    var body: some View {
        ZStack {
            Palette.bg0.ignoresSafeArea()
            RadialGradient(
                gradient: Gradient(colors: [element.palette[2].opacity(0.35), .clear]),
                center: .center, startRadius: 20, endRadius: 400
            )
            .ignoresSafeArea()

            switch phase {
            case .sealed:
                sealedView
            case .revealing(let i):
                if let result = current { revealingView(result, i) }
            case .summary:
                if let result = current {
                    SummaryView(
                        result: result,
                        set: set,
                        packCounter: isBox ? PackCounter(index: packIndex, total: packCount) : nil,
                        onDone: resolvePack
                    )
                    .id(packIndex)
                }
            }
        }
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                ForEach(evoBanners) { bonus in
                    EvolutionPopupBanner(bonus: bonus)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        // Each toast lives a fixed 3s from when it appears,
                        // independent of taps, so spam-advancing still shows what
                        // was earned. The task is tied to this banner's identity,
                        // so later cards neither restart nor cancel its timer.
                        .task {
                            try? await Task.sleep(nanoseconds: 3_000_000_000)
                            guard !Task.isCancelled else { return }
                            withAnimation(.easeOut(duration: 0.3)) {
                                evoBanners.removeAll { $0.id == bonus.id }
                            }
                        }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
        }
        .onChange(of: phase) { _, newPhase in updateEvoBanners(for: newPhase) }
    }

    /// Stack an evolution toast on the exact card that finishes a line, under any
    /// still-visible earlier toasts. A card that completes no line leaves the
    /// current toasts alone — they expire on their own 3s timers rather than when
    /// the player advances. Leaving the reveal clears them; the summary shows its
    /// own permanent banners.
    private func updateEvoBanners(for phase: Phase) {
        guard case .revealing(let i) = phase else {
            if !evoBanners.isEmpty {
                withAnimation(.easeOut(duration: 0.3)) { evoBanners.removeAll() }
            }
            return
        }
        guard let result = current, let bonus = evoCompletion(at: i, in: result),
              !evoBanners.contains(where: { $0.id == bonus.id }) else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            evoBanners.append(bonus)
        }
    }

    /// The evolution bonus (if any) that this pack finishes on the card at
    /// `index` — i.e. the last of the line's cards to appear in the pulled order.
    private func evoCompletion(at index: Int, in result: OpenResult) -> BonusEvent? {
        for bonus in result.bonuses where bonus.kind == .evolution {
            guard let lineId = bonus.lineId,
                  let lineCards = CardDatabase.evolutionLines[lineId] else { continue }
            let lineIds = Set(lineCards.map(\.id))
            let idxs = result.pulled.indices.filter { lineIds.contains(result.pulled[$0].cardId) }
            if let last = idxs.max(), last == index { return bonus }
        }
        return nil
    }

    // MARK: Sealed

    private var sealedView: some View {
        SealedPackView(set: set, isBox: isBox) { startPack(0) }
    }

    // MARK: Revealing

    private func revealingView(_ result: OpenResult, _ i: Int) -> some View {
        let inst = result.pulled[i]
        let isNew = !result.preOwnedIds.contains(inst.cardId)
        return GeometryReader { geo in
            // On a short frame (e.g. 402pt-tall landscape phone) a fixed 280pt-wide
            // card (392pt tall) plus its chrome would overflow, so scale the card
            // down to whatever height is actually available instead of clipping.
            let chrome: CGFloat = isBox ? 262 : 170
            let availableForCard = max(120, geo.size.height - chrome)
            let cardWidth = min(280, availableForCard / 1.4, geo.size.width * 0.78)

            VStack(spacing: 20) {
                if isBox {
                    PackTray(set: set, opened: packIndex + 1, total: packCount,
                             width: min(260, geo.size.width - 60), columns: packCount,
                             caption: "Pack \(packIndex + 1) of \(packCount)")
                        .padding(.top, 16)
                }
                HStack(spacing: 7) {
                    ForEach(result.pulled.indices, id: \.self) { idx in
                        Circle()
                            .fill(idx <= i ? result.pulled[idx].card.rarity.accent : Palette.stroke)
                            .frame(width: 9, height: 9)
                    }
                }
                .padding(.top, 24)

                Spacer()

                RevealingCardView(inst: inst, isNew: isNew, width: cardWidth, playFlipSound: i != 0,
                                  series: CardSeries(for: inst.card, pull: true) { game.owns($0.id) })
                    .id(i)
                    .transition(.opacity)

                Spacer()

                VStack(spacing: 4) {
                    Text(inst.card.rarity.display.uppercased())
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(inst.card.rarity.accent)
                    Text(i + 1 == result.pulled.count ? "Tap to finish" : "Tap for next card")
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

    // MARK: Flow

    private func advance() {
        switch phase {
        case .sealed:
            startPack(0)
        case .revealing(let i):
            guard let result = current else { return }
            let next = i + 1
            if next < result.pulled.count {
                haptic(for: result.pulled[next])
                withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { phase = .revealing(next) }
            } else {
                Haptics.play(.success)
                withAnimation(.easeOut(duration: 0.35)) { phase = .summary }
            }
        case .summary:
            break
        }
    }

    /// Begin revealing pack `index`. All cards were already added to the
    /// collection when the box was bought; this just selects which pack to show.
    private func startPack(_ index: Int) {
        let result: OpenResult
        switch content {
        case .pack(let r):      result = r
        case .box(let results): result = results[index]
        }
        current = result
        packIndex = index
        haptic(for: result.pulled[0])
        withAnimation(.spring(response: 0.5, dampingFraction: 0.68)) { phase = .revealing(0) }
    }

    /// Called when the player finishes a pack's summary (kept or sold). Advances
    /// to the next pack of a box, or finishes when the last pack is done.
    private func resolvePack() {
        if isBox, packIndex + 1 < packCount {
            startPack(packIndex + 1)
        } else {
            onDone()
        }
    }

    private func haptic(for inst: CardInstance) {
        if inst.foil || inst.card.rarity == .ultra { Haptics.play(.heavy) }
        else if inst.card.rarity == .rare { Haptics.play(.medium) }
        else { Haptics.play(.light) }
    }
}

// MARK: - Summary

/// Position of a pack within a booster box, shown as a "Pack X of N" counter.
struct PackCounter: Equatable {
    let index: Int
    let total: Int
}

/// Live per-card state on the pack summary. Boxes don't use this (bulk flow).
enum PackSlot: Equatable { case newCard, keeperExisting, pendingDup, keptDup, sold }

private struct SummaryView: View {
    @Environment(GameState.self) var game: GameState
    let result: OpenResult
    let set: Int
    var packCounter: PackCounter? = nil
    let onDone: () -> Void

    /// One-time classification of each pulled instance, snapshotted before any
    /// selling so keeper decisions don't shift as dupes are sold.
    private enum BaseKind { case newCard, keeperExisting, duplicate }

    /// Boxed in a reference type so the plan can be computed on the first `body`
    /// pass — before the first frame is drawn — rather than in `onAppear`.
    /// Computing it in `onAppear` left one frame where every card was still
    /// unclassified, which `slot(for:)` treated as a pending duplicate and
    /// flashed Keep/Sell buttons onto brand-new cards before correcting itself.
    private final class Plan { var kinds: [UUID: BaseKind]? = nil }
    @State private var plan = Plan()
    @State private var soldIds: Set<UUID> = []
    @State private var keptIds: Set<UUID> = []
    /// Cards graded right here on the summary — kept so their fresh slab and new
    /// value stay on screen even though `result.pulled` is an open-time snapshot.
    @State private var gradedInstances: [UUID: CardInstance] = [:]
    /// The PSA reveal to show after a grade roll, mirroring the Collection flow.
    @State private var gradeResult: GradeResult?

    /// Lazily computed and cached: the first read takes the snapshot, later
    /// reads return it, so a card's kind stays stable as the collection changes.
    private var baseKind: [UUID: BaseKind] {
        if let kinds = plan.kinds { return kinds }
        let kinds = computePlan()
        plan.kinds = kinds
        return kinds
    }

    private let blue = [Color(hex: "3b82f6"), Color(hex: "6d5cf7")]
    private let green = [Palette.money, Color(hex: "2fae63")]

    private var totalValue: Double { result.pulled.reduce(0) { $0 + $1.currentValue } }
    private var foils: [CardInstance] { result.pulled.filter { $0.foil } }
    private var ultras: [CardInstance] { result.pulled.filter { $0.card.rarity == .ultra } }

    // Box highlights: show only the exciting cards (too many to list all).
    private var boxHighlights: [CardInstance] {
        Array((ultras + foils.filter { $0.card.rarity != .ultra })
            .reduce(into: [CardInstance]()) { acc, x in if !acc.contains(where: { $0.id == x.id }) { acc.append(x) } })
    }

    // Pack duplicates the player hasn't yet sold or explicitly kept.
    private var pendingDuplicates: [CardInstance] {
        result.pulled.filter { baseKind[$0.id] == .duplicate && !soldIds.contains($0.id) && !keptIds.contains($0.id) }
    }
    private var pendingProceeds: Double { pendingDuplicates.reduce(0) { $0 + $1.sellValue } }

    /// The card IDs that count as *owned* for the evolution-line pips right now,
    /// given the decisions made so far on this summary: everything owned before
    /// the pack was opened, plus every pulled card that is staying — a brand-new
    /// keeper, an upgrade of an owned card, or a duplicate the player has kept.
    /// Pending (undecided) and sold duplicates are deliberately excluded, so the
    /// pips reflect what is *now* owned and light up as cards are kept — matching
    /// Gauntlet's Showcase-based pips. Recomputes as `keptIds`/`soldIds` change.
    private var stayingCardIds: Set<String> {
        var ids = result.preOwnedIds
        for inst in result.pulled {
            switch slot(for: inst) {
            case .newCard, .keeperExisting, .keptDup: ids.insert(inst.cardId)
            case .pendingDup, .sold:                  break
            }
        }
        return ids
    }

    var body: some View {
        GeometryReader { geo in
            let metrics = GridMetrics(container: geo.size.width)
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: metrics.sectionSpacing) {
                        Text(result.isBox ? "Booster Box Opened!" : "Pack Summary")
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.top, metrics.titleTopPad)

                        if result.isBox {
                            HStack(spacing: 10) {
                                StatTile(label: "Cards", value: "\(result.pulled.count)")
                                StatTile(label: "Foils", value: "\(foils.count)", tint: Color(hex: "ff8ad6"))
                                StatTile(label: "Ultras", value: "\(ultras.count)", tint: Color(hex: "b06cf7"))
                                StatTile(label: "Value", value: totalValue.moneyShort, tint: Palette.money)
                            }
                        }

                        ForEach(result.bonuses) { bonus in
                            BonusBanner(bonus: bonus)
                        }

                        if result.isBox { boxGrid(metrics) } else { packGrid(metrics) }
                    }
                    .padding(16)
                    .readableWidth(metrics.contentCap)
                }

                if let pc = packCounter { packCounterBar(pc) }

                finishButtons
                    .padding(16)
                    .readableWidth()
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(Palette.bg0.ignoresSafeArea())
        .overlay {
            if let r = gradeResult {
                GradeRevealOverlay(result: r) { gradeResult = nil }
            }
        }
    }

    // MARK: Grids

    private func boxGrid(_ m: GridMetrics) -> some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: m.card), spacing: m.spacing)], spacing: m.spacing) {
                ForEach(boxHighlights) { inst in
                    CardView(card: inst.card, instance: inst, width: m.card,
                             series: CardSeries(for: inst.card, pull: true) { game.owns($0.id) })
                }
            }
            if boxHighlights.count < result.pulled.count {
                Text("+ \(result.pulled.count - boxHighlights.count) more commons & uncommons added to your collection")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.subtle)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 4)
    }

    private func packGrid(_ m: GridMetrics) -> some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: m.columns, spacing: m.spacing) {
                ForEach(result.pulled) { inst in
                    PackCardSlot(inst: displayInstance(inst), slot: slot(for: inst), width: m.card,
                                 series: CardSeries(for: inst.card, pull: true) { stayingCardIds.contains($0.id) },
                                 onKeep: { decideKeep(inst) },
                                 onSell: { decideSell(inst) },
                                 gradeTitle: gradeTitle(for: inst),
                                 gradeEnabled: game.canAffordGrade(set: set),
                                 onGrade: { decideGrade(inst) })
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: Bottom actions

    /// "Pack X of N" progress shown between the card grid and the action buttons
    /// while opening a booster box, so the player can track their way through it.
    private func packCounterBar(_ pc: PackCounter) -> some View {
        return VStack(spacing: 7) {
            Text("Pack \(pc.index + 1) of \(pc.total)")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.stroke)
                    Capsule().fill(.white)
                        .frame(width: max(6, geo.size.width * CGFloat(pc.index + 1) / CGFloat(pc.total)))
                }
            }
            .frame(height: 5)
        }
        .padding(.horizontal, 40)
        .padding(.top, 6)
        .readableWidth()
    }

    private var showSpreadHint: Bool {
        result.isBox ? game.duplicateSummary(from: result).count > 0 : !pendingDuplicates.isEmpty
    }

    private var spreadHint: some View {
        Text("Shop buys extras at \(Int((Economy.sellbackRate * 100).rounded()))% of market value")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Palette.subtle)
            .padding(.top, 2)
    }

    private var finishButtons: some View {
        VStack(spacing: 10) {
            if result.isBox {
                let dup = game.duplicateSummary(from: result)
                if dup.count > 0 {
                    BigButton(title: "Sell \(dup.count) Duplicate\(dup.count == 1 ? "" : "s")",
                              subtitle: "Keep 1 of each · +\(dup.proceeds.moneyShort)",
                              systemImage: "dollarsign.circle.fill", tint: green) {
                        Haptics.play(.success); Sound.play(.coin); game.sellDuplicates(from: result); onDone()
                    }
                    BigButton(title: "Keep All", systemImage: "tray.and.arrow.down.fill", tint: blue) {
                        Haptics.play(.light); onDone()
                    }
                } else {
                    BigButton(title: "Add to Collection", systemImage: "checkmark.circle.fill", tint: blue) {
                        Haptics.play(.light); onDone()
                    }
                }
            } else {
                let pending = pendingDuplicates
                if !pending.isEmpty {
                    BigButton(title: "Sell \(pending.count) Duplicate\(pending.count == 1 ? "" : "s")",
                              subtitle: "Keep 1 of each · +\(pendingProceeds.moneyShort)",
                              systemImage: "dollarsign.circle.fill", tint: green) {
                        sellAllPending()
                    }
                    BigButton(title: "Keep All", systemImage: "tray.and.arrow.down.fill", tint: blue) {
                        Haptics.play(.light); onDone()
                    }
                } else {
                    BigButton(title: "Add to Collection", systemImage: "checkmark.circle.fill", tint: blue) {
                        Haptics.play(.light); onDone()
                    }
                }
            }
            if showSpreadHint { spreadHint }
        }
    }

    // MARK: Classification + live state

    private func slot(for inst: CardInstance) -> PackSlot {
        switch baseKind[inst.id] ?? .duplicate {
        case .newCard:        return .newCard
        case .keeperExisting: return .keeperExisting
        case .duplicate:
            if soldIds.contains(inst.id) { return .sold }
            if keptIds.contains(inst.id) { return .keptDup }
            return .pendingDup
        }
    }

    /// Snapshot which pulled cards are new keepers vs. sellable extras. The
    /// keeper of each card is its most valuable owned copy; ties prefer a
    /// pre-existing (non-pulled) copy so a plain re-pull becomes the dup, while
    /// a foil upgrade of an owned card keeps the pulled foil.
    private func computePlan() -> [UUID: BaseKind] {
        guard !result.isBox else { return [:] }
        let pulledIds = Set(result.pulled.map { $0.id })
        var kinds: [UUID: BaseKind] = [:]
        for inst in result.pulled {
            let keeper = keeperId(forCard: inst.cardId, pulledIds: pulledIds)
            if inst.id == keeper {
                kinds[inst.id] = result.preOwnedIds.contains(inst.cardId) ? .keeperExisting : .newCard
            } else {
                kinds[inst.id] = .duplicate
            }
        }
        return kinds
    }

    private func keeperId(forCard cardId: String, pulledIds: Set<UUID>) -> UUID? {
        var copies = game.instances(of: cardId)
        if let visible = result.visibleInstanceIds {
            copies = copies.filter { visible.contains($0.id) }
        }
        return copies.sorted { a, b in
            if a.currentValue != b.currentValue { return a.currentValue > b.currentValue }
            return !pulledIds.contains(a.id) && pulledIds.contains(b.id)
        }.first?.id
    }

    private func decideSell(_ inst: CardInstance) {
        guard game.sell(inst.id) != nil else {
            withAnimation(.easeOut(duration: 0.2)) { _ = keptIds.insert(inst.id) }
            return
        }
        Haptics.play(.success)
        Sound.play(.coin)
        withAnimation(.easeOut(duration: 0.25)) {
            keptIds.remove(inst.id)
            _ = soldIds.insert(inst.id)
        }
    }

    private func decideKeep(_ inst: CardInstance) {
        Haptics.play(.light)
        withAnimation(.easeOut(duration: 0.2)) { _ = keptIds.insert(inst.id) }
    }

    /// Grade a pulled card right on the summary. The roll (and its fee) run through
    /// the same `game.grade` path as the Collection, then the card is auto-kept — a
    /// freshly slabbed card is a keeper, so its Keep/Sell choice falls away — and the
    /// reveal overlay shows the PSA result. A sold card can't reach here (no tab).
    private func decideGrade(_ inst: CardInstance) {
        guard let r = game.grade(inst.id) else { Haptics.play(.error); return }
        Haptics.play(.rigid)
        var graded = inst
        graded.grade = r.grade
        withAnimation(.easeOut(duration: 0.25)) {
            gradedInstances[inst.id] = graded
            soldIds.remove(inst.id)
            _ = keptIds.insert(inst.id)
        }
        gradeResult = r
    }

    /// The live copy to draw for a pulled card: the graded version once the player
    /// grades it here, otherwise the card as pulled. Keeps the slab and its new
    /// value on screen even though `result.pulled` is an open-time snapshot.
    private func displayInstance(_ inst: CardInstance) -> CardInstance {
        gradedInstances[inst.id] ?? inst
    }

    /// The grade tab's fee label for a card, or nil to hide the tab. The tab lives
    /// only on cards still in play, so it's hidden once a card is graded, sold, or
    /// kept — choosing Keep resolves a duplicate as-is, and grading is the tab's own
    /// (auto-keeping) path. Any rarity can be graded, matching the Collection.
    private func gradeTitle(for inst: CardInstance) -> String? {
        let state = slot(for: inst)
        guard displayInstance(inst).grade == nil, state != .sold, state != .keptDup else { return nil }
        let fee = Economy.gradeFee(set: set)
        return fee == fee.rounded() ? "$\(Int(fee))" : fee.moneyShort
    }

    private func sellAllPending() {
        Haptics.play(.success)
        Sound.play(.coin)
        withAnimation(.easeOut(duration: 0.25)) {
            for inst in pendingDuplicates where game.sell(inst.id) != nil {
                soldIds.insert(inst.id)
            }
        }
        onDone()
    }
}

/// Sizing for the pack-summary card grid.
///
/// A pack is always six cards, so it's laid out as a fixed three columns that
/// stretch to fill whatever width the screen offers. On a phone that's the same
/// ~104pt card as before; on an iPad — where fixed 104pt cards left the whole
/// summary marooned in the top quarter of the screen — the cards grow to their
/// full design size and spread across the width instead.
private struct GridMetrics {
    let contentCap: CGFloat
    let spacing: CGFloat
    let card: CGFloat
    let sectionSpacing: CGFloat
    let titleTopPad: CGFloat

    /// Three across is what a phone already fit, and it keeps a six-card pack to
    /// two tidy rows at every screen size.
    private static let columnCount = 3

    init(container: CGFloat) {
        // Wider than the app's usual reading width: this screen is a grid of
        // pictures, not a column of prose.
        let wide = container >= 700
        contentCap = wide ? 820 : 760
        spacing = wide ? 18 : 12
        sectionSpacing = wide ? 26 : 18
        titleTopPad = wide ? 44 : 28
        let usable = min(container, contentCap) - 32          // .padding(16) on each side
        let perColumn = (usable - CGFloat(Self.columnCount - 1) * spacing) / CGFloat(Self.columnCount)
        card = min(230, max(96, perColumn))                   // 230 is CardView's native size
    }

    var columns: [GridItem] {
        // Top-aligned so cards line up along the top of each row even when a
        // pending duplicate's Keep/Sell buttons make its cell taller.
        Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .top), count: Self.columnCount)
    }
}

/// A single card on the pack summary with its NEW / duplicate / sold state.
/// Pending duplicates carry their own Keep / Sell buttons so the choice is made
/// right on the card, without a follow-up dialog (req 1).
private struct PackCardSlot: View {
    let inst: CardInstance
    let slot: PackSlot
    let width: CGFloat
    var series: CardSeries? = nil
    let onKeep: () -> Void
    let onSell: () -> Void
    /// The grade tab's fee label (e.g. "$2"), or nil to hide it — hidden once the
    /// card is graded or sold. Boxes never pass it (they use the bulk flow).
    var gradeTitle: String? = nil
    /// Whether the player can currently afford to grade; a dimmed tab still shows so
    /// the action stays discoverable, but tapping it does nothing.
    var gradeEnabled: Bool = true
    var onGrade: () -> Void = {}

    @State private var pulse = false

    /// Chrome scales with the card, which is much larger on a tablet than the
    /// 104pt phone card these badges were originally sized against.
    private var s: CGFloat { min(1.7, max(1, width / 104)) }
    private var corner: CGFloat { 16 * (width / 230) }
    /// CardView's own internal scale (its `s`), used to line the grade tab up with
    /// the art window drawn inside the card.
    private var cs: CGFloat { width / 230 }

    /// Kept and sold cards are desaturated so the undecided ones stand out — but a
    /// graded keeper stays vibrant so its fresh PSA slab is shown off, not greyed.
    private var isProcessed: Bool { slot == .sold || (slot == .keptDup && inst.grade == nil) }
    private var cardOpacity: Double {
        switch slot {
        case .sold:    return 0.45
        case .keptDup: return inst.grade == nil ? 0.65 : 1
        default:       return 1
        }
    }

    var body: some View {
        VStack(spacing: 7 * s) {
            cardFace
            // Only an undecided duplicate still needs a choice, so it carries both
            // Keep and Sell right on the card. Once kept it shows no buttons — the
            // copy is safely in the collection and can still be sold later from the
            // Collection tab if the player changes their mind (req).
            if slot == .pendingDup {
                VStack(spacing: 6 * s) {
                    actionButton(title: "Keep", tint: Color(hex: "3b82f6"), action: onKeep)
                    actionButton(title: "Sell \(inst.sellValue.moneyShort)", tint: Palette.money, action: onSell)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: slot)
        .onAppear {
            guard slot == .pendingDup else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    private var cardFace: some View {
        CardView(card: inst.card, instance: inst, width: width, series: series)
            .saturation(isProcessed ? 0 : 1)
            .opacity(cardOpacity)
            .overlay { if slot == .pendingDup { pendingRing } }
            .overlay(alignment: .topLeading) { badgeView }
            .overlay(alignment: .topTrailing) { gradeTabView }
            .overlay { if slot == .sold { soldStamp } }
    }

    private func actionButton(title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12 * s, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6.5 * s)
                .padding(.horizontal, 10 * s)
                .background(Capsule().fill(tint))
                .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    /// Duplicates are the only cards here that still need a decision, so they
    /// get an unmissable cue of their own: a breathing accent ring that draws
    /// the eye down to the Keep / Sell buttons beneath them.
    private var pendingRing: some View {
        RoundedRectangle(cornerRadius: corner)
            .strokeBorder(Palette.tapCue, lineWidth: 2.5 * s)
            .shadow(color: Palette.tapCue.opacity(pulse ? 0.85 : 0.3), radius: 7 * s)
            .opacity(pulse ? 1 : 0.55)
            .allowsHitTesting(false)
    }

    @ViewBuilder private var badgeView: some View {
        if let b = badge {
            Text(b.text)
                .font(.system(size: 9 * s, weight: .black))
                .foregroundStyle(.white)
                .padding(.horizontal, 7 * s).padding(.vertical, 3 * s)
                .background(Capsule().fill(b.color))
                .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.45), radius: 2 * s, y: 1)
                .offset(x: -5 * s, y: -7 * s)
        }
    }

    /// The grade tab (req: 4C) — a single seal-and-fee chip pinned inside the art
    /// window's top-right, tucked just under the header's evolution pips. Grade is
    /// the only corner action; Keep/Sell stay below the card. It disappears once the
    /// card is graded or sold, so a slabbed or sold card offers no second roll.
    @ViewBuilder private var gradeTabView: some View {
        if let title = gradeTitle {
            Button(action: onGrade) {
                HStack(spacing: 3 * s) {
                    Image(systemName: "seal.fill").font(.system(size: 8.5 * s, weight: .black))
                    Text(title).font(.system(size: 9 * s, weight: .black, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 6 * s).padding(.vertical, 3.5 * s)
                .background(Capsule().fill(Color(hex: "6d5cf7").opacity(gradeEnabled ? 0.95 : 0.5)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.4), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.5), radius: 2 * s, y: 1)
            }
            .buttonStyle(.plain)
            .disabled(!gradeEnabled)
            // CardView draws its art window ~35·cs below the card top; the tab drops
            // a touch below that edge and insets from the right so it reads as part
            // of the art, clear of the pips above it.
            .offset(x: -13 * cs, y: 40 * cs)
        }
    }

    private var badge: (text: String, color: Color)? {
        // A graded card carries its PSA slab (drawn by CardView); the NEW/KEPT chip
        // would only crowd it, so it steps aside once a grade lands.
        if inst.grade != nil { return nil }
        switch slot {
        case .newCard:    return ("✦ NEW", Color(hex: "ffd54a"))
        case .keptDup:    return ("KEPT", Color(hex: "5b6b8a"))
        default:          return nil
        }
    }

    private var soldStamp: some View {
        Text("SOLD\n+\(inst.sellValue.money)")
            .multilineTextAlignment(.center)
            .font(.system(size: 13 * s, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 8 * s).padding(.vertical, 6 * s)
            .background(RoundedRectangle(cornerRadius: 8 * s).fill(Palette.money.opacity(0.92)))
            .rotationEffect(.degrees(-11))
            .shadow(color: .black.opacity(0.4), radius: 3 * s, y: 1)
    }
}

// MARK: - Bits

struct BonusBanner: View {
    let bonus: BonusEvent
    var body: some View {
        HStack(spacing: 10) {
            Text(bonus.kind == .set ? "🏆" : "🧬").font(.system(size: 20))
            Text(bonus.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
            Spacer(minLength: 4)
            Text("+\(bonus.amount.money)")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.money)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Palette.money.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.money.opacity(0.4), lineWidth: 1))
    }
}

/// The transient "Evolution Complete!" toast that drops in on the card that
/// finishes a line mid-reveal. Deliberately louder than `BonusBanner` (a floating
/// card with a glow) since it's on screen only for a beat.
struct EvolutionPopupBanner: View {
    let bonus: BonusEvent

    /// The line names without the "Evolution complete: " prefix baked into `title`.
    private var lineNames: String {
        bonus.title.replacingOccurrences(of: "Evolution complete: ", with: "")
    }

    var body: some View {
        HStack(spacing: 11) {
            Text("🧬").font(.system(size: 24))
            VStack(alignment: .leading, spacing: 2) {
                Text("Evolution Complete!")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text(lineNames)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 6)
            Text("+\(bonus.amount.money)")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.money)
        }
        .padding(.horizontal, 15).padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Palette.bg1.opacity(0.97))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Palette.money.opacity(0.6), lineWidth: 1.5)
        )
        .shadow(color: Palette.money.opacity(0.35), radius: 14, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Evolution complete. \(lineNames). Bonus \(bonus.amount.money)")
    }
}

/// Rotating light rays behind rare pulls.
struct GlowBurst: View {
    var color: Color
    /// Overall diameter. Scaled from the card it sits behind so the effect can
    /// never be wider than the screen it's drawn on.
    var diameter: CGFloat = 440
    var body: some View {
        TimelineView(.animation) { tl in
            let angle = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 12) / 12
            ZStack {
                Circle()
                    .fill(RadialGradient(gradient: Gradient(colors: [color.opacity(0.5), .clear]),
                                         center: .center,
                                         startRadius: diameter / 44, endRadius: diameter / 2))
                    .frame(width: diameter, height: diameter)
                AngularGradient(
                    gradient: Gradient(stops: raysStops()),
                    center: .center,
                    angle: .degrees(angle * 360)
                )
                .frame(width: diameter * 0.955, height: diameter * 0.955)
                .mask(Circle())
                .opacity(0.18)
                .blendMode(.plusLighter)
            }
        }
    }

    private func raysStops() -> [Gradient.Stop] {
        var stops: [Gradient.Stop] = []
        let n = 12
        for i in 0..<n {
            let l = Double(i) / Double(n)
            let r = Double(i) + 0.5
            stops.append(.init(color: .clear, location: l))
            stops.append(.init(color: color, location: r / Double(n)))
        }
        stops.append(.init(color: .clear, location: 1))
        return stops
    }
}

/// Sealed pack / box graphic.
struct PackArtwork: View {
    let set: Int
    var isBox: Bool
    /// 0 = sealed. Drives the wrapper's crimp tearing off / the box splitting.
    var tearTop: Double = 0
    /// 0 = intact. Drives the body falling out of frame after the crimp goes.
    var dropBody: Double = 0

    var body: some View {
        Group {
            if isBox {
                BoosterBoxArt(set: set, width: 296)
                    .scaleEffect(1 - 0.06 * dropBody)
                    .offset(y: 30 * dropBody - 26 * tearTop)
                    .opacity(1 - dropBody)
            } else {
                PackWrapper(set: set, width: 218, detail: .full,
                            animatedSheen: true, tearTop: tearTop, dropBody: dropBody)
            }
        }
    }
}
