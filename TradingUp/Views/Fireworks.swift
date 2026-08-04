import SwiftUI

/// A continuous fireworks show rendered in a single `Canvas`. Shells launch from
/// the bottom, arc up to an apex, and burst into a gravity-fed spray of sparks
/// that fade. Like `ParticleBurst`, the whole thing is a pure function of elapsed
/// time — a fixed, seeded schedule of shells rendered against `Date()` — so it's
/// frame-stable, self-sustaining, and needs no timers or mutable per-frame state.
struct FireworksView: View {
    var palette: [Color]
    var seed: UInt64
    /// Scales how many shells are in the sky at once.
    var intensity: Double

    init(palette: [Color] = FireworksView.festive,
         seed: UInt64 = 0xF17E_2A9C_5B31_00D5,
         intensity: Double = 1.0) {
        self.palette = palette
        self.seed = seed
        self.intensity = intensity

        var rng = SplitMix64(seed)
        let n = max(4, Int(12 * intensity))
        var arr: [Shell] = []
        for i in 0..<n {
            arr.append(Shell(
                t0: (Double(i) + rng.unit()) / Double(n) * Self.period,
                originX: 0.1 + rng.unit() * 0.8,
                apexY: 0.16 + rng.unit() * 0.34,
                colorIndex: Int(rng.unit() * Double(palette.count)) % palette.count,
                count: 22 + Int(rng.unit() * 22),
                spread: 0.15 + rng.unit() * 0.13,
                burstSeed: rng.next()
            ))
        }
        shells = arr
    }

    static let festive: [Color] = [
        Color(hex: "ffd54a"), Color(hex: "ff8ad6"), Color(hex: "b06cf7"),
        Color(hex: "5be08a"), Color(hex: "3b82f6"), .white,
    ]

    // A shell fully rises then bursts within `period`, and the schedule is read
    // modulo `period`, so bursts crossing the loop boundary still render — the
    // show is seamless with no visible seam or lull.
    private static let period: Double = 6.3
    private static let rise: Double = 0.85
    private static let burst: Double = 1.3

    private struct Shell {
        let t0: Double
        let originX: Double     // 0…1 of width
        let apexY: Double       // 0…1 of height
        let colorIndex: Int
        let count: Int
        let spread: Double      // burst radius as a fraction of the min dimension
        let burstSeed: UInt64
    }

    private let shells: [Shell]
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                ctx.blendMode = .plusLighter        // sparks glow against the dark sky
                let loop = tl.date.timeIntervalSince(start)
                    .truncatingRemainder(dividingBy: Self.period)
                let life = Self.rise + Self.burst
                for shell in shells {
                    var age = loop - shell.t0
                    if age < 0 { age += Self.period }
                    guard age <= life else { continue }
                    let apex = CGPoint(x: size.width * shell.originX,
                                       y: size.height * shell.apexY)
                    if age < Self.rise {
                        drawRise(&ctx, size: size, shell: shell, apex: apex, p: age / Self.rise)
                    } else {
                        drawBurst(&ctx, size: size, shell: shell, apex: apex,
                                  p: (age - Self.rise) / Self.burst)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: Phases

    /// The climbing shell: a bright head decelerating toward its apex, trailing
    /// a short comet tail. Fades out just as it reaches the top, handing off to
    /// the burst.
    private func drawRise(_ ctx: inout GraphicsContext, size: CGSize, shell: Shell,
                          apex: CGPoint, p: Double) {
        let color = palette[shell.colorIndex]
        let y0 = size.height * 1.03
        func y(at prog: Double) -> CGFloat {
            let eased = 1 - pow(1 - max(0, prog), 2)          // decelerate near apex
            return y0 + (apex.y - y0) * CGFloat(eased)
        }
        let headAlpha = pow(1 - p, 0.6)                        // dim as it arrives
        for k in 0..<6 {
            let tp = p - Double(k) * 0.05
            guard tp >= 0 else { continue }
            let sz = CGFloat(2.6 - Double(k) * 0.35) * (size.width / 390)
            guard sz > 0 else { continue }
            let a = headAlpha * pow(0.62, Double(k))
            let pt = CGPoint(x: apex.x, y: y(at: tp))
            let rect = CGRect(x: pt.x - sz, y: pt.y - sz, width: sz * 2, height: sz * 2)
            ctx.opacity = a
            ctx.fill(Path(ellipseIn: rect), with: .color(k == 0 ? .white : color))
        }
    }

    /// The burst: sparks fly outward from the apex, arc down under gravity, and
    /// fade. A quick central flash sells the detonation.
    private func drawBurst(_ ctx: inout GraphicsContext, size: CGSize, shell: Shell,
                           apex: CGPoint, p: Double) {
        let color = palette[shell.colorIndex]
        let unit = size.width / 390
        let maxR = min(size.width, size.height) * CGFloat(shell.spread)
        let ease = 1 - pow(1 - p, 3)
        let gravity = size.height * 0.11 * CGFloat(p * p)

        // Detonation flash.
        if p < 0.16 {
            let fa = (1 - p / 0.16)
            let fr = maxR * 0.5 * CGFloat(0.4 + p * 3)
            ctx.opacity = fa * 0.9
            ctx.fill(Path(ellipseIn: CGRect(x: apex.x - fr, y: apex.y - fr,
                                            width: fr * 2, height: fr * 2)),
                     with: .color(.white))
        }

        var rng = SplitMix64(shell.burstSeed)
        for _ in 0..<shell.count {
            let ang = rng.unit() * 2 * .pi
            let spd = 0.45 + rng.unit() * 0.55
            let plife = 0.7 + rng.unit() * 0.3
            let psz = CGFloat(1.6 + rng.unit() * 2.6) * unit
            let isStar = rng.unit() < 0.4
            let lp = p / plife
            if lp >= 1 { continue }
            let dist = maxR * CGFloat(spd) * CGFloat(ease)
            let x = apex.x + CGFloat(cos(ang)) * dist
            let y = apex.y + CGFloat(sin(ang)) * dist + gravity
            let alpha = pow(1 - lp, 1.3)
            let rect = CGRect(x: x - psz, y: y - psz, width: psz * 2, height: psz * 2)
            ctx.opacity = alpha
            let tint = rng.unit() < 0.22 ? Color.white : color
            if isStar {
                ctx.fill(ParticleBurst.starPath(in: rect), with: .color(tint))
            } else {
                ctx.fill(Path(ellipseIn: rect), with: .color(tint))
            }
        }
    }
}
