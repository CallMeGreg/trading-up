import SwiftUI

struct CollectorsView: View {
    @Environment(GameState.self) private var game: GameState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var isSelected = true
    var onShop: () -> Void

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
        let tracked = game.collectorTrackedPreviews
        return availableSets.reduce(into: [:]) { counts, choice in
            let goals = Set(game.collectorRequests(inSet: choice).map(\.goal)
                            + tracked.filter { $0.deal.set == choice }.map(\.deal.goal))
            counts[choice] = goals.filter { game.collectorPreview(for: $0)?.isReady == true }.count
        }
    }

    private var selectedTrade: CollectorPreview? {
        if let id = tradeTargets[set], let preview = game.collectorPreview(for: .trade(id)) {
            return preview
        }
        return game.collectorTrackedPreviews.first { $0.deal.set == set && $0.deal.collector == .tess }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        introduction.id("collectorBoardTop")
                        readyElsewhere
                        trackedGoals
                        setPicker
                        cashRequests
                        trader
                        CollectorSafetyNote()
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
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Haptics.play(.light)
                        onShop()
                    } label: {
                        Label("Shop", systemImage: "bag.fill")
                    }
                    .accessibilityIdentifier("collectorsBackToShop")
                }
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
            .alert("Couldn't update this goal", isPresented: errorPresented) {
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

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Good spares. Great connections.")
                .font(.title2.bold())
                .foregroundStyle(Palette.text)
            Text("Help Mira and Rowan for cash, or trade with Tess for a card you're missing.")
                .font(.subheadline)
                .foregroundStyle(Palette.subtle)
                .fixedSize(horizontal: false, vertical: true)
            Label("Always here · No timers · Works offline", systemImage: "heart.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(Palette.money)
        }
    }

    private var trackedGoals: some View {
        let header = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout())
        return VStack(alignment: .leading, spacing: 10) {
            header {
                Label("Tracked goals", systemImage: "bookmark.fill")
                    .font(.headline)
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                Text("\(game.collectorProgress.trackedGoals.count)/\(CollectorEconomy.maximumTrackedGoals)")
                    .font(.subheadline.bold().monospacedDigit())
                    .accessibilityLabel("\(game.collectorProgress.trackedGoals.count) of \(CollectorEconomy.maximumTrackedGoals) tracking slots used")
                    .accessibilityIdentifier("collectorTrackingCount")
            }
            .foregroundStyle(Palette.text)

            if game.collectorTrackedPreviews.isEmpty {
                Text("Track up to two goals across all sets. Their spare cards are saved automatically, even when you sell duplicates.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.subtle)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(game.collectorTrackedPreviews) { preview in
                    trackedRow(preview)
                }
                Text("Earlier goals get first pick. Untracking releases the cards, not the offer.")
                    .font(.caption)
                    .foregroundStyle(Palette.subtle)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .panel(14)
    }

    @ViewBuilder private var readyElsewhere: some View {
        let counts = readyCountsBySet
        let choices = availableSets.filter { $0 != set && counts[$0, default: 0] > 0 }
        if !choices.isEmpty {
            Menu {
                ForEach(choices, id: \.self) { choice in
                    Button("\(CardDatabase.setName(choice)) · \(counts[choice, default: 0]) ready") {
                        selectSet(choice)
                    }
                    .accessibilityIdentifier("collectorReadySet-\(choice)")
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Ready in other sets").font(.subheadline.bold())
                        Text(choices.map { "\(CardDatabase.setName($0)): \(counts[$0, default: 0])" }
                            .joined(separator: " · "))
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down").font(.caption.bold())
                }
                .foregroundStyle(Palette.money)
                .frame(minHeight: 44)
                .panel(12, corner: 14)
            }
            .accessibilityLabel("Ready in other sets. " + choices.map {
                "\(CardDatabase.setName($0)), \(counts[$0, default: 0]) ready"
            }.joined(separator: ". "))
            .accessibilityHint("Choose a set to see its ready offers.")
            .accessibilityIdentifier("collectorReadyElsewhere")
        }
    }

    private func trackedRow(_ preview: CollectorPreview) -> some View {
        let locked = game.requiresFullUnlock(set: preview.deal.set)
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
        return VStack(alignment: .leading, spacing: 6) {
            Divider().overlay(Palette.stroke)
            layout {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(preview.deal.collector.name) · \(CardDatabase.setName(preview.deal.set))")
                        .font(.subheadline.bold())
                        .foregroundStyle(preview.deal.collector.tint)
                    Text(preview.deal.title)
                        .font(.subheadline)
                        .foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(preview.collectedCount)/\(preview.deal.requiredCount) spares saved")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Palette.subtle)
                        .accessibilityIdentifier("collectorTrackedProgress-\(preview.id)")
                }
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                Button {
                    toggleTracking(preview.deal.goal)
                } label: {
                    Text("Untrack")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.subtle)
                        .frame(minWidth: 64, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Untrack \(preview.deal.title) for \(preview.deal.collector.name)")
                .accessibilityHint("Releases held cards. The offer stays available.")
                .accessibilityIdentifier("collectorUntrack-\(preview.id)")
            }
            if locked {
                Label("Full unlock needed to exchange. You can still untrack.", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(Palette.subtle)
            } else if preview.isReady {
                Button {
                    review(preview.deal.goal)
                } label: {
                    Label("Ready to review", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.bold())
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .foregroundStyle(Palette.money)
                .accessibilityIdentifier("collectorTrackedReview-\(preview.id)")
            }
        }
    }

    private var setPicker: some View {
        let counts = readyCountsBySet
        let readyCount = counts[set, default: 0]
        let readyBadge = Text("\(readyCount) ready")
            .font(.caption.bold())
            .foregroundStyle(Palette.money)
            .fixedSize()
        return VStack(alignment: .leading, spacing: 8) {
            Menu {
                ForEach(availableSets, id: \.self) { choice in
                    let title = "Set \(choice) · \(CardDatabase.setName(choice))"
                        + (counts[choice, default: 0] > 0 ? " · \(counts[choice, default: 0]) ready" : "")
                    Button {
                        selectSet(choice)
                    } label: {
                        if set == choice {
                            Label(title, systemImage: "checkmark")
                        } else {
                            Text(title)
                        }
                    }
                    .accessibilityIdentifier("collectorSet-\(choice)")
                }
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        if !dynamicTypeSize.isAccessibilitySize {
                            Image(systemName: Element.theme(forSet: set).glyphSymbol)
                                .foregroundStyle(Element.theme(forSet: set).badgeTint)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("SET \(set)").font(.caption.bold())
                            Text(CardDatabase.setName(set)).font(.headline)
                        }
                        Spacer(minLength: 8)
                        if readyCount > 0 && !dynamicTypeSize.isAccessibilitySize { readyBadge }
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.subheadline.bold())
                    }
                    if readyCount > 0 && dynamicTypeSize.isAccessibilitySize { readyBadge }
                }
                .foregroundStyle(Palette.text)
                .frame(minHeight: 44)
                .panel(12, corner: 14)
            }
            .accessibilityLabel("Collector set, \(CardDatabase.setName(set))")
            .accessibilityValue("\(counts[set, default: 0]) offers ready in this set")
            .accessibilityHint("Choose a playable set. Each choice shows its ready offers.")
            .accessibilityIdentifier("collectorSetPicker")

            if let next = (1...game.collectorSetLimit).first(where: { !game.isSetUnlocked($0) }) {
                Text("Collect \(game.uniquesToUnlock(set: next)) unique cards to meet collectors in \(CardDatabase.setName(next)).")
                    .font(.caption)
                    .foregroundStyle(Palette.subtle)
            }
            if game.collectorSetLimit < CardDatabase.setCount {
                Button {
                    Sound.play(.panelOpen)
                    sheet = .unlock
                } label: {
                    Label("More sets use the same one-time full unlock", systemImage: "lock.fill")
                        .font(.caption.weight(.semibold))
                        .frame(minHeight: 44, alignment: .leading)
                }
                .foregroundStyle(Palette.tapCue)
                .accessibilityIdentifier("collectorFullUnlock")
            }
        }
    }

    private var cashRequests: some View {
        VStack(spacing: 14) {
            ForEach([Collector.mira, .rowan], id: \.self) { collector in
                if let deal = game.collectorRequests(inSet: set).first(where: { $0.collector == collector }),
                   let preview = game.collectorPreview(for: deal.goal) {
                    offer(preview)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        CollectorIdentity(collector: collector)
                        Label("All \(CollectorEconomy.requestsPerCollector) requests complete", systemImage: "checkmark.seal.fill")
                            .font(.headline)
                            .foregroundStyle(Palette.money)
                        Text("You've helped \(collector.name) finish \(CardDatabase.setName(set)). Other sets have their own requests.")
                            .font(.subheadline)
                            .foregroundStyle(Palette.subtle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panel()
                }
            }
        }
    }

    @ViewBuilder private var trader: some View {
        if let preview = selectedTrade {
            offer(preview, onChooseTarget: chooseTarget)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                CollectorIdentity(collector: .tess)
                Text("A missing piece, not another gamble.")
                    .font(.headline)
                    .foregroundStyle(Palette.text)
                Text("\(game.collectorTradesRemaining(inSet: set)) of \(CollectorEconomy.tradesPerSet) trades left in this set")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Collector.tess.tint)
                    .accessibilityIdentifier("collectorTradesRemaining")
                if game.collectorTradesRemaining(inSet: set) == 0 {
                    Label("All \(CollectorEconomy.tradesPerSet) trades used in this set", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(Palette.money)
                        .accessibilityIdentifier("collectorTradesExhausted")
                    Text("Tess has a fresh trade allowance in each new set.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.subtle)
                } else if game.collectorTradeTargets(inSet: set).isEmpty {
                    Label("You own every card in this set", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(Palette.money)
                        .accessibilityIdentifier("collectorSetComplete")
                } else {
                    Text("Choose a missing card from \(CardDatabase.setName(set)). Give a bundle of different normal spares from this same set.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.subtle)
                    CollectorAction(title: "Choose a missing card", symbol: "rectangle.on.rectangle", tint: Collector.tess.tint,
                                    action: chooseTarget)
                        .accessibilityIdentifier("collectorChooseTarget")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel()
        }
    }

    private func offer(_ preview: CollectorPreview, onChooseTarget: (() -> Void)? = nil) -> some View {
        CollectorOfferCard(
            preview: preview,
            isTracked: game.collectorProgress.trackedGoals.contains(preview.deal.goal),
            trackingFull: game.collectorProgress.trackedGoals.count >= CollectorEconomy.maximumTrackedGoals,
            onTrack: { toggleTracking(preview.deal.goal) },
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
        let tracked = game.collectorTrackedPreviews.filter { choices.contains($0.deal.set) }
        if let priority = tracked.first(where: \.isReady) ?? tracked.first {
            set = priority.deal.set
            return
        }
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

    private func toggleTracking(_ goal: CollectorGoal) {
        do {
            let tracked = game.collectorProgress.trackedGoals.contains(goal)
            try game.setCollectorGoalTracked(goal, tracked: !tracked)
            Haptics.play(.light)
            Sound.play(tracked ? .uiBack : .toggleOn)
        } catch {
            report(error)
        }
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
    let preview: CollectorPreview
    let isTracked: Bool
    let trackingFull: Bool
    let onTrack: () -> Void
    let onReview: () -> Void
    var onChooseTarget: (() -> Void)?

    private var deal: CollectorDeal { preview.deal }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CollectorIdentity(collector: deal.collector)
            VStack(alignment: .leading, spacing: 4) {
                Text(deal.title)
                    .font(.title3.bold())
                    .foregroundStyle(Palette.text)
                Text(deal.rewardCard == nil
                     ? "Request \(deal.sequence) of \(deal.total) · \(CardDatabase.setName(deal.set))"
                     : "Trade \(deal.sequence) of \(deal.total) · \(CardDatabase.setName(deal.set))")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Palette.subtle)
            }

            VStack(alignment: .leading, spacing: 9) {
                CollectorSectionLabel(title: "You give", symbol: "arrow.up.right")
                ForEach(preview.requirements) { progress in
                    CollectorRequirementRow(progress: progress)
                        .accessibilityIdentifier("collectorRequirement-\(deal.id)-\(progress.id)")
                }
                ProgressBar(value: Double(preview.collectedCount), total: Double(deal.requiredCount),
                            tint: deal.collector.tint, height: 5)
                    .accessibilityHidden(true)
                Text(preview.isReady ? "All \(deal.requiredCount) normal spares ready to review"
                     : "\(preview.missingCount) more normal spare\(preview.missingCount == 1 ? "" : "s") needed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(preview.isReady ? Palette.money : Palette.subtle)
                    .accessibilityIdentifier("collectorOfferProgress-\(deal.id)")
            }

            CollectorReward(deal: deal)
            Text("Best and last copies stay with you. Only ungraded, non-foil spares go.")
                .font(.caption)
                .foregroundStyle(Palette.subtle)
                .fixedSize(horizontal: false, vertical: true)

            if preview.isReady {
                CollectorAction(title: "Review exchange", symbol: "arrow.left.arrow.right",
                                tint: deal.collector.tint, prominent: true, action: onReview)
                    .accessibilityLabel("Review \(deal.title) with \(deal.collector.name)")
                    .accessibilityIdentifier("collectorReview-\(deal.id)")
            }
            CollectorAction(title: isTracked ? "Untrack goal" : "Track goal",
                            symbol: isTracked ? "bookmark.slash" : "bookmark",
                            tint: isTracked ? Palette.subtle : deal.collector.tint,
                            action: onTrack)
                .accessibilityHint(isTracked
                                   ? "Releases held cards without removing the offer."
                                   : "Automatically protects the required spares from selling and grading.")
                .accessibilityIdentifier("collectorTrack-\(deal.id)")
            if !isTracked && trackingFull {
                Text("Both tracking slots are in use. Untrack a goal above to make room.")
                    .font(.caption)
                    .foregroundStyle(Palette.subtle)
            }
            if let onChooseTarget {
                Button(action: onChooseTarget) {
                    Text("Choose another missing card")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(deal.collector.tint)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("collectorChooseTarget")
            }
        }
        .panel()
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 2)
                .fill(deal.collector.tint.opacity(0.75))
                .frame(width: 42, height: 3)
                .padding(.top, 1)
                .accessibilityHidden(true)
        }
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
                    CardView(card: card, width: 34, pipsGlow: false)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "rectangle.stack.fill")
                        .font(.title3)
                        .foregroundStyle(progress.requirement.rarity?.accent ?? Palette.subtle)
                        .frame(minWidth: 34, minHeight: 44)
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
            .navigationTitle("Trade with Tess")
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
                    Text("These copies would sell to the shop for \(preview.sellValue.money). You give up that sale payout when you exchange them.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.subtle)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("collectorForegoneSale")
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
                        Text("Normal · Ungraded · New to your collection")
                            .font(.caption)
                            .foregroundStyle(Palette.subtle)
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
                Text("\(receipt.supplied.count) normal spares exchanged. Your last copies, best copies, foils, and graded cards stayed safe.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.subtle)
                    .fixedSize(horizontal: false, vertical: true)
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
            return left == 0 ? "You've used all of Tess's trades in this set."
                : "\(left) trade\(left == 1 ? "" : "s") left with Tess in \(CardDatabase.setName(receipt.deal.set))."
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

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: collector.symbol)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(collector.tint)
                .frame(width: 46, height: 46)
                .background(Circle().fill(collector.tint.opacity(0.14)))
                .overlay(Circle().strokeBorder(collector.tint.opacity(0.35), lineWidth: 1))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(collector.name)
                    .font(.headline)
                    .foregroundStyle(Palette.text)
                Text(collector.specialty)
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
