import Foundation

/// A Gauntlet "Catalyst": a new card type that rips can surface alongside the
/// Sprytes. A Catalyst can be **attuned** (consuming a Catalyst slot, its effect
/// applies for the rest of the run) or **sold** for a little cash. Effects stack,
/// so a run's identity is built partly from the Catalysts it commits to.
///
/// Catalysts speak the same `RunMods` language as Trainers, so the run just sums
/// them. The five archetypes map to the Gauntlet elements — Shadow, not "Dark";
/// and these are Catalysts, not "Energy" — deliberately, to keep clear of the
/// trademarked TCG vocabulary (docs/DESIGN.md §14.4).
struct Catalyst: Identifiable, Codable, Hashable {
    let id: String
    let element: Element
    let name: String
    let blurb: String
    var mods: RunMods
    /// Cash gained if it's sold instead of attuned.
    var saleValue: Double
}

extension Catalyst {

    /// One archetype per Gauntlet element. Magnitudes are harness-tuned.
    static let roster: [Catalyst] = [
        Catalyst(id: "ignition", element: .fire, name: "Ignition",
                 blurb: "Packs run hot: more foils, more ultras.",
                 mods: { var m = RunMods.none; m.foilChanceBonus = 0.05; m.ultraChanceBonus = 0.10; return m }(),
                 saleValue: 20),

        Catalyst(id: "tide", element: .water, name: "Tide",
                 blurb: "The floor buys back kinder. Better sell-back.",
                 mods: { var m = RunMods.none; m.sellbackBonus = 0.08; return m }(),
                 saleValue: 20),

        Catalyst(id: "bloom", element: .grass, name: "Bloom",
                 blurb: "Everything reads richer. A global Aura lift.",
                 mods: { var m = RunMods.none; m.auraMult = 1.12; return m }(),
                 saleValue: 20),

        Catalyst(id: "overload", element: .electric, name: "Overload",
                 blurb: "Fortune at the slab — grades swing your way.",
                 mods: { var m = RunMods.none; m.gradeLuckBonus = 0.18; return m }(),
                 saleValue: 20),

        Catalyst(id: "eclipse", element: .shadow, name: "Eclipse",
                 blurb: "Faster hands. One extra rip every round, starting now.",
                 mods: { var m = RunMods.none; m.extraRipsPerRound = 1; return m }(),
                 saleValue: 20),
    ]

    static func byId(_ id: String) -> Catalyst? { roster.first { $0.id == id } }

    static func random<G: RandomNumberGenerator>(using rng: inout G) -> Catalyst {
        roster.randomElement(using: &rng)!
    }

    /// A concise, mechanical description of what attuning this Catalyst does for the
    /// rest of the run, derived from its `RunMods` so it always matches the real
    /// effect. Drives the tap-to-inspect detail for an attuned Catalyst.
    var effectSummary: String {
        let s = mods.effectSummary
        return s.isEmpty ? "A one-time run buff." : s
    }
}
