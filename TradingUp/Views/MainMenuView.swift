import SwiftUI

/// The v2.0.0 home screen: a Spryte parade drifting behind the wordmark and the
/// four ways into the game — Classic Mode, Gauntlet Mode, the Binder, and the
/// one-time Full Game unlock. Each mode is presented full-screen over the menu so
/// it owns the whole display while it's up; the menu stays underneath, ready for
/// the player to come back to.
struct MainMenuView: View {
    @Environment(GameState.self) private var game: GameState
    @Environment(PurchaseStore.self) private var purchases: PurchaseStore

    /// Which mode is currently presented full-screen, if any.
    @State private var route: MenuRoute?
    /// Drives the full-version unlock paywall (from the Unlock button, or a tap on
    /// a still-locked Gauntlet Mode).
    @State private var showPaywall = false
    /// Drives the Settings sheet, opened from the gear in the top corner. Settings
    /// moved here from a Classic tab so it governs the whole app.
    @State private var showSettings = false
    /// A mode the player picked that already has a run in progress, so the menu is
    /// asking whether to resume it or start fresh. `nil` when no such prompt is up.
    @State private var resumePrompt: MenuRoute?
    /// A mode the player chose "New Run" for, pending the "lose your progress?"
    /// confirmation. `nil` when that confirm isn't up.
    @State private var confirmNewRun: MenuRoute?

    private var unlocked: Bool { game.isFullVersionUnlocked }

    var body: some View {
        ZStack {
            background

            ViewThatFits(in: .vertical) {
                content(compact: false)
                content(compact: true)
                ScrollView { content(compact: true) }
            }
            .readableWidth(460)
            .padding(.horizontal, 22)
        }
        .overlay(alignment: .topTrailing) { settingsButton }
        .fullScreenCover(item: $route) { route in
            switch route {
            case .classic:  ClassicModeView()
            case .gauntlet: GauntletView()
            case .binder:   BinderView()
            }
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .sheet(isPresented: $showSettings) {
            SettingsView(onExitToMenu: { showSettings = false })
        }
        // The save-load notice is raised at launch on whatever's on screen, which
        // is the menu — so it surfaces immediately, before the player picks a mode.
        .alert(game.loadIssue?.title ?? "", isPresented: loadIssueBinding) {
            Button("OK", role: .cancel) { game.dismissLoadIssue() }
        } message: {
            Text(game.loadIssue?.message ?? "")
        }
        // Picking a mode that already has a run asks whether to resume it or start
        // over, instead of a Settings reset button (req 3).
        .confirmationDialog(resumeTitle, isPresented: resumeBinding, titleVisibility: .visible) {
            if let mode = resumePrompt {
                Button("Continue") { enter(mode) }
                Button("New Run", role: .destructive) { promptNewRun(mode) }
                Button("Cancel", role: .cancel) {}
            }
        } message: {
            Text("Pick up where you left off, or start over.")
        }
        // "New Run" then has to be confirmed, because it throws the run away.
        .alert(newRunTitle, isPresented: confirmNewRunBinding, presenting: confirmNewRun) { mode in
            Button("Cancel", role: .cancel) {}
            Button("Start New Run", role: .destructive) { startNewRun(mode) }
        } message: { mode in
            Text(newRunMessage(for: mode))
        }
    }

    /// The gear that opens Settings, tucked into the top-trailing corner so it's
    /// always reachable from home without competing with the mode tiles.
    private var settingsButton: some View {
        Button {
            Haptics.play(.light)
            showSettings = true
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 42, height: 42)
                .background(Circle().fill(.white.opacity(0.10)))
                .overlay(Circle().strokeBorder(.white.opacity(0.14), lineWidth: 1))
        }
        .padding(.top, 6)
        .padding(.trailing, 18)
        .accessibilityIdentifier("settings")
        .accessibilityLabel("Settings")
    }

    // MARK: Layout

    private func content(compact: Bool) -> some View {
        VStack(spacing: compact ? 18 : 30) {
            Spacer(minLength: compact ? 8 : 24)
            wordmark(compact: compact)
            Spacer(minLength: 0)
            buttons
            Spacer(minLength: compact ? 8 : 20)
        }
        .frame(maxWidth: .infinity)
    }

