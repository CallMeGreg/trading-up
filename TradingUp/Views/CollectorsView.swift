import SwiftUI

struct CollectorsView: View {
    @Environment(GameState.self) private var game: GameState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var isSelected = true

    @State private var set = 1
    @State private var hasChosenSet = false
    @State private var tradeTargets: [Int: String] = [:]
    @State private var sheet: CollectorSheet?
    @State private var errorMessage: String?

    private enum CollectorSheet: Identifiable {
        case targets(Int)
        case review(CollectorPreview)
        case unlock

        var id: String {
            switch self {
            case .targets(let set): return "targets-\(set)"
            case .review(let preview): return "review-\(preview.id)"
            case .unlock: return "unlock"
            }
        }
    }

    private var availableSets: [Int] {
        (1...game.collectorSetLimit).filter { game.isSetUnlocked($0) }
    }

    private var readyCountsBySet: [Int: Int] {
        availableSets.reduce(into: [:]) { counts, choice in
            counts[choice] = game.collectorReadyCount(inSet: choice)
        }
    }

    private var selectedTrade: CollectorPreview? {
        if let id = tradeTargets[set], let preview = game.collectorPreview(for: .trade(id)) {
            return preview
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        setPicker.id("collectorBoardTop")
                        cashRequests
                        trader
                    }
                    .padding(16)
                    .readableWidth()
                }
                .accessibilityIdentifier("collectorBoard")
                .onChange(of: set) { _, _ in
                    scroll.scrollTo("collectorBoardTop", anchor: .top)
                }
            }
            .background(Palette.screen.ignoresSafeArea())
            .navigationTitle("Collectors")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Text(game.cash.money)
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(Palette.money)
                        .accessibilityLabel("Cash \(game.cash.money)")
                        .accessibilityIdentifier("collectorCash")
                }
            }
            .sheet(item: $sheet, onDismiss: {
                // Review and receipt share one sheet. A final-card win may only
                // present after that sheet has completely left the screen.
                game.endCollectorReceipt()
            }) { destination in
                switch destination {
                case .targets(let targetSet):
                    CollectorTargetPicker(set: targetSet) { card in
                        tradeTargets[targetSet] = card.id
                        sheet = nil
                    }
                case .review(let preview):
                    CollectorExchangeSheet(preview: preview)
                case .unlock:
                    PaywallView()
                }
            }
            .alert("Couldn't review this offer", isPresented: errorPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .onChange(of: availableSets) { _, choices in
                if !choices.contains(set) {
                    set = choices.first ?? 1
                    hasChosenSet = false
                    focusRelevantSet()
                }
            }
        }
        .onAppear { if isSelected { focusRelevantSet() } }
        .onChange(of: isSelected) { _, selected in
            if selected { focusRelevantSet() }
        }
        .onChange(of: game.shouldShowWelcome) { _, showing in
            if showing {
                set = 1
                hasChosenSet = false
                tradeTargets.removeAll()
            }
        }
    }

    private var setPicker: some View {
        let counts = readyCountsBySet
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(1...CardDatabase.setCount, id: \.self) { choice in
                    setButton(choice, ready: counts[choice, default: 0])
                }
            }
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout())
            layout {
                Text(CardDatabase.setName(set))
                    .font(.headline)
                    .foregroundStyle(Palette.text)
                    .accessibilityIdentifier("collectorSelectedSet")
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 4) }
                if counts[set, default: 0] > 0 {
                    Text("\(counts[set, default: 0]) ready")
                        .font(.caption.bold())
                        .foregroundStyle(Palette.money)
                }
            }
        }
    }

    private func setButton(_ choice: Int, ready: Int) -> some View {
        let unlocked = game.isSetUnlocked(choice)
        let paid = game.requiresFullUnlock(set: choice)
        let playable = unlocked && !paid
        let tint = Element.theme(forSet: choice).badgeTint
        return Button {
            if paid {
                Sound.play(.panelOpen)
                sheet = .unlock
            } else {
                selectSet(choice)
            }
        } label: {
            VStack(spacing: 6) {
                PackWrapper(set: choice, width: 50, detail: .mini)
                    .saturation(playable ? 1 : 0)
                    .opacity(playable ? 1 : 0.35)
                    .overlay {
                        if !playable {
                            Image(systemName: "lock.fill")
                                .font(.subheadline.bold())
                                .foregroundStyle(Palette.subtle)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if ready > 0 {
                            Text("\(ready)")
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(Palette.bg0)
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(Palette.money))
                                .offset(x: 3, y: -3)
                        }
                    }
                Text("\(choice)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(playable ? tint : Palette.subtle)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12).fill(set == choice ? tint.opacity(0.12) : .clear))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(set == choice ? tint : .clear, lineWidth: 2))
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
        .accessibilityLabel("Set \(choice), \(CardDatabase.setName(choice))")
        .accessibilityValue(!unlocked ? "Locked, \(game.uniquesToUnlock(set: choice)) unique cards needed"
                            : paid ? "Full unlock required" : "\(ready) offers ready")
        .accessibilityHint(!unlocked ? "Collect more unique cards to unlock this set."
                           : paid ? "Opens the full-collection unlock." : "Shows this set's collector offers.")
        .accessibilityAddTraits(set == choice ? .isSelected : [])
        .accessibilityIdentifier("collectorSet-\(choice)")
    }

    private var cashRequests: some View {
        VStack(spacing: 12) {
            ForEach([Collector.mira, .rowan], id: \.self) { collector in
                if let deal = game.collectorRequests(inSet: set).first(where: { $0.collector == collector }),
                   let preview = game.collectorPreview(for: deal.goal) {
                    offer(preview)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        CollectorIdentity(collector: collector, compact: true)
                        Label("All \(CollectorEconomy.requestsPerCollector) requests complete", systemImage: "checkmark.seal.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(Palette.money)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panel(12)
                }
            }
        }
    }

    @ViewBuilder private var trader: some View {
        if let preview = selectedTrade {
            offer(preview, onChooseTarget: chooseTarget)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                CollectorIdentity(collector: .tess, compact: true)
                Text("\(game.collectorTradesRemaining(inSet: set)) of \(CollectorEconomy.tradesPerSet) trades left in this set")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Collector.tess.tint)
                    .accessibilityIdentifier("collectorTradesRemaining")
                if game.collectorTradesRemaining(inSet: set) == 0 {
                    Label("All \(CollectorEconomy.tradesPerSet) trades used in this set", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(Palette.money)
                        .accessibilityIdentifier("collectorTradesExhausted")
                } else if game.collectorTradeTargets(inSet: set).isEmpty {
                    Label("You own every card in this set", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(Palette.money)
                        .accessibilityIdentifier("collectorSetComplete")
                } else {
                    CollectorAction(title: "Choose a missing card", symbol: "rectangle.on.rectangle", tint: Collector.tess.tint,
                                    action: chooseTarget)
                        .accessibilityIdentifier("collectorChooseTarget")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel(12)
            .overlay(alignment: .top) {
                CollectorAccent(tint: Collector.tess.tint)
            }
        }
    }

    private func offer(_ preview: CollectorPreview, onChooseTarget: (() -> Void)? = nil) -> some View {
        CollectorOfferCard(
            preview: preview,
            onReview: { review(preview.deal.goal) },
            onChooseTarget: onChooseTarget
        )
    }

    private func chooseTarget() {
        Haptics.play(.light)
        Sound.play(.panelOpen)
        sheet = .targets(set)
    }

    private func selectSet(_ choice: Int) {
        set = choice
        hasChosenSet = true
        Haptics.play(.light)
        Sound.play(.uiTap)
    }

    private func focusRelevantSet() {
        guard !hasChosenSet, sheet == nil, !game.revealInFlight, !game.collectorReceiptInFlight else { return }
        let choices = availableSets
        let counts = readyCountsBySet
        if counts[set, default: 0] > 0 { return }
        if let readySet = choices.reversed().first(where: { counts[$0, default: 0] > 0 }) {
            set = readySet
        } else if !hasOffers(in: set), let next = choices.reversed().first(where: hasOffers) {
            set = next
        }
    }

    private func hasOffers(in choice: Int) -> Bool {
        !game.collectorRequests(inSet: choice).isEmpty || !game.collectorTradeTargets(inSet: choice).isEmpty
    }

    private func review(_ goal: CollectorGoal) {
        guard let preview = game.collectorPreview(for: goal) else {
            report(CollectorError.unavailable)
            return
        }
        guard !game.requiresFullUnlock(set: preview.deal.set) else {
            report(CollectorError.lockedSet)
            return
        }
        guard preview.isReady else {
            report(CollectorError.missingCopies)
            return
        }
        Haptics.play(.light)
        Sound.play(.panelOpen)
        sheet = .review(preview)
    }

    private func report(_ error: Error) {
        Haptics.play(.error)
        Sound.play(.blocked)
        errorMessage = error.localizedDescription
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}

private struct CollectorOfferCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let preview: CollectorPreview
    let onReview: () -> Void
    var onChooseTarget: (() -> Void)?

    private var deal: CollectorDeal { preview.deal }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 10))
        return VStack(alignment: .leading, spacing: 10) {
            layout {
                CollectorIdentity(collector: deal.collector, compact: true,
                                  subtitle: "\(deal.rewardCard == nil ? "Request" : "Trade") \(deal.sequence) of \(deal.total)")
                if deal.rewardCard == nil {
                    if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 4) }
                    Text(deal.cashReward.money + " cash")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(Palette.money)
                }
            }
            if deal.rewardCard == nil {
                Text(deal.title)
                    .font(.subheadline.bold())
                    .foregroundStyle(Palette.text)
            } else {
                CollectorReward(deal: deal)
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(preview.requirements) { progress in
                    CollectorRequirementRow(progress: progress)
                        .accessibilityIdentifier("collectorRequirement-\(deal.id)-\(progress.id)")
                }
                Text(preview.isReady ? "\(deal.requiredCount) spares ready"
                     : "\(preview.missingCount) more spare\(preview.missingCount == 1 ? "" : "s") needed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(preview.isReady ? Palette.money : Palette.subtle)
                    .accessibilityIdentifier("collectorOfferProgress-\(deal.id)")
            }

            layout {
                if preview.isReady {
                    CollectorAction(title: "Review exchange", symbol: "arrow.left.arrow.right",
                                    tint: deal.collector.tint, prominent: true, action: onReview)
                        .accessibilityLabel("Review \(deal.title) with \(deal.collector.name)")
                        .accessibilityIdentifier("collectorReview-\(deal.id)")
                }
                if let onChooseTarget {
                    CollectorAction(title: "Change card", symbol: "rectangle.on.rectangle",
                                    tint: deal.collector.tint, action: onChooseTarget)
                        .accessibilityIdentifier("collectorChooseTarget")
                }
            }
        }
        .panel(12)
        .overlay(alignment: .top) {
            CollectorAccent(tint: deal.collector.tint)
        }
    }
}

private struct CollectorAccent: View {
    let tint: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(tint.opacity(0.75))
            .frame(width: 42, height: 3)
            .padding(.top, 1)
            .accessibilityHidden(true)
    }
}

