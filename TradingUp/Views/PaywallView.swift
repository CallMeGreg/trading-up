import SwiftUI

/// The paywall for the one-time full-version unlock (Option A monetization).
/// Presented from the shop when a player taps a paid, still-locked set. Set 1 ·
/// Emberfall stays free to play in full, so this is always opt-in: the free game
/// keeps working whether or not it is ever shown.
struct PaywallView: View {
    @Environment(PurchaseStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "10192e"), Palette.bg0],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            RadialGradient(gradient: Gradient(colors: [Palette.money.opacity(0.22), .clear]),
                           center: .top, startRadius: 20, endRadius: 460)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    header
                    perks
                    if let error = store.lastError { errorNote(error) }
                    actions
                    finePrint
                }
                .padding(16)
                .readableWidth()
            }
        }
        // Auto-dismiss the instant the entitlement lands — covers a direct buy, a
        // restore, and an Ask-to-Buy approval that arrives while this is open.
        .onChange(of: store.isFullVersionUnlocked) { _, unlocked in
            if unlocked { dismiss() }
        }
        .overlay(alignment: .topTrailing) { closeButton }
    }

    private var priceText: String { store.displayPrice ?? "" }

    private var header: some View {
        VStack(spacing: 10) {
            Text("🗂️").font(.system(size: 60))
            Text("UNLOCK THE FULL GAME")
                .font(.system(size: 13, weight: .black)).tracking(2)
                .foregroundStyle(Palette.subtle)
                .multilineTextAlignment(.center)
            Text("Keep collecting past Emberfall")
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 28)
    }

    private var perks: some View {
        VStack(alignment: .leading, spacing: 14) {
            perk("🌊", "Four more sets",
                 "Tidecaller, Verdspire, Voltcrest and Umbral Reach — 200 more cards to chase.")
            perk("⚡", "Gauntlet Mode",
                 "Unlocks a relentless new way to play, arriving in a future update.")
            perk("🏆", "Go for Master Collector",
                 "The full 250-card win, plus every set-completion and evolution bonus past Set 1.")
            perk("💎", "One-time purchase",
                 "Pay once and it's yours. No subscription, no packs for real money, no ads.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(16)
    }

    private func perk(_ emoji: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(emoji).font(.system(size: 24)).frame(width: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.text)
                Text(body).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.subtle)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

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
}