    private func wordmark(compact: Bool) -> some View {
        let ringW: CGFloat = compact ? 250 : 300
        let ringH: CGFloat = compact ? 180 : 220
        let badge: CGFloat = compact ? 48 : 54
        return ZStack {
            SetLogoRing(width: ringW, height: ringH, badgeSize: badge)
            Text("Trading Up")
                .font(.system(size: compact ? 30 : 38, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 8, y: 3)
        }
        .frame(height: ringH + badge)
    }

    private var buttons: some View {
        VStack(spacing: 12) {
            MenuButton(
                title: "Classic Mode",
                subtitle: "Chase the \(game.totalCards)-card collection",
                systemImage: "square.grid.3x3.fill",
                accent: Color(hex: "56d98a")
            ) {
                Haptics.play(.medium)
                chooseMode(.classic)
            }
            .accessibilityIdentifier("classicMode")

            gauntletButton

            MenuButton(
                title: "Binder",
                subtitle: binderSubtitle,
                systemImage: "books.vertical.fill",
                accent: Color(hex: "6f9dff")
            ) {
                Haptics.play(.light)
                route = .binder
            }
            .accessibilityIdentifier("binder")
        }
    }

    /// Gauntlet is gated behind the Full Game unlock. Unlocked, it's an ordinary
    /// frosted tile that enters the mode. Locked, it expands into a "vault": the
    /// mode keeps its purple identity up top and a full-width amber call-to-action
    /// opens the paywall to buy the Full Game.
    @ViewBuilder
    private var gauntletButton: some View {
        if unlocked {
            MenuButton(
                title: "Gauntlet Mode",
                subtitle: "Craft a high value showcase",
                systemImage: "bolt.fill",
                accent: Color(hex: "b98cff")
            ) {
                Haptics.play(.medium)
                chooseMode(.gauntlet)
            }
            .accessibilityIdentifier("gauntletMode")
        } else {
            GauntletVaultButton(unlockTitle: unlockCTA) {
                Haptics.play(.light)
                showPaywall = true
            }
            .accessibilityIdentifier("gauntletMode")
        }
    }

    private var binderSubtitle: String {
        "Your best Sprytes · \(game.binder.filledCount)/\(game.binder.totalSlots)"
    }

    /// The locked Gauntlet vault's amber CTA line. Carries the live price once
    /// StoreKit resolves it, and stays a clean call to action before then.
    private var unlockCTA: String {
        if let price = purchases.displayPrice, !price.isEmpty {
            return "Unlock the Full Game · \(price)"
        }
        return "Unlock the Full Game"
    }

    private var background: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "10192e"), Palette.bg0],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            SpryteParadeView(featured: featuredSprytes)

            // Darken top and bottom so the wordmark and buttons stay legible over
            // whatever Sprytes happen to drift behind them.
            LinearGradient(
                colors: [Palette.bg0.opacity(0.85), .clear, Palette.bg0.opacity(0.92)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    /// Feature the player's own most valuable Sprytes in the parade when they have
    /// some, so a seasoned collector sees their trophies float by; the parade tops
    /// itself up from a curated spread otherwise.
    private var featuredSprytes: [String] {
        game.binder.bestByCardId.values
            .sorted { $0.currentValue > $1.currentValue }
            .prefix(10)
            .map(\.cardId)
    }

    private var loadIssueBinding: Binding<Bool> {
        Binding(get: { game.loadIssue != nil },
                set: { if !$0 { game.dismissLoadIssue() } })
    }

    // MARK: Resume / New Run (req 3)

    /// Entry point for the Classic and Gauntlet tiles. If the mode has a run
    /// in progress, ask whether to resume or restart; otherwise just enter.
    private func chooseMode(_ mode: MenuRoute) {
        if hasRunInProgress(mode) {
            resumePrompt = mode
        } else {
            route = mode
        }
    }

    private func hasRunInProgress(_ mode: MenuRoute) -> Bool {
        switch mode {
        case .classic:  return game.hasClassicProgress
        case .gauntlet: return GauntletRunStore().hasSavedRun
        case .binder:   return false
        }
    }

    /// Resume the existing run. Deferred so the confirmation dialog finishes
    /// dismissing before the full-screen cover presents.
    private func enter(_ mode: MenuRoute) {
        DispatchQueue.main.async { route = mode }
    }

    /// "New Run" tapped — raise the destructive confirmation. Deferred so it
    /// doesn't collide with the dismissing confirmation dialog.
    private func promptNewRun(_ mode: MenuRoute) {
        DispatchQueue.main.async { confirmNewRun = mode }
    }

    /// Confirmed "New Run": throw the old run away, then enter the mode fresh.
    private func startNewRun(_ mode: MenuRoute) {
        switch mode {
        case .classic:  game.newGame()
        case .gauntlet: GauntletRunStore().clear()
        case .binder:   break
        }
        Haptics.play(.warning)
        DispatchQueue.main.async { route = mode }
    }

    private var resumeBinding: Binding<Bool> {
        Binding(get: { resumePrompt != nil }, set: { if !$0 { resumePrompt = nil } })
    }

    private var confirmNewRunBinding: Binding<Bool> {
        Binding(get: { confirmNewRun != nil }, set: { if !$0 { confirmNewRun = nil } })
    }

    private var resumeTitle: String {
        switch resumePrompt {
        case .classic:  return "Classic run in progress"
        case .gauntlet: return "Gauntlet run in progress"
        default:        return ""
        }
    }

    private var newRunTitle: String {
        confirmNewRun == .classic ? "Start a new Classic run?" : "Start a new Gauntlet run?"
    }

    private func newRunMessage(for mode: MenuRoute) -> String {
        switch mode {
        case .classic:
            return "This erases your current Classic collection and cash, and starts over with \(Economy.startingCash.money). Your all-time record is kept."
        case .gauntlet:
            return "This discards your in-progress Gauntlet run so it won't resume. Your unlocked trainers and difficulties are kept."
        case .binder:
            return ""
        }
    }
}

// MARK: - Route

/// The full-screen destinations reachable from the menu.
enum MenuRoute: Int, Identifiable {
    case classic, gauntlet, binder
    var id: Int { rawValue }
}

// MARK: - Menu tiles

/// A home-screen menu tile in the frosted-glass style: a blurred translucent
/// panel with a colored accent rail and tinted glyph on the leading edge, the
/// title and subtitle, and a trailing chevron.
private struct MenuButton: View {
    let title: String
    var subtitle: String? = nil
    let systemImage: String
    /// Drives both the leading accent rail and the glyph tint.
    var accent: Color
    /// Optional capsule tag shown beside the title, e.g. "Coming soon!".
    var badge: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(accent)
                    .frame(width: 44, height: 46)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text(title)
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1).minimumScaleFactor(0.75)
                        if let badge { MenuBadge(text: badge) }
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.vertical, 14)
            .padding(.leading, 18)
            .padding(.trailing, 16)
            .frame(maxWidth: .infinity)
            .frostedTile(accent: accent)
        }
        .buttonStyle(MenuPressStyle())
    }
}