private struct CollectorRequirementRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let progress: CollectorRequirementProgress

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 10))
        layout {
            HStack(spacing: 10) {
                if let card = progress.requirement.card {
                    CardView(card: card, width: 28, pipsGlow: false)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "rectangle.stack.fill")
                        .font(.subheadline)
                        .foregroundStyle(progress.requirement.rarity?.accent ?? Palette.subtle)
                        .frame(minWidth: 28, minHeight: 28)
                        .accessibilityHidden(true)
                }
                Text(progress.requirement.label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 4) }
            HStack(spacing: 4) {
                if progress.isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .accessibilityHidden(true)
                }
                Text("\(progress.count)/\(progress.requirement.count)")
                    .monospacedDigit()
            }
            .font(.subheadline.bold())
            .foregroundStyle(progress.isComplete ? Palette.money : Palette.subtle)
            .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(progress.requirement.label), \(progress.count) of \(progress.requirement.count) normal spares available")
    }
}

private struct CollectorTargetPicker: View {
    @Environment(GameState.self) private var game: GameState
    @Environment(\.dismiss) private var dismiss
    let set: Int
    let onChoose: (Card) -> Void
    @State private var search = ""
    @State private var rarity: Rarity?

    private var targets: [Card] {
        game.collectorTradeTargets(inSet: set).filter {
            (rarity == nil || $0.rarity == rarity)
                && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    Text("Choose your missing piece")
                        .font(.title2.bold())
                        .foregroundStyle(Palette.text)
                    let remaining = game.collectorTradesRemaining(inSet: set)
                    Text("\(remaining) trade\(remaining == 1 ? "" : "s") left in \(CardDatabase.setName(set)). You'll review the exact spares before exchanging anything.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.subtle)
                    Picker("Rarity", selection: $rarity) {
                        Text("All rarities").tag(Rarity?.none)
                        ForEach(Rarity.allCases, id: \.self) { choice in
                            Text(choice.display).tag(Optional(choice))
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Collector.tess.tint)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("collectorTargetRarity")
                    ForEach(targets) { card in
                        if let preview = game.collectorPreview(for: .trade(card.id)) {
                            targetRow(card, preview: preview)
                        }
                    }
                    if targets.isEmpty {
                        ContentUnavailableView("No missing cards match", systemImage: "magnifyingglass",
                                               description: Text("Try another rarity or clear your search."))
                    }
                }
                .padding(16)
                .readableWidth()
            }
            .accessibilityIdentifier("collectorTargetList")
            .background(Palette.screen.ignoresSafeArea())
            .navigationTitle("Trade with \(Collector.tess.name)")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Find a missing card")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { Sound.play(.uiBack); dismiss() }
                        .accessibilityIdentifier("collectorTargetCancel")
                }
            }
        }
    }

    private func targetRow(_ card: Card, preview: CollectorPreview) -> some View {
        Button {
            Haptics.play(.light)
            Sound.play(.uiTap)
            onChoose(card)
        } label: {
            HStack(spacing: 14) {
                CardView(card: card, width: 66, pipsGlow: false)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(card.name)
                        .font(.headline)
                        .foregroundStyle(Palette.text)
                    Text("\(card.rarity.display) · #\(pad3(card.number))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(card.rarity.accent)
                    Text("Give: " + preview.requirements.map(\.requirement.label).joined(separator: " + "))
                        .font(.caption)
                        .foregroundStyle(Palette.subtle)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(preview.isReady ? "Ready to review" : "\(preview.collectedCount)/\(preview.deal.requiredCount) spares available")
                        .font(.caption.bold())
                        .foregroundStyle(preview.isReady ? Palette.money : Collector.tess.tint)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(Collector.tess.tint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel(12, corner: 14)
            .accessibilityElement(children: .ignore)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Choose \(card.name), \(card.rarity.display). Give \(preview.requirements.map(\.requirement.label).joined(separator: ", ")). \(preview.collectedCount) of \(preview.deal.requiredCount) spares available.")
        .accessibilityHint("Selects your target. No cards are exchanged yet.")
        .accessibilityIdentifier("collectorTarget-\(card.id)")
    }
}

private struct CollectorExchangeSheet: View {
    @Environment(GameState.self) private var game: GameState
    @Environment(\.dismiss) private var dismiss
    let preview: CollectorPreview
    @State private var receipt: CollectorReceipt?
    @State private var completing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let receipt {
                    receiptContent(receipt)
                } else {
                    reviewContent
                }
            }
            .background(Palette.screen.ignoresSafeArea())
            .navigationTitle(receipt == nil ? "Review exchange" : "Deal complete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(receipt == nil ? "Cancel" : "Done") {
                        Sound.play(.uiBack)
                        dismiss()
                    }
                    .accessibilityIdentifier(receipt == nil ? "collectorReviewCancel" : "collectorReceiptClose")
                }
            }
            .safeAreaInset(edge: .bottom) {
                Group {
                    if receipt == nil {
                        CollectorAction(title: "Confirm exchange", symbol: "arrow.left.arrow.right",
                                        tint: preview.deal.collector.tint, prominent: true, action: complete)
                            .disabled(completing)
                            .accessibilityHint("Exchanges only the exact spare copies shown in this review.")
                            .accessibilityIdentifier("collectorConfirm")
                    } else {
                        CollectorAction(title: game.shouldShowWin ? "Celebrate your collection" : "Back to Collectors",
                                        symbol: "checkmark", tint: Palette.money, prominent: true) {
                            Sound.play(.uiBack)
                            dismiss()
                        }
                        .accessibilityHint("Closes your receipt.")
                        .accessibilityIdentifier("collectorReceiptDone")
                    }
                }
                .padding(16)
                .readableWidth()
                .background(Palette.bg1)
            }
            .alert("Couldn't complete this exchange", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) {
                Button("Back to Collectors") { dismiss() }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var reviewContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                CollectorIdentity(collector: preview.deal.collector)
                Text(preview.deal.title)
                    .font(.title2.bold())
                    .foregroundStyle(Palette.text)
                VStack(alignment: .leading, spacing: 12) {
                    CollectorSectionLabel(title: "You give · \(preview.supplied.count) exact copies", symbol: "arrow.up.right")
                    CollectorSuppliedCopies(instances: preview.supplied)
                }
                .panel()
                CollectorReward(deal: preview.deal)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panel()
                CollectorSafetyNote()
                Text("Nothing changes until you confirm.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.subtle)
            }
            .padding(16)
            .readableWidth()
        }
        .accessibilityIdentifier("collectorReviewSheet")
    }

    private func receiptContent(_ receipt: CollectorReceipt) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.largeTitle)
                        .foregroundStyle(Palette.money)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(receipt.received == nil ? "Request complete!" : "It's in your collection!")
                            .font(.title2.bold())
                            .foregroundStyle(Palette.text)
                        Text("Thanks from \(receipt.deal.collector.name)")
                            .font(.subheadline)
                            .foregroundStyle(receipt.deal.collector.tint)
                    }
                }
                if let received = receipt.received {
                    VStack(spacing: 12) {
                        CardView(card: received.card, instance: received, width: 156,
                                 series: CardSeries(for: received.card, pull: false) { game.owns($0.id) },
                                 pipsGlow: false)
                            .accessibilityHidden(true)
                        Text(received.card.name)
                            .font(.title3.bold())
                            .foregroundStyle(Palette.text)
                            .accessibilityIdentifier("collectorReceived-\(received.cardId)")
                    }
                    .frame(maxWidth: .infinity)
                    .panel()
                } else {
                    Text("+\(receipt.deal.cashReward.money)")
                        .font(.largeTitle.bold().monospacedDigit())
                        .foregroundStyle(Palette.money)
                        .accessibilityLabel("\(receipt.deal.cashReward.money) cash received")
                        .accessibilityIdentifier("collectorCashReceived")
                }
                if !receipt.bonuses.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        CollectorSectionLabel(title: "Bonuses earned", symbol: "gift.fill")
                        ForEach(receipt.bonuses) { bonus in
                            BonusBanner(bonus: bonus)
                        }
                    }
                    .accessibilityIdentifier("collectorReceiptBonuses")
                }
                Text(nextStep(receipt))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .readableWidth()
        }
        .accessibilityIdentifier("collectorReceipt")
    }

    private func nextStep(_ receipt: CollectorReceipt) -> String {
        if receipt.received != nil {
            let left = game.collectorTradesRemaining(inSet: receipt.deal.set)
            return left == 0 ? "You've used all of \(receipt.deal.collector.name)'s trades in this set."
                : "\(left) trade\(left == 1 ? "" : "s") left with \(receipt.deal.collector.name) in \(CardDatabase.setName(receipt.deal.set))."
        }
        return receipt.deal.sequence < receipt.deal.total
            ? "\(receipt.deal.collector.name)'s next request is waiting on the board."
            : "You've completed all of \(receipt.deal.collector.name)'s requests for this set."
    }

    private func complete() {
        guard receipt == nil, !completing else { return }
        completing = true
        do {
            receipt = try game.completeCollectorDeal(preview.deal.goal, expectedInstanceIDs: preview.suppliedIDs)
            Haptics.play(.success)
            Sound.play(preview.deal.rewardCard == nil ? .coin : .newCard)
        } catch {
            completing = false
            Haptics.play(.error)
            Sound.play(.blocked)
            errorMessage = error.localizedDescription
        }
    }
}

