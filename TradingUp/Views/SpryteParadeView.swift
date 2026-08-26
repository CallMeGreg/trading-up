import SwiftUI

/// The home-screen showpiece: a slow, dreamlike parade of Sprytes drifting up
/// through the background behind the main menu. Each floats on its own loop,
/// swaying side to side, gently spinning, and haloed in its element's colour —
/// a living wallpaper made of the very creatures the game is about.
///
/// Like `FireworksView`, every transform is a pure function of elapsed time and a
/// set of per-Spryte constants seeded once at init, so the whole thing is
/// frame-stable, self-sustaining, and needs no timers or per-frame mutable state.
/// It never takes touches, so the menu's buttons sit right on top of it.
struct SpryteParadeView: View {

    /// The Spryte art to feature. Callers can pass the player's own binder
    /// standouts; anything short of a full roster is topped up from a curated
    /// spread so the parade always looks full, even on a brand-new save.
    var featured: [String] = []

    /// How many Sprytes drift at once. A calm crowd, not a swarm.
    var count: Int = 14

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                ZStack {
                    ForEach(sprytes) { spryte in
                        FloatingSpryte(spryte: spryte, time: t, canvas: geo.size)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    /// The resolved roster: featured ids first, then curated fillers, de-duped and
    /// trimmed to `count`, each paired with seeded motion constants.
    private var sprytes: [Spryte] {
        var ids: [String] = []
        var seen = Set<String>()
        for id in featured + Self.curated where CardDatabase.exists(id) && seen.insert(id).inserted {
            ids.append(id)
            if ids.count == count { break }
        }
        return ids.enumerated().map { Spryte(index: $0.offset, total: max(ids.count, 1), cardId: $0.element) }
    }

    /// A hand-picked spread across all five sets and every element, so the default
    /// parade shows the game's range before a player has collected anything.
    static let curated: [String] = [
        "S1-047", "S1-012", "S1-031",
        "S2-044", "S2-008", "S2-025",
        "S3-050", "S3-017", "S3-033",
        "S4-021", "S4-006", "S4-040",
        "S5-049", "S5-014", "S5-028",
    ]
}

// MARK: - One drifting Spryte

/// Constant per-Spryte motion parameters, derived once from a deterministic seed
/// so the layout is stable frame to frame.
private struct Spryte: Identifiable {
    let id: Int
    let cardId: String
    let laneX: Double        // 0…1 horizontal home position
    let size: Double         // tile edge in points
    let period: Double       // seconds for one bottom→top loop
    let phase: Double        // 0…1 offset into the loop, so they don't march in step
    let swayAmp: Double      // px of horizontal sway
    let swayFreq: Double     // sway cycles per second
    let spin: Double         // peak rotation in degrees
    let depth: Double        // 0 (near) … 1 (far): dims and softens the far ones

    init(index: Int, total: Int, cardId: String) {
        self.id = index
        self.cardId = cardId
        var rng = SplitMix64(0xACE1 &+ UInt64(index) &* 0x9E37_79B9)
        // Spread lanes evenly, then jitter, so they don't clump or line up.
        self.laneX = (Double(index) + 0.5) / Double(total) + (rng.unit() - 0.5) * 0.14
        self.depth = rng.unit()
        self.size = 46 + (1 - depth) * 52          // near ones larger
        self.period = 15 + rng.unit() * 12         // 15–27s, slow
        self.phase = rng.unit()
        self.swayAmp = 8 + rng.unit() * 20
        self.swayFreq = 0.04 + rng.unit() * 0.06
        self.spin = (rng.unit() * 2 - 1) * 9
        _ = rng.unit()
    }
}

/// Renders a single Spryte at its time-derived position: rising, swaying, spinning
/// and fading in at the bottom / out at the top so it loops without a hard seam.
private struct FloatingSpryte: View {
    let spryte: Spryte
    let time: Double
    let canvas: CGSize

    private var element: Element { CardDatabase.card(spryte.cardId)?.element ?? .shadow }

    var body: some View {
        let loop = ((time / spryte.period) + spryte.phase).truncatingRemainder(dividingBy: 1)
        // Travel from just below the screen to just above it.
        let y = canvas.height * (1.15 - loop * 1.30)
        let sway = sin(time * spryte.swayFreq * 2 * .pi + Double(spryte.id)) * spryte.swayAmp
        let x = canvas.width * spryte.laneX + sway
        let angle = sin(time * spryte.swayFreq * .pi + Double(spryte.id) * 1.3) * spryte.spin
        // Fade in over the first 12% of the climb and out over the last 12%.
        let edge = min(loop, 1 - loop) / 0.12
        let fade = max(0, min(1, edge))
        let baseOpacity = 0.5 + (1 - spryte.depth) * 0.4

        tile
            .frame(width: spryte.size, height: spryte.size)
            .rotationEffect(.degrees(angle))
            .position(x: x, y: y)
            .opacity(fade * baseOpacity)
            .blur(radius: spryte.depth * 1.6)
    }

    private var tile: some View {
        let corner = spryte.size * 0.26
        return RoundedRectangle(cornerRadius: corner)
            .fill(element.artGradient)
            .overlay {
                if UIImage(named: spryte.cardId) != nil {
                    Image(spryte.cardId)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                } else {
                    SigilView(seed: spryte.cardId, element: element)
                        .padding(spryte.size * 0.12)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: corner))
            .overlay(
                RoundedRectangle(cornerRadius: corner)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: element.palette[1].opacity(0.45), radius: spryte.size * 0.18, y: 2)
    }
}
