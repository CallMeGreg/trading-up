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
        VStack(spacing: 8) {
            Text("🎴")
                .font(.system(size: compact ? 40 : 58))
                .shadow(color: Palette.money.opacity(0.4), radius: 12)
            Text("Trading Up")
                .font(.system(size: compact ? 38 : 46, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 8, y: 3)
            Text("Collect all \(game.totalCards) Sprytes")
                .font(.system(size: 13, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(Palette.subtle)
        }
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

            unlockButton
        }
    }

    /// Gauntlet is gated behind the Full Game unlock. Locked, it wears a padlock
    /// and routes a tap to the paywall; unlocked, it opens the mode.
    private var gauntletButton: some View {
        MenuButton(
            title: "Gauntlet Mode",
            subtitle: unlocked ? "A relentless new way to play" : "Requires the Full Game",
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

    /// The unlock call-to-action, swapped for a quiet "owned" chip once bought.
    @ViewBuilder
    private var unlockButton: some View {
        if unlocked {
            Label("Full Game unlocked", systemImage: "checkmark.seal.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Palette.money)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 14).fill(Palette.money.opacity(0.10)))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.money.opacity(0.35), lineWidth: 1))
        } else {
            MenuButton(
                title: "Unlock the Full Game",
                subtitle: unlockSubtitle,
                systemImage: "lock.open.fill",
                tint: [Color(hex: "f5a300"), Color(hex: "e0663b")]
            ) {
                Haptics.play(.medium)
                showPaywall = true
            }
            .accessibilityIdentifier("unlockFullGameMenu")
        }
    }

    private var binderSubtitle: String {
        "Your best Sprytes · \(game.binder.filledCount)/\(game.binder.totalSlots)"
    }

    private var unlockSubtitle: String {
        if let price = purchases.displayPrice, !price.isEmpty {
            return "All sets + Gauntlet · \(price)"
        }
        return "All classic sets + Gauntlet Mode"
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
