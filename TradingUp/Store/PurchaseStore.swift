import Foundation
import StoreKit

/// The StoreKit 2 layer behind the one-time **"Unlock the full collection"**
/// purchase (Option A monetization: Set 1 is free, sets 2–5 and the 250-card win
/// are unlocked by a single non-consumable).
///
/// Deliberately *outside* `Models/`: the pure game logic there stays Foundation-
/// only and StoreKit-free, and the `tools/verify` harness never sees this file.
/// StoreKit is the **source of truth** — the entitlement is re-verified from
/// `Transaction.currentEntitlements` on every launch and on every transaction
/// update — and the verified result is pushed into `GameState`, which is all the
/// rest of the app reads. A last-known value is cached in `UserDefaults` purely
/// so a returning owner doesn't see a paywall flash before the (fast, local)
/// verification completes; it is a hint, never the authority.
@Observable
@MainActor
final class PurchaseStore {

    /// Must match the product created in App Store Connect and in the bundled
    /// `.storekit` test configuration. Namespaced under the app's bundle id.
    static let fullUnlockProductID = "com.callmegreg.tradingup.fullunlock"

    /// UserDefaults key for the cached entitlement hint. Reading/writing the
    /// app's own preferences is the `CA92.1` reason already declared in
    /// `PrivacyInfo.xcprivacy`, so this adds no new privacy surface.
    private static let cacheKey = "fullVersionUnlocked"

    /// The loaded product, for its localized display price and title. Nil until
    /// `loadProducts()` succeeds — e.g. while offline with nothing cached — in
    /// which case the paywall offers a retry rather than a hard-coded price.
    private(set) var fullUnlock: Product?

    /// The localized price string the paywall shows, or `nil` before the product
    /// loads. Normally just the loaded product's `displayPrice`. In DEBUG a
    /// launch-environment override (`TU_FAKE_PRICE`) can stand in for it, so the
    /// App Review screenshot capture can render the real price without a live
    /// StoreKit product — a UI-test host can't load one. The whole override is
    /// compiled out of release, so shipping builds only ever read the real
    /// product price.
    var displayPrice: String? {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["TU_FAKE_PRICE"],
           !override.isEmpty {
            return override
        }
        #endif
        return fullUnlock?.displayPrice
    }

    #if DEBUG
    /// Launch key for the DEBUG-only entitlement override.
    private static let forceUnlockKey = "TU_FORCE_UNLOCK"

    /// DEBUG-only launch override that forces the full-version entitlement on, so
    /// the *unlocked* main menu — and Gauntlet Mode — can be exercised and
    /// screenshotted without a live StoreKit purchase. It is the entitlement
    /// analogue of `TU_FAKE_PRICE`: read only here, honoured by `init` and
    /// `refresh()`, and compiled out of release entirely, so a shipped build has
    /// no code path that can grant the unlock this way.
    private static var forcedUnlock: Bool {
        switch ProcessInfo.processInfo.environment[forceUnlockKey]?.lowercased() {
        case "1", "true", "yes": return true
        default: return false
        }
    }
    #endif

    /// The verified entitlement, mirrored here for the paywall's own UI.
    /// `GameState.isFullVersionUnlocked` is the game-facing copy and is kept in
    /// step through `apply(_:)`.
    private(set) var isFullVersionUnlocked: Bool

    /// True while a purchase or restore round-trip is in flight, so the paywall
    /// can show progress and disable its controls.
    private(set) var isWorking = false

    /// A human-readable message from the last failed purchase/restore, surfaced
    /// by the paywall and cleared when the next attempt starts.
    private(set) var lastError: String?

    private let game: GameState
    /// `@ObservationIgnored` (it's plumbing, not UI state) keeps this a plain
    /// stored property, and `nonisolated(unsafe)` lets `deinit` — a nonisolated
    /// context under this toolchain — cancel the lifetime listener. `deinit` runs
    /// only once no other reference survives, so that access is exclusive.
    @ObservationIgnored private nonisolated(unsafe) var updatesTask: Task<Void, Never>?

    init(game: GameState) {
        self.game = game

        // Instant, cached hint so an owner's paid sets are open on cold launch,
        // before the async StoreKit check lands. Overwritten by `refresh()`.
        var initial = UserDefaults.standard.bool(forKey: Self.cacheKey)
        #if DEBUG
        initial = initial || Self.forcedUnlock
        #endif
        isFullVersionUnlocked = initial
        game.setFullVersionUnlocked(initial)

        // A lifetime listener for transactions that arrive *outside* a direct
        // purchase: Ask-to-Buy approvals, a buy made on another device, or a
        // refund/revocation. Apple recommends starting this as early as possible.
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }

        // Verify the real entitlement and load the product for display.
        Task { [weak self] in
            await self?.refresh()
            await self?.loadProducts()
        }
    }

    deinit { updatesTask?.cancel() }

    // MARK: - Loading

    /// Fetch the product so the paywall can show its localized price/title.
    func loadProducts() async {
        do {
            let products = try await Product.products(for: [Self.fullUnlockProductID])
            fullUnlock = products.first
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Recompute the entitlement from StoreKit's `currentEntitlements` — the
    /// authoritative, locally-verified set of non-consumables the account owns.
    /// Runs on launch, after a purchase, and after a restore.
    func refresh() async {
        #if DEBUG
        if Self.forcedUnlock { apply(true); return }
        #endif
        var owned = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == Self.fullUnlockProductID,
               transaction.revocationDate == nil {
                owned = true
            }
        }
        apply(owned)
    }

    // MARK: - Purchase / restore

    /// Buy the full-version unlock. Returns true only once a verified transaction
    /// has been recorded and the entitlement applied. `.pending` (Ask to Buy)
    /// returns false here; the grant then arrives later via `Transaction.updates`.
    @discardableResult
    func purchaseFullUnlock() async -> Bool {
        guard let product = fullUnlock else {
            await loadProducts()
            if fullUnlock == nil { lastError = "The store is unavailable right now. Try again." }
            return false
        }
        isWorking = true
        lastError = nil
        defer { isWorking = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    lastError = "That purchase couldn't be verified."
                    return false
                }
                await transaction.finish()
                apply(true)
                return true
            case .userCancelled:
                return false
            case .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Restore previous purchases. For a non-consumable this is really just
    /// "re-sync with the App Store and re-check entitlements". Apple **requires**
    /// an explicit Restore control, and `AppStore.sync()` forces the refresh
    /// (prompting for the store login if needed).
    func restore() async {
        isWorking = true
        lastError = nil
        defer { isWorking = false }
        do {
            try await AppStore.sync()
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Private

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else { return }
        await transaction.finish()
        await refresh()
    }

    /// Single choke point that keeps the three copies of the entitlement — this
    /// object, `GameState`, and the cached hint — in lockstep.
    private func apply(_ unlocked: Bool) {
        isFullVersionUnlocked = unlocked
        game.setFullVersionUnlocked(unlocked)
        UserDefaults.standard.set(unlocked, forKey: Self.cacheKey)
    }
}
