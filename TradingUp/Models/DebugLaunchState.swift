#if DEBUG
import Foundation

/// Test-only fast travel into a scripted game state.
///
/// Ripping the ~300 packs it takes to finish a collection by hand is far too
/// slow for a test — or a developer — that only wants to see the *ending*. This
/// reads a launch environment variable and, when present, seeds the game
/// straight into a late-game state so the last stretch can be exercised in
/// seconds.
///
/// It is wrapped in `#if DEBUG` in its entirety, so the whole mechanism is
/// compiled out of release builds: a shipped App Store build has no code path
/// that can grant cash or cards, so there is nothing here to abuse in
/// production. `GameState.init` consults it only in DEBUG, before it would
/// otherwise load the real save.
///
/// Drive it from a UI test:
///
///     app.launchEnvironment["TU_TEST_STATE"] = "almost-won"
///
/// or from the command line for a manual run:
///
///     xcrun simctl launch --console <udid> com.callmegreg.tradingup \
///         --setenv TU_TEST_STATE almost-won
enum DebugLaunchState {

    /// Environment key a test sets to request a seeded state.
    static let key = "TU_TEST_STATE"
    /// Optional override for the starting bankroll of a seeded state.
    static let cashKey = "TU_TEST_CASH"
    /// Optional override for which card the seeded state holds out, e.g. the rare
    /// the recorded ending demo finishes on. Any valid card id.
    static let missingKey = "TU_TEST_MISSING"
    /// Optional fixed RNG seed, so a scripted run pulls a known pack. DEBUG-only,
    /// read by `GameState.init` to pin `AppRNG`.
    static let seedKey = "TU_TEST_SEED"

    /// The seeded `GameCore` requested by the launch environment, or `nil` when
    /// no test state was asked for (the normal launch path).
    static func core(environment: [String: String] = ProcessInfo.processInfo.environment) -> GameCore? {
        guard let state = environment[key]?.trimmingCharacters(in: .whitespaces), !state.isEmpty else {
            return nil
        }
        let cash = environment[cashKey].flatMap(Double.init)
        let missing = environment[missingKey]?.trimmingCharacters(in: .whitespaces)
        switch state {
        case "almost-won":
            return almostWon(missing: (missing?.isEmpty == false) ? missing : nil, cash: cash)
        case "almost-champion":
            return almostChampion(cash: cash)
        default:
            return nil
        }
    }

    /// The fixed RNG seed requested by the launch environment, or `nil` to keep
    /// genuine system randomness.
    static func seed(environment: [String: String] = ProcessInfo.processInfo.environment) -> UInt64? {
        environment[seedKey].flatMap { UInt64($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// A game a single unique card short of a complete collection, with cash to
    /// spare — the fast path an automated test uses to reach the ending. One
    /// more pack from the set that still has a hole in it can finish the
    /// collection and trigger the win. Every other set is already claimed, so
    /// the only reward left to fire is that final set completion and the win
    /// itself.
    static func almostWon(missing missingId: String? = nil, cash: Double? = nil) -> GameCore {
        var core = GameCore()
        core.welcomeSeen = true

        // Hold out one low-value common from set 1: commons are the slot a pack
        // fills most (three per pack), so the missing card lands quickly, and a
        // set-1 pack is the cheapest to buy while ripping toward it.
        let holdOut = missingId
            ?? CardDatabase.cards(inSet: 1).last(where: { $0.rarity == .common })?.id
            ?? CardDatabase.all.first?.id
        guard let holdOut else { return core }

        for card in CardDatabase.all where card.id != holdOut {
            core.instances.append(CardInstance(cardId: card.id))
        }

        // Pre-claim every bonus the seeded 249 cards have already earned (all the
        // evolution lines and sets 2–5), so completing the last card fires only
        // the final set's bonus and the win — not a flood of back-claimed
        // rewards on the deciding pack's summary. Owning 249/250 keeps `hasWon`
        // false, so the win still has to be earned by that last pull.
        _ = core.checkBonuses()

        // Set cash last so the seeded bankroll is exactly what was asked for,
        // rather than that plus the pre-claim bonuses just banked above.
        core.cash = cash ?? 2_000
        return core
    }

    /// A Season sitting at the Championship (final Show) with net worth already
    /// past the Quota — so the shop shows the "Make the Cut" call-to-action and a
    /// single tap wins the Season. The fast path a UI test uses to reach the
    /// Season Champion celebration without playing eight Shows by hand.
    static func almostChampion(cash: Double? = nil) -> GameCore {
        var core = GameCore()
        core.welcomeSeen = true
        core.ensureActiveRun()
        core.run.show = Economy.seasonShows                 // the Masters Invitational
        // Comfortably clear the final Quota outright, so `canMakeCut` is true the
        // moment the shop appears.
        core.cash = cash ?? (Economy.quota(show: Economy.seasonShows) + 500)
        return core
    }
}
#endif
