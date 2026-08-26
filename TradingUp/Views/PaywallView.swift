import SwiftUI

/// The paywall for the one-time full-game unlock.
///
/// v2.0.0 reframes the purchase as unlocking the *whole* game — all five Classic
/// sets **and** Gauntlet Mode — so it reads the same however a player arrives:
/// tapping a paid, still-locked set in the Classic shop, or tapping the locked
/// Gauntlet button on the main menu. It's a sheet over that origin, and because a
/// successful purchase flips `GameState` in lockstep with the store, dismissing on
/// success drops the player right back where they were with the content now
/// unlocked. Set 1 · Emberfall stays free to play in full, so this is always
/// opt-in: the free game keeps working whether or not it is ever shown.
struct PaywallView: View {
    @Environment(GameState.self) private var game
    @Environment(PurchaseStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            background

            ScrollView {
                VStack(spacing: 18) {
                    hero
                    pillars
                    assurances
                    if let error = store.lastError { errorNote(error) }
                    actions
                    finePrint
                }
                .padding(16)
                .readableWidth()
            }
        }
        // Auto-dismiss the instant the entitlement lands — covers a direct buy, a
        // restore, and an Ask-to-Buy approval that arrives while this is open. The
        // sheet slides away to reveal whatever presented it (shop or menu), now
        // unlocked, so the player lands back exactly where they started.
        .onChange(of: store.isFullVersionUnlocked) { _, unlocked in
            if unlocked { dismiss() }
        }
        .overlay(alignment: .topTrailing) { closeButton }
    }

    // MARK: - Hero

    /// A crest of all five sets over the offer line, so the screen reads as "the
    /// whole game" at a glance no matter which door the player came through. The
    /// emblems mirror the main-menu ring, tying the two v2 surfaces together.
    private var hero: some View {
        VStack(spacing: 16) {
            emblemStrip
            VStack(spacing: 8) {
                Text("ONE-TIME UNLOCK")
                    .font(.system(size: 13, weight: .black)).tracking(2)
                    .foregroundStyle(Palette.subtle)
                Text("Unlock the Full Game")
                    .font(.system(size: 27, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("All five sets and Gauntlet Mode — one purchase, yours forever.")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.text)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 30)
    }

    private var emblemStrip: some View {
        HStack(spacing: 12) {
            ForEach(1...CardDatabase.setCount, id: \.self) { HeroEmblem(set: $0) }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Pillars (what the unlock includes)

    /// The two things the unlock grants, side by side, so whichever mode's button
    /// opened this screen the player sees it represented — plus the other. Classic
    /// leads because its content (200 more cards) is playable the moment you buy;
    /// Gauntlet is flagged as coming so the offer stays honest.
    private var pillars: some View {
        VStack(spacing: 12) {
            pillar(
                icon: "square.grid.3x3.fill",
                tint: [Palette.money, Color(hex: "39b56a")],
                title: "Classic Mode · all five sets",
                detail: "Open up Tidecaller, Verdspire, Voltcrest and Umbral Reach and chase the full \(game.totalCards)-card collection — with every set and evolution bonus along the way."
            )
            pillar(
                icon: "bolt.fill",
                tint: [Color(hex: "b06cf7"), Color(hex: "6d2bb3")],
                title: "Gauntlet Mode",
                detail: "A relentless new way to play, arriving in a future update — and it's yours automatically the moment it lands.",
                tag: "COMING SOON"
            )
        }
    }

    private func pillar(icon: String, tint: [Color], title: String,
                        detail: String, tag: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 13).fill(
                        LinearGradient(colors: tint, startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                )
                .shadow(color: (tint.first ?? .clear).opacity(0.4), radius: 8, y: 3)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if let tag {
                        Text(tag)
                            .font(.system(size: 9, weight: .black)).tracking(0.5)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill((tint.last ?? Palette.subtle).opacity(0.9)))
                    }
                }
                Text(detail)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.subtle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(16)
    }

    // MARK: - Assurances

    private var assurances: some View {
        VStack(alignment: .leading, spacing: 11) {
            assurance("One-time purchase — no subscription, ever.")
            assurance("No ads, no tracking, and it plays fully offline.")
            assurance("Restores on all your Apple devices.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(16)
    }

    private func assurance(_ text: String) -> some View {
        HStack(alignment: .center, spacing: 11) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Palette.money)
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Actions

    private var priceText: String { store.displayPrice ?? "" }

    private var actions: some View {
        VStack(spacing: 10) {
            BigButton(title: store.isWorking ? "Working…" : "Unlock the full game",
                      subtitle: priceText.isEmpty ? "One-time purchase"
                                                  : "\(priceText) · one-time purchase",
                      systemImage: "lock.open.fill",
                      tint: [Palette.money, Color(hex: "39b56a")],
                      enabled: !store.isWorking) {
                Task {
                    Haptics.play(.medium)
                    let ok = await store.purchaseFullUnlock()
                    if ok { Haptics.play(.success) }
                }
            }

            Button {
                Task { await store.restore() }
            } label: {
                Text("Restore purchase")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.tapCue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .disabled(store.isWorking)
            .accessibilityIdentifier("restorePurchase")
        }
    }

    private func errorNote(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(Color(hex: "e0663b"))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    private var finePrint: some View {
        Text("Set 1 · Emberfall is free to play in full. Purchases are tied to your Apple Account and can be restored on your other devices.")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Palette.subtle)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
            .padding(.top, 2)
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 26))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Palette.subtle)
        }
        .buttonStyle(.plain)
        .padding(12)
        .accessibilityLabel("Close")
    }

    private var background: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "10192e"), Palette.bg0],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            RadialGradient(gradient: Gradient(colors: [Palette.money.opacity(0.18), .clear]),
                           center: .top, startRadius: 20, endRadius: 460)
                .ignoresSafeArea()
        }
    }
}

/// One set's crest for the paywall hero: its hand-drawn `SetEmblem` in a dark disc
/// rimmed and haloed in the set's signature element colour — the same treatment
/// the main-menu ring uses, so the two v2 surfaces share a visual language. The
/// halo bleeds past the emblem's layout footprint so the five run together into a
/// soft band of colour without pushing the row wider.
private struct HeroEmblem: View {
    let set: Int
    var size: CGFloat = 44
    private var element: Element { Element.theme(forSet: set) }

    var body: some View {
        let glow = size * 1.7
        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [element.palette[1].opacity(0.5),
                                 element.palette[1].opacity(0.16),
                                 .clear],
                        center: .center,
                        startRadius: size * 0.35,
                        endRadius: glow / 2
                    )
                )
                .frame(width: glow, height: glow)
                .blur(radius: 4)

            SetEmblem(set: set)
                .frame(width: size, height: size)
                .background(Circle().fill(Color(hex: "0c1730")))
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(element.palette[1].opacity(0.85), lineWidth: 1.5))
                .shadow(color: element.palette[1].opacity(0.5), radius: size * 0.16, y: 1)
        }
        .frame(width: size, height: size)
    }
}
