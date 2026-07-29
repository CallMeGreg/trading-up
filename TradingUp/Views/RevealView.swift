import SwiftUI

/// Dramatic pack / box opening. Packs reveal one card at a time with a tap.
/// A booster box reveals each of its packs in turn — the same card-by-card
/// flip and keep/sell summary as a single pack — advancing automatically to
/// the next pack once its cards are kept or sold, with a "Pack X of N" counter.
struct RevealView: View {
    let content: RevealContent
    let set: Int
    let onDone: () -> Void

    @State private var phase: Phase = .sealed
    @State private var packIndex = 0
    /// The pack currently being revealed. For a box, the next pack's result.
    @State private var current: OpenResult? = nil

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
    }

    // MARK: Sealed

    private var sealedView: some View {
        SealedPackView(set: set, isBox: isBox) { startPack(0) }
    }

    // MARK: Revealing

    private func revealingView(_ result: OpenResult, _ i: Int) -> some View {
        let inst = result.pulled[i]
        let isNew = !result.preOwnedIds.contains(inst.cardId)
        return VStack(spacing: 20) {
            if isBox {
                Text("Pack \(packIndex + 1) of \(packCount)")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.subtle)
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

            RevealingCardView(inst: inst, isNew: isNew, width: 280)
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

    /// One-time classification of each pulled instance, snapshotted on appear
    /// (before any selling) so keeper decisions don't shift as dupes are sold.
    private enum BaseKind { case newCard, keeperExisting, duplicate }
    @State private var baseKind: [UUID: BaseKind] = [:]
    @State private var soldIds: Set<UUID> = []
    @State private var keptIds: Set<UUID> = []
    @State private var actionInst: CardInstance? = nil

    private let blue = [Color(hex: "3b82f6"), Color(hex: "6d5cf7")]
    private let green = [Palette.money, Color(hex: "2fae63")]

    private var totalValue: Double { result.pulled.reduce(0) { $0 + $1.currentValue } }
    private var foils: [CardInstance] { result.pulled.filter { $0.foil } }
    private var ultras: [CardInstance] { result.pulled.filter { $0.card.rarity == .ultra } }

    /// Distinct cards in this pull that weren't already in the collection.
    private var newCount: Int {
        Set(result.pulled.map { $0.cardId }).subtracting(result.preOwnedIds).count
    }

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

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 18) {
                    Text(result.isBox ? "Booster Box Opened!" : "Pack Opened!")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.top, 28)

                    HStack(spacing: 10) {
                        StatTile(label: "Cards", value: "\(result.pulled.count)")
                        if result.isBox {
                            StatTile(label: "Foils", value: "\(foils.count)", tint: Color(hex: "ff8ad6"))
                            StatTile(label: "Ultras", value: "\(ultras.count)", tint: Color(hex: "b06cf7"))
                        } else {
                            StatTile(label: "New", value: "\(newCount)", tint: Color(hex: "ffd54a"))
                            StatTile(label: "Foils", value: "\(foils.count)", tint: Color(hex: "ff8ad6"))
                        }
                        StatTile(label: "Value", value: totalValue.moneyShort, tint: Palette.money)
                    }

                    ForEach(result.bonuses) { bonus in
                        BonusBanner(bonus: bonus)
                    }

                    if result.isBox { boxGrid } else { packGrid }
                }
                .padding(16)
            }

            if let pc = packCounter { packCounterBar(pc) }

            finishButtons
                .padding(16)
        }
        .background(Palette.bg0.ignoresSafeArea())
        .onAppear(perform: computePlan)
        .confirmationDialog(
            Text(actionInst.map { "Extra copy of \($0.card.name)" } ?? "Duplicate"),
            isPresented: Binding(get: { actionInst != nil }, set: { if !$0 { actionInst = nil } }),
            titleVisibility: .visible,
            presenting: actionInst
        ) { inst in
            Button("Sell for \(inst.sellValue.money)") { decideSell(inst) }
            Button("Keep in collection") { decideKeep(inst) }
            Button("Cancel", role: .cancel) { }
        } message: { _ in
            Text("You already have a copy. The shop pays \(Int((Economy.sellbackRate * 100).rounded()))% of market value for extras — sell it for cash, or keep it in your collection.")
        }
    }

    // MARK: Grids

    private var boxGrid: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12)], spacing: 12) {
                ForEach(boxHighlights) { inst in
                    CardView(card: inst.card, instance: inst, width: 104)
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

    private var packGrid: some View {
        VStack(spacing: 10) {
            if !pendingDuplicates.isEmpty {
                Text("Tap a duplicate to keep or sell it")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.subtle)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12)], spacing: 12) {
                ForEach(result.pulled) { inst in
                    PackCardSlot(inst: inst, slot: slot(for: inst), width: 104) {
                        actionInst = inst
                    }
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
    private func computePlan() {
        guard baseKind.isEmpty, !result.isBox else { return }
        let pulledIds = Set(result.pulled.map { $0.id })
        var plan: [UUID: BaseKind] = [:]
        for inst in result.pulled {
            let keeper = keeperId(forCard: inst.cardId, pulledIds: pulledIds)
            if inst.id == keeper {
                plan[inst.id] = result.preOwnedIds.contains(inst.cardId) ? .keeperExisting : .newCard
            } else {
                plan[inst.id] = .duplicate
            }
        }
        baseKind = plan
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

/// A single card on the pack summary with its NEW / duplicate / sold state.
private struct PackCardSlot: View {
    let inst: CardInstance
    let slot: PackSlot
    let width: CGFloat
    let onTap: () -> Void

    private var tappable: Bool { slot == .pendingDup || slot == .keptDup }

    /// Kept and sold cards are "processed" — desaturated so it's clear which
    /// cards still need a decision. Sold fades more and carries a stamp.
    private var isProcessed: Bool { slot == .sold || slot == .keptDup }
    private var cardOpacity: Double {
        switch slot {
        case .sold:    return 0.45
        case .keptDup: return 0.65
        default:       return 1
        }
    }

    var body: some View {
        CardView(card: inst.card, instance: inst, width: width)
            .saturation(isProcessed ? 0 : 1)
            .opacity(cardOpacity)
            .overlay(alignment: .topTrailing) { badgeView }
            .overlay { if slot == .sold { soldStamp } }
            .contentShape(Rectangle())
            .onTapGesture { if tappable { Haptics.play(.light); onTap() } }
            .animation(.easeInOut(duration: 0.2), value: slot)
    }

    @ViewBuilder private var badgeView: some View {
        if let b = badge {
            Text(b.text)
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(.white)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Capsule().fill(b.color))
                .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                .offset(x: 5, y: -7)
        }
    }

    private var badge: (text: String, color: Color)? {
        switch slot {
        case .newCard: return ("✦ NEW", Color(hex: "ffd54a"))
        default:       return nil
        }
    }

    private var soldStamp: some View {
        Text("SOLD\n+\(inst.sellValue.money)")
            .multilineTextAlignment(.center)
            .font(.system(size: 13, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Palette.money.opacity(0.92)))
            .rotationEffect(.degrees(-11))
            .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
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

/// Rotating light rays behind rare pulls.
struct GlowBurst: View {
    var color: Color
    var body: some View {
        TimelineView(.animation) { tl in
            let angle = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 12) / 12
            ZStack {
                Circle()
                    .fill(RadialGradient(gradient: Gradient(colors: [color.opacity(0.5), .clear]),
                                         center: .center, startRadius: 10, endRadius: 220))
                    .frame(width: 440, height: 440)
                AngularGradient(
                    gradient: Gradient(stops: raysStops()),
                    center: .center,
                    angle: .degrees(angle * 360)
                )
                .frame(width: 420, height: 420)
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
    private var element: Element { Element.theme(forSet: set) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(LinearGradient(colors: [element.palette[1], element.palette[3]],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 18)
                .fill(LinearGradient(colors: [.clear, .white.opacity(0.7), .clear],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .blendMode(.plusLighter)
                .opacity(0.25)
            VStack(spacing: 10) {
                Text("TRADING UP")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .tracking(2)
                Text(element.emoji).font(.system(size: 64))
                Text(CardDatabase.setName(set).uppercased())
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.95))
                    .tracking(1)
                Text(isBox ? "BOOSTER BOX" : "BOOSTER PACK")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(20)
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(.white.opacity(0.25), lineWidth: 1.5)
        }
        .frame(width: isBox ? 230 : 190, height: isBox ? 240 : 300)
        .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
    }
}
