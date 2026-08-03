import Foundation

/// Build-time switches for behaviour we want to be able to turn on — or back
/// off — by editing one line, instead of deleting code and later resurrecting
/// it from git history.
///
/// Flags are `var` rather than `let` purely so tests can exercise both states;
/// nothing in the app mutates them at runtime, and every read happens on the
/// main actor during a view update or a purchase.
enum FeatureFlags {

    /// Takes booster boxes off the shelf, leaving single packs as the only
    /// thing the shop sells.
    ///
    /// **Currently enabled** — the shop sells packs only. The mechanic was
    /// pulled rather than deleted because it is likely to come back in some
    /// form, and reading one flag beats resurrecting a feature from git
    /// history. While this is `true`:
    ///
    /// - `SetShelfRow` drops its "Booster box · …" line, so a set row is just
    ///   the pack buy.
    /// - `GameState.buyBox(set:)` / `buyBoxPacks(set:)` refuse the sale, so no
    ///   stale call site, deep link, or UI test can spend the player's cash on
    ///   something the shop no longer advertises.
    /// - The "Boxes Opened" / "Boxes" tiles disappear from Stats, the win
    ///   screen and the shareable win card, instead of reporting a permanent
    ///   zero at the player.
    /// - The verify harness buys packs only, so the difficulty curve it
    ///   enforces is the one players actually face.
    ///
    /// What the flag does *not* touch is everything under `GameCore` — pack
    /// composition, the ultra/foil guarantees, box pricing — which stays intact
    /// and fully covered by tests. It closes the shop door; it doesn't
    /// dismantle the room behind it. Box counts already recorded in a save are
    /// likewise left alone, so flipping this back is lossless.
    static var removeBoosterBoxes = true

    /// Whether the shop should still sell booster boxes. Reads better at the
    /// call site than negating ``removeBoosterBoxes`` in a dozen places.
    static var boosterBoxesAvailable: Bool { !removeBoosterBoxes }
}
