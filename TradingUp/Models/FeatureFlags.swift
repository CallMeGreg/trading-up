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
    /// **Currently disabled** — boxes are still offered, so the app behaves
    /// exactly as it did before this flag existed. Flip to `true` and:
    ///
    /// - `SetShelfRow` drops its "Booster box · …" line, so a set row is just
    ///   the pack buy.
    /// - `GameState.buyBox(set:)` / `buyBoxPacks(set:)` refuse the sale, so no
    ///   stale call site, deep link, or UI test can spend the player's cash on
    ///   something the shop no longer advertises.
    ///
    /// Deliberately *not* gated: the reveal flow's box art and the "Boxes
    /// Opened" stat tiles. Those describe boxes a player already opened, and
    /// erasing that history would be a lie about their save.
    static var removeBoosterBoxes = false

    /// Whether the shop should still sell booster boxes. Reads better at the
    /// call site than negating ``removeBoosterBoxes`` in a dozen places.
    static var boosterBoxesAvailable: Bool { !removeBoosterBoxes }
}