private struct CollectorSuppliedCopies: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let instances: [CardInstance]

    private var cardIDs: [String] { Set(instances.map(\.cardId)).sorted() }

    var body: some View {
        VStack(spacing: 12) {
            ForEach(cardIDs, id: \.self) { cardID in
                let copies = instances.filter { $0.cardId == cardID }
                if let copy = copies.first {
                    HStack(spacing: 12) {
                        if !dynamicTypeSize.isAccessibilitySize {
                            CardView(card: copy.card, instance: copy, width: 48, pipsGlow: false)
                                .accessibilityHidden(true)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(copy.card.name)
                                .font(.headline)
                                .foregroundStyle(Palette.text)
                            Text(dynamicTypeSize.isAccessibilitySize
                                 ? "\(copies.count) normal, ungraded \(copies.count == 1 ? "copy" : "copies") · #\(pad3(copy.card.number))"
                                 : "Normal · Ungraded · #\(pad3(copy.card.number))")
                                .font(.caption)
                                .foregroundStyle(Palette.subtle)
                        }
                        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil, alignment: .leading)
                        if !dynamicTypeSize.isAccessibilitySize {
                            Spacer(minLength: 0)
                            Text("×\(copies.count)")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(Palette.text)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(copies.count) \(copy.card.name), normal ungraded spare \(copies.count == 1 ? "copy" : "copies")")
                    .accessibilityIdentifier("collectorSupplied-\(copy.cardId)")
                }
            }
        }
    }
}

