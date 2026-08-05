import Foundation

/// The random source every pull, grade and foil roll draws from.
///
/// In a shipping build it is nothing but the system generator. A DEBUG build can
/// pin it to a fixed seed so an automated run — the ending demo the UI test
/// records, say — plays out identically every single time. The seeding path is
/// wrapped in `#if DEBUG`, so release builds contain no way to make the game
/// deterministic and nothing here to abuse in production.
///
/// It is a concrete type (rather than `any RandomNumberGenerator`) so it can be
/// passed straight to `GameCore`'s generic `using rng:` entry points.
struct AppRNG: RandomNumberGenerator {
    private var system = SystemRandomNumberGenerator()
    #if DEBUG
    private var seeded: DebugSeededRNG?
    #endif

    /// The normal generator: genuine system randomness.
    init() {}

    #if DEBUG
    /// A deterministic generator pinned to `seed`. DEBUG-only.
    init(seed: UInt64) { seeded = DebugSeededRNG(seed) }
    #endif

    mutating func next() -> UInt64 {
        #if DEBUG
        if seeded != nil { return seeded!.next() }
        #endif
        return system.next()
    }
}

#if DEBUG
/// SplitMix64 — a tiny, fast, fully deterministic generator. Matches the RNG the
/// simulation harness (`tools/verify/main.swift`) and the seeded unit tests use,
/// so a seed reproduces the same stream there and in the app. DEBUG-only.
struct DebugSeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(_ seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
#endif
