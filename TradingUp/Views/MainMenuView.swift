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
        .fullScreenCover(item: $route) { route in
            switch route {
            case .classic:  ClassicModeView()
            case .gauntlet: GauntletView()
            case .binder:   BinderView()
            }
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        // The save-load notice is raised at launch on whatever's on screen, which
        // is the menu — so it surfaces immediately, before the player picks a mode.
        .alert(game.loadIssue?.title ?? "", isPresented: loadIssueBinding) {
            Button("OK", role: .cancel) { game.dismissLoadIssue() }
        } message: {
            Text(game.loadIssue?.message ?? "")
        }
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
                subtitle: "Chase the full \(game.totalCards)-card collection",
                systemImage: "square.grid.3x3.fill",
                tint: [Palette.money, Color(hex: "39b56a")]
            ) {
                Haptics.play(.medium)
                route = .classic
            }
            .accessibilityIdentifier("classicMode")

            gauntletButton

            MenuButton(
                title: "Binder",
                subtitle: binderSubtitle,
                systemImage: "books.vertical.fill",
                tint: [Color(hex: "3b82f6"), Color(hex: "6d5cf7")]
            ) {
                Haptics.play(.light)
                route = .binder
            }
            .accessibilityIdentifier("binder")
        }
    }

    /// Gauntlet is gated behind the Full Game unlock, and while locked it doubles
    /// as the unlock call-to-action: it wears a padlock, its subtitle carries the
    /// price, and a tap opens the paywall. Unlocked, it simply enters the mode.
    private var gauntletButton: some View {
        MenuButton(
            title: "Gauntlet Mode",
            subtitle: gauntletSubtitle,
            systemImage: "bolt.fill",
            tint: [Color(hex: "b06cf7"), Color(hex: "6d2bb3")],
            locked: !unlocked
        ) {
            if unlocked {
                Haptics.play(.medium)
                route = .gauntlet
            } else {
                Haptics.play(.light)
                showPaywall = true
            }
        }
        .accessibilityIdentifier("gauntletMode")
    }

    private var binderSubtitle: String {
        "Your best Sprytes · \(game.binder.filledCount)/\(game.binder.totalSlots)"
    }

    /// Locked, the Gauntlet button doubles as the Full Game unlock CTA, so its
    /// subtitle carries the price; unlocked, it's just the mode's tagline.
    private var gauntletSubtitle: String {
        if unlocked { return "A relentless new way to play" }
        if let price = purchases.displayPrice, !price.isEmpty {
            return "Unlock the Full Game · \(price)"
        }
        return "Unlock the Full Game — all sets + Gauntlet"
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
}

// MARK: - Route

/// The full-screen destinations reachable from the menu.
enum MenuRoute: Int, Identifiable {
    case classic, gauntlet, binder
    var id: Int { rawValue }
}

// MARK: - Menu button

/// A tall home-screen menu tile: icon, title, subtitle, and a trailing chevron —
/// or a padlock when the option is gated behind a purchase.
private struct MenuButton: View {
    let title: String
    var subtitle: String? = nil
    let systemImage: String
    var tint: [Color]
    var locked: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(.white.opacity(0.18)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.82))
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
                Spacer(minLength: 4)

                Image(systemName: locked ? "lock.fill" : "chevron.right")
                    .font(.system(size: locked ? 16 : 14, weight: .bold))
                    .foregroundStyle(.white.opacity(locked ? 0.9 : 0.6))
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18).fill(
                    LinearGradient(colors: tint, startPoint: .leading, endPoint: .trailing)
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: tint.first?.opacity(0.35) ?? .clear, radius: 10, y: 4)
        }
        .buttonStyle(MenuPressStyle())
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
        let glow = size * 1.85
        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [element.palette[1].opacity(0.5),
                                 element.palette[1].opacity(0.14),
                                 .clear],
                        center: .center,
                        startRadius: size * 0.42,
                        endRadius: glow / 2
                    )
                )
                .frame(width: glow, height: glow)
                .blur(radius: 3)

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