private struct CollectorReward: View {
    let deal: CollectorDeal

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            CollectorSectionLabel(title: "You get", symbol: "arrow.down.left")
            if let card = deal.rewardCard {
                HStack(spacing: 12) {
                    CardView(card: card, width: 54, pipsGlow: false)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(card.name)
                            .font(.headline)
                            .foregroundStyle(Palette.text)
                        Text("\(card.rarity.display) · Normal · Ungraded")
                            .font(.caption)
                            .foregroundStyle(card.rarity.accent)
                        Text("One missing card, guaranteed")
                            .font(.caption)
                            .foregroundStyle(Palette.subtle)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("collectorReward-\(card.id)")
            } else {
                Text(deal.cashReward.money + " cash")
                    .font(.title2.bold().monospacedDigit())
                    .foregroundStyle(Palette.money)
            }
        }
    }
}

private struct CollectorIdentity: View {
    let collector: Collector
    var compact = false
    var subtitle: String? = nil

    var body: some View {
        HStack(spacing: compact ? 8 : 12) {
            Image(systemName: collector.symbol)
                .font(.system(size: compact ? 16 : 20, weight: .bold))
                .foregroundStyle(collector.tint)
                .frame(width: compact ? 36 : 46, height: compact ? 36 : 46)
                .background(Circle().fill(collector.tint.opacity(0.14)))
                .overlay(Circle().strokeBorder(collector.tint.opacity(0.35), lineWidth: 1))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(collector.name)
                    .font(.headline)
                    .foregroundStyle(Palette.text)
                Text(subtitle ?? collector.specialty)
                    .font(.caption)
                    .foregroundStyle(Palette.subtle)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct CollectorSectionLabel: View {
    let title: String
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.subheadline.bold())
            .foregroundStyle(Palette.text)
    }
}

private struct CollectorSafetyNote: View {
    var body: some View {
        Label {
            Text("Only normal, ungraded spares are exchanged. Your last copy, best copy, foils, and graded cards stay safe.")
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "checkmark.shield.fill")
        }
        .font(.caption)
        .foregroundStyle(Palette.subtle)
        .accessibilityIdentifier("collectorSafety")
    }
}

private struct CollectorAction: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let symbol: String
    let tint: Color
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    Text(title).multilineTextAlignment(.center)
                } else {
                    Label(title, systemImage: symbol)
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .foregroundStyle(prominent ? Palette.bg0 : tint)
            .background(RoundedRectangle(cornerRadius: 13).fill(prominent ? tint : tint.opacity(0.1)))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(tint.opacity(prominent ? 0 : 0.35)))
        }
        .buttonStyle(.plain)
    }
}

private extension Collector {
    var tint: Color {
        switch self {
        case .mira: return Element.grass.badgeTint
        case .rowan: return Element.fire.badgeTint
        case .tess: return Element.shadow.badgeTint
        }
    }

    var symbol: String {
        switch self {
        case .mira: return "books.vertical.fill"
        case .rowan: return "leaf.fill"
        case .tess: return "arrow.left.arrow.right"
        }
    }
}
