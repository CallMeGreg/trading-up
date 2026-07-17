import SwiftUI

/// Deterministic 32-bit RNG — exact port of the mockup's `mulberry32`,
/// so the app reproduces the same emblem the mockups previewed.
private struct Mulberry32 {
    var a: UInt32
    mutating func next() -> Double {
        a = a &+ 0x6D2B79F5
        var t = (a ^ (a >> 15)) &* (1 | a)
        t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
        return Double(t ^ (t >> 14)) / 4294967296.0
    }
}

/// FNV-1a hash over UTF-16 code units — matches the mockup's `hashStr`.
private func fnv1a(_ s: String) -> UInt32 {
    var h: UInt32 = 2166136261
    for u in s.utf16 {
        h ^= UInt32(u)
        h = h &* 16777619
    }
    return h
}

/// Symmetric mandala/crest emblem, drawn deterministically from `seed`.
/// Mirrors `makeSigil(name+type, type)` in design/mockups/cards.js.
struct SigilView: View {
    let seed: String
    let element: Element

    var body: some View {
        Canvas { context, size in
            let pal = element.palette
            var rnd = Mulberry32(a: fnv1a(seed))

            let side = min(size.width, size.height)
            let ox = (size.width - side) / 2
            let oy = (size.height - side) / 2
            let unit = side / 100.0
            func P(_ x: Double, _ y: Double) -> CGPoint {
                CGPoint(x: ox + x / 100.0 * side, y: oy + y / 100.0 * side)
            }
            func dot(_ center: CGPoint, _ r: Double, _ color: Color) {
                let rr = r * unit
                context.fill(
                    Path(ellipseIn: CGRect(x: center.x - rr, y: center.y - rr, width: rr * 2, height: rr * 2)),
                    with: .color(color)
                )
            }

            let arms = 5 + Int(rnd.next() * 4)          // 5..8
            let ringCount = 2 + Int(rnd.next() * 3)     // 2..4
            let rot = rnd.next() * 360.0

            // Concentric rings
            for i in 0..<ringCount {
                let r = 12.0 + Double(i) * (32.0 / Double(ringCount))
                let c = P(50, 50)
                let rr = r * unit
                let ring = Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2))
                context.stroke(
                    ring,
                    with: .color(pal[i % pal.count].opacity(0.45)),
                    lineWidth: (1.0 + rnd.next() * 1.4) * unit
                )
            }

            // Radial arms with tip gems
            let d2r = Double.pi / 180.0
            for i in 0..<arms {
                let a = (rot + Double(i) * (360.0 / Double(arms))) * d2r
                let perp = a + .pi / 2
                let x1 = 50 + cos(a) * 13, y1 = 50 + sin(a) * 13
                let x2 = 50 + cos(a) * (36 + rnd.next() * 8)
                let y2 = 50 + sin(a) * (36 + rnd.next() * 8)
                let w = 3.5 + rnd.next() * 3
                let bx1 = x1 + cos(perp) * w, by1 = y1 + sin(perp) * w
                let bx2 = x1 - cos(perp) * w, by2 = y1 - sin(perp) * w

                var arm = Path()
                arm.move(to: P(bx1, by1))
                arm.addLine(to: P(bx2, by2))
                arm.addLine(to: P(x2, y2))
                arm.closeSubpath()
                context.fill(arm, with: .color(pal[1].opacity(0.8)))
                dot(P(x2, y2), 1.8 + rnd.next() * 2, pal[0])
            }

            // Center polygon + core
            let sides = 3 + Int(rnd.next() * 4)
            var poly = Path()
            for i in 0..<sides {
                let a = (rot + Double(i) * (360.0 / Double(sides))) * d2r
                let pt = P(50 + cos(a) * 11, 50 + sin(a) * 11)
                if i == 0 { poly.move(to: pt) } else { poly.addLine(to: pt) }
            }
            poly.closeSubpath()
            context.fill(poly, with: .color(pal[2]))
            context.stroke(poly, with: .color(.white.opacity(0.55)), lineWidth: unit)
            dot(P(50, 50), 3, .white.opacity(0.85))
        }
    }
}