/// A small capsule tag shown beside a mode's title — e.g. "Coming soon!" on
/// Gauntlet Mode, in both its locked and unlocked states.
private struct MenuBadge: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy))
            .tracking(0.4)
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(.white.opacity(0.16)))
    }
}

/// The locked Gauntlet "vault": a frosted tile that keeps Gauntlet's purple
/// identity (medallion glyph + "Coming soon!" badge) and hosts a full-width amber
/// call-to-action, which opens the Full Game paywall.
private struct GauntletVaultButton: View {
    /// The amber CTA line, e.g. "Unlock the Full Game · $2.99".
    let unlockTitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                HStack(spacing: 14) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color(hex: "c9a9ff"))
                        .frame(width: 46, height: 46)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(
                                RadialGradient(
                                    colors: [Color(hex: "2a1c47"), Color(hex: "170e2b")],
                                    center: UnitPoint(x: 0.5, y: 0.32),
                                    startRadius: 1, endRadius: 40)
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color(hex: "4a2f86"), lineWidth: 1)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 7) {
                            Text("Gauntlet Mode")
                                .font(.system(size: 18, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                            MenuBadge(text: "Coming soon!")
                        }
                        Text("A relentless new way to play")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 4)
                }

                Text(unlockTitle)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(hex: "241a05"))
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 13, style: .continuous).fill(
                            LinearGradient(colors: [Color(hex: "ffd15c"), Color(hex: "f5a300")],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                    )
                    .shadow(color: Color(hex: "f5a300").opacity(0.35), radius: 8, y: 4)
            }
            .padding(15)
            .frame(maxWidth: .infinity)
            .frostedTile(accent: Color(hex: "b98cff"))
        }
        .buttonStyle(MenuPressStyle())
    }
}

/// The frosted-glass material shared by every menu tile: a blurred translucent
/// panel, a subtle dark wash for legibility over the Spryte parade, a hairline
/// border, and a colored accent rail down the leading edge.
private struct FrostedTile: ViewModifier {
    var accent: Color
    var corner: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .fill(Color(hex: "0e1420").opacity(0.45))
                    )
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(accent)
                            .frame(width: 5)
                            .padding(.vertical, 12)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .strokeBorder(.white.opacity(0.10), lineWidth: 1)
                    )
            }
            .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
    }
}

private extension View {
    func frostedTile(accent: Color, corner: CGFloat = 18) -> some View {
        modifier(FrostedTile(accent: accent, corner: corner))
    }
}

/// A gentle press-scale so the tiles feel tactile.
private struct MenuPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A slowly revolving ring of the five sets' emblems, encircling the wordmark.
/// Each set is stood in for by its signature element — the same element gradients
/// the shop uses to brand its banners — so the crest reads as "all five sets" at
/// a glance. The ring is elliptical so it hugs the wide title without the side
/// emblems colliding with it, and purely decorative (non-interactive).
private struct SetLogoRing: View {
    var width: CGFloat
    var height: CGFloat
    var badgeSize: CGFloat
    /// Seconds per full revolution — slow enough to feel like drift, not spin.
    var period: Double = 54

    var body: some View {
        TimelineView(.animation) { tl in
            let base = tl.date.timeIntervalSinceReferenceDate / period * 2 * Double.pi
            ZStack {
                ForEach(1...CardDatabase.setCount, id: \.self) { set in
                    let a = -Double.pi / 2 + base
                        + Double(set - 1) / Double(CardDatabase.setCount) * 2 * Double.pi
                    SetRingBadge(set: set, size: badgeSize)
                        .offset(x: CGFloat(cos(a)) * width / 2,
                                y: CGFloat(sin(a)) * height / 2)
                }
            }
        }
        .frame(width: width + badgeSize, height: height + badgeSize)
        .allowsHitTesting(false)
    }
}

/// One set's crest for the ring: its hand-drawn `SetEmblem` scene set into a dark
/// disc rimmed in the set's signature element colour, wrapped in a soft aura of
/// that same colour so it carries more presence and glows against the parade.
private struct SetRingBadge: View {
    let set: Int
    var size: CGFloat
    private var element: Element { Element.theme(forSet: set) }

    var body: some View {
        let glow = size * 2.35
        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [element.palette[1].opacity(0.62),
                                 element.palette[1].opacity(0.24),
                                 .clear],
                        center: .center,
                        startRadius: size * 0.4,
                        endRadius: glow / 2
                    )
                )
                .frame(width: glow, height: glow)
                .blur(radius: 5)

            SetEmblem(set: set)
                .frame(width: size, height: size)
                .background(Circle().fill(Color(hex: "0c1730")))
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(element.palette[1].opacity(0.85), lineWidth: 2))
                .shadow(color: element.palette[1].opacity(0.55), radius: size * 0.18, y: 1)
        }
        .frame(width: glow, height: glow)
    }
}
