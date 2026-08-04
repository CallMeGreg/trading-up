import SwiftUI

// MARK: - Design-space helpers
//
// Every set scene is drawn in a 100 x 100 box with y running down, then scaled
// to whatever the caller asked for. One set of coordinates therefore serves the
// 280pt hero on the reveal screen and the 34pt chip in a list. Nothing is
// clipped, so each scene keeps its own silhouette on the wrapper: masses that
// reach the edge of the box fade out instead of being cut off.

private func P(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

private func poly(_ pts: [(Double, Double)], closed: Bool = true) -> Path {
    var p = Path()
    guard let first = pts.first else { return p }
    p.move(to: P(first.0, first.1))
    for pt in pts.dropFirst() { p.addLine(to: P(pt.0, pt.1)) }
    if closed { p.closeSubpath() }
    return p
}

private func ell(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double) -> Path {
    Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
}

private func dot(_ cx: Double, _ cy: Double, _ r: Double) -> Path { ell(cx, cy, r, r) }

/// Overlapping ellipses filled as one non-zero path — a cheap union that builds
/// organic masses (canopy, thunderhead, ash plume, mist) out of simple parts.
private func blob(_ parts: [(Double, Double, Double, Double)]) -> Path {
    var p = Path()
    for (cx, cy, rx, ry) in parts {
        p.addEllipse(in: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
    }
    return p
}

private func vShade(_ colors: [Color], _ y0: Double, _ y1: Double) -> GraphicsContext.Shading {
    .linearGradient(Gradient(colors: colors), startPoint: P(50, y0), endPoint: P(50, y1))
}

private func aShade(_ colors: [Color], _ from: CGPoint, _ to: CGPoint) -> GraphicsContext.Shading {
    .linearGradient(Gradient(colors: colors), startPoint: from, endPoint: to)
}

private func rShade(_ colors: [Color], _ centre: CGPoint, _ r0: Double, _ r1: Double) -> GraphicsContext.Shading {
    .radialGradient(Gradient(colors: colors), center: centre, startRadius: r0, endRadius: r1)
}

/// Left-to-right shading that fades out at both ends, so a ground layer can run
/// wide without cutting a hard vertical edge into the wrapper behind it.
private func band(_ edge: Color, _ centre: Color) -> GraphicsContext.Shading {
    .linearGradient(
        Gradient(stops: [.init(color: edge.opacity(0), location: 0),
                         .init(color: edge, location: 0.2),
                         .init(color: centre, location: 0.5),
                         .init(color: edge, location: 0.8),
                         .init(color: edge.opacity(0), location: 1)]),
        startPoint: P(0, 50), endPoint: P(100, 50)
    )
}

/// Interpolates two hex colours. Used to haze a scene's elements back by depth.
/// `Color.mixed` can't do this job here: it is UIKit-only, and these scenes also
/// have to render the same way in the macOS preview harness.
private func blend(_ from: String, _ to: String, _ t: Double) -> Color {
    func rgb(_ hex: String) -> (Double, Double, Double) {
        var v: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&v)
        return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }
    let a = rgb(from), b = rgb(to), k = max(0, min(1, t))
    return Color(red: a.0 + (b.0 - a.0) * k,
                 green: a.1 + (b.1 - a.1) * k,
                 blue: a.2 + (b.2 - a.2) * k)
}

private func stroked(_ ctx: inout GraphicsContext, _ path: Path, _ color: Color, _ width: Double) {    ctx.stroke(path, with: .color(color),
               style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
}

/// Draws `body` through a blur, for glows and soft masses. The radius is in
/// design units, so it scales with the badge like everything else.
private func glow(_ ctx: inout GraphicsContext, _ radius: Double,
                  _ body: (inout GraphicsContext) -> Void) {
    ctx.drawLayer { layer in
        layer.addFilter(.blur(radius: radius))
        body(&layer)
    }
}

/// A mass plus the soft halo that keeps its edge from reading as a cut-out.
private func softFill(_ ctx: inout GraphicsContext, _ path: Path,
                      _ shading: GraphicsContext.Shading, halo: Color, radius: Double) {
    glow(&ctx, radius) { g in g.fill(path, with: .color(halo)) }
    ctx.fill(path, with: shading)
}

// MARK: - Set emblem

/// The artwork stamped on a booster pack. Each set gets its *own* illustration —
/// a small landscape of the region it is named after — instead of one shared
/// emblem in five colourways:
///
/// - **Emberfall** — an erupting cone over a lava lake, ringed by dead peaks.
/// - **Tidecaller** — two small islands under a breaking wave and heavy swell.
/// - **Verdspire** — a stand of mossy jungle trees with light coming through.
/// - **Voltcrest** — a thunderhead forking lightning into a ridge line.
/// - **Umbral Reach** — an eclipse over dead trees, with spirits drifting up.
///
/// Everything is drawn in a 100 x 100 space and scaled, and the fussier details
/// (embers, spray, pollen, rain, spirit dust) drop out below ~64pt so a shop
/// thumbnail stays legible instead of turning to noise.
struct SetEmblem: View {
    let set: Int

    var body: some View {
        Canvas { ctx, size in
            let side = min(size.width, size.height)
            guard side > 3 else { return }
            ctx.translateBy(x: (size.width - side) / 2, y: (size.height - side) / 2)
            ctx.scaleBy(x: side / 100, y: side / 100)
            SetScene.draw(set: set, into: &ctx, fine: side >= 64)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Scenes

enum SetScene {
    static func draw(set: Int, into ctx: inout GraphicsContext, fine: Bool) {
        switch set {
        case 1: emberfall(&ctx, fine)
        case 2: tidecaller(&ctx, fine)
        case 3: verdspire(&ctx, fine)
        case 4: voltcrest(&ctx, fine)
        default: umbralReach(&ctx, fine)
        }
    }

    /// The soft dark wash every scene sits on, so the illustration reads against
    /// a bright foil wrapper instead of dissolving into it. It fades to nothing
    /// well inside the box, which is what keeps the badge edgeless.
    private static func nightWash(_ ctx: inout GraphicsContext, _ color: Color, _ centre: CGPoint) {
        ctx.fill(ell(50, 50, 50, 50),
                 with: rShade([color.opacity(0.94), color.opacity(0.9), color.opacity(0.62), color.opacity(0)],
                              centre, 4, 50))
    }

    // MARK: Emberfall — volcano, magma, rock

    private static func emberfall(_ ctx: inout GraphicsContext, _ fine: Bool) {
        nightWash(&ctx, Color(hex: "1a0603"), P(50, 44))

        // Heat thrown off the caldera and the lake below it.
        ctx.fill(ell(50, 70, 44, 40),
                 with: rShade([Color(hex: "ff7a1a").opacity(0.5), Color(hex: "ff5a0f").opacity(0.16),
                               Color(hex: "ff5a0f").opacity(0)], P(50, 76), 2, 40))

        // Dead peaks standing behind the cone, hazed by the ash in the air.
        ctx.fill(poly([(12, 86), (21, 54), (28, 64), (35, 52), (44, 86)]),
                 with: vShade([Color(hex: "5e2411"), Color(hex: "2b0d08")], 50, 88))
        ctx.fill(poly([(58, 86), (68, 50), (75, 61), (81, 55), (90, 86)]),
                 with: vShade([Color(hex: "6b2a12"), Color(hex: "2b0d08")], 48, 88))

        // The cone: concave flanks, a snapped-off rim with a notch in it.
        var cone = Path()
        cone.move(to: P(15, 87))
        cone.addQuadCurve(to: P(41, 30), control: P(30, 62))
        cone.addLine(to: P(48, 35))
        cone.addLine(to: P(57, 27))
        cone.addQuadCurve(to: P(85, 87), control: P(70, 60))
        cone.closeSubpath()
        ctx.fill(cone, with: vShade([Color(hex: "5a2110"), Color(hex: "24090a")], 28, 90))

        // Rim light down both flanks, so the mountain keeps its shape against
        // the glow it is throwing.
        var leftEdge = Path()
        leftEdge.move(to: P(15, 87))
        leftEdge.addQuadCurve(to: P(41, 30), control: P(30, 62))
        stroked(&ctx, leftEdge, Color(hex: "ff9a4a").opacity(0.5), 1.1)
        var rightEdge = Path()
        rightEdge.move(to: P(57, 27))
        rightEdge.addQuadCurve(to: P(85, 87), control: P(70, 60))
        stroked(&ctx, rightEdge, Color(hex: "ff7a1a").opacity(0.35), 1.0)
        stroked(&ctx, poly([(41, 30), (48, 35), (57, 27)], closed: false),
                Color(hex: "ffb24d").opacity(0.65), 1.0)

        // The flank the flows are lighting up.
        var lit = Path()
        lit.move(to: P(15, 87))
        lit.addQuadCurve(to: P(41, 30), control: P(30, 62))
        lit.addLine(to: P(44, 33))
        lit.addLine(to: P(26, 87))
        lit.closeSubpath()
        ctx.fill(lit, with: vShade([Color(hex: "8a3a19").opacity(0.55), Color(hex: "3a1009").opacity(0.05)], 32, 86))

        // Broken rock faces.
        let facets: [[(Double, Double)]] = [
            [(33, 56), (39, 46), (37, 60)], [(62, 66), (69, 78), (59, 72)],
            [(50, 46), (56, 55), (47, 57)], [(24, 76), (31, 68), (30, 82)]]
        for f in facets { ctx.fill(poly(f), with: .color(.black.opacity(0.28))) }

        // Ash plume: a column out of the vent boiling up into a head of smoke.
        var column = Path()
        column.move(to: P(45, 32))
        column.addQuadCurve(to: P(37, 15), control: P(40, 24))
        column.addLine(to: P(68, 13))
        column.addQuadCurve(to: P(55, 31), control: P(61, 21))
        column.closeSubpath()
        glow(&ctx, 2.6) { g in
            g.fill(column, with: .color(Color(hex: "4a2418").opacity(0.85)))
        }
        glow(&ctx, 1.6) { g in
            g.fill(blob([(53, 14, 15, 8), (39, 12, 10, 6), (69, 10, 12, 6.5), (58, 4, 13, 5.5), (77, 16, 8, 5)]),
                   with: vShade([Color(hex: "5b3226").opacity(0.8), Color(hex: "24100a").opacity(0.95)], 0, 26))
            g.fill(blob([(46, 9, 8, 4), (62, 5, 7, 3.4)]),
                   with: .color(Color(hex: "7a4a36").opacity(0.35)))
        }
        glow(&ctx, 3.4) { g in
            g.fill(ell(50, 22, 11, 4.5), with: .color(Color(hex: "ff7a1a").opacity(0.5)))
        }

        // Vent, and the fountain coming out of it.
        glow(&ctx, 3.0) { g in
            g.fill(ell(49, 31, 9, 4.5), with: .color(Color(hex: "ff6a1a").opacity(0.95)))
        }
        let jets: [(Double, Double, Double)] = [(-4, 30, 9), (0, 33, 14), (4, 30, 10)]
        for (dx, base, h) in jets {
            var jet = Path()
            jet.move(to: P(49 + dx, base))
            jet.addQuadCurve(to: P(49 + dx * 2.2, base - h), control: P(49 + dx * 1.3, base - h * 0.7))
            stroked(&ctx, jet, Color(hex: "ffd15c").opacity(0.9), 1.3)
        }
        ctx.fill(ell(49, 31.5, 6, 2.4),
                 with: rShade([Color(hex: "fff0b0"), Color(hex: "ff8a1a")], P(49, 31.5), 0, 7))

        // Magma running down the flanks into the lake, hugging the slopes so the
        // cone keeps reading as rock rather than a fountain.
        let flows: [([(Double, Double)], Double)] = [
            ([(44, 34), (36, 48), (30, 60), (26, 72), (23, 84)], 1.4),
            ([(55, 31), (63, 45), (66, 58), (71, 70), (73, 84)], 1.2),
            ([(47, 36), (43, 52), (46, 66), (42, 80)], 0.9)]
        for (pts, w) in flows {
            var flow = Path()
            flow.move(to: P(pts[0].0, pts[0].1))
            for i in 1..<pts.count {
                let prev = pts[i - 1], cur = pts[i]
                flow.addQuadCurve(to: P(cur.0, cur.1),
                                  control: P(prev.0 + (cur.0 - prev.0) * 0.9, (prev.1 + cur.1) / 2))
            }
            glow(&ctx, 2.2) { g in
                g.stroke(flow, with: .color(Color(hex: "ff5a0f").opacity(0.75)),
                         style: StrokeStyle(lineWidth: w * 3, lineCap: .round, lineJoin: .round))
            }
            stroked(&ctx, flow, Color(hex: "ffd15c"), w)
        }

        // The lake itself: a molten pool with its own bloom.
        softFill(&ctx, ell(50, 88, 39, 8.5),
                 band(Color(hex: "d8480a"), Color(hex: "ffb24d")),
                 halo: Color(hex: "ff6a1a").opacity(0.55), radius: 5)
        var crestLine = Path()
        crestLine.move(to: P(16, 84))
        crestLine.addQuadCurve(to: P(52, 82.5), control: P(34, 81))
        crestLine.addQuadCurve(to: P(84, 85), control: P(68, 85.5))
        stroked(&ctx, crestLine, Color(hex: "fff0b0").opacity(0.5), 1.2)

        // Cooled crust floating on it.
        let crust: [[(Double, Double)]] = [
            [(20, 90), (26, 86), (33, 88), (29, 92), (22, 92)],
            [(60, 87), (68, 85), (74, 89), (65, 91)],
            [(41, 93), (48, 90), (55, 94), (46, 95)]]
        for r in crust { ctx.fill(poly(r), with: .color(Color(hex: "220806").opacity(0.85))) }

        guard fine else { return }

        // Embers, and lava bombs still arcing out of the vent.
        let embers: [(Double, Double, Double, Double)] = [
            (19, 44, 1.3, 0.8), (80, 38, 1.5, 0.75), (28, 62, 1.0, 0.65), (86, 58, 1.2, 0.65),
            (14, 70, 0.9, 0.55), (67, 22, 1.4, 0.85), (31, 20, 1.1, 0.75), (73, 42, 0.9, 0.55),
            (24, 34, 1.0, 0.6), (90, 72, 1.0, 0.5)]
        for (x, y, r, o) in embers {
            glow(&ctx, 1.6) { g in
                g.fill(dot(x, y, r * 2), with: .color(Color(hex: "ff8a1a").opacity(o * 0.65)))
            }
            ctx.fill(dot(x, y, r), with: .color(Color(hex: "ffe6a0").opacity(o)))
        }
        for (a, b) in [((69.0, 19.0), (77.0, 33.0)), ((29.0, 17.0), (21.0, 30.0))] {
            stroked(&ctx, poly([a, b], closed: false), Color(hex: "ff8a1a").opacity(0.4), 0.9)
        }
    }

    // MARK: Tidecaller — small islands, massive swells

    private static func tidecaller(_ ctx: inout GraphicsContext, _ fine: Bool) {
        nightWash(&ctx, Color(hex: "04142f"), P(44, 40))

        // Moon over the horizon.
        glow(&ctx, 4.0) { g in
            g.fill(dot(22, 18, 10), with: .color(Color(hex: "9fe8ff").opacity(0.3)))
        }
        ctx.fill(dot(22, 17, 6),
                 with: rShade([Color(hex: "eafaff"), Color(hex: "8fd6f5").opacity(0.8)], P(20, 15), 0, 7))
        if fine {
            for (x, y, w) in [(30.0, 22.0, 13.0), (12.0, 27.0, 9.0)] {
                var cloud = Path()
                cloud.move(to: P(x - w / 2, y))
                cloud.addQuadCurve(to: P(x + w / 2, y - 1), control: P(x, y - 2.5))
                stroked(&ctx, cloud, Color(hex: "9fe8ff").opacity(0.35), 1.1)
            }
        }

        // Open water: a lens of sea, fading out at both ends.
        softFill(&ctx, ell(50, 80, 46, 18),
                 band(Color(hex: "05204d"), Color(hex: "0d3d81")),
                 halo: Color(hex: "0a2a66").opacity(0.6), radius: 5)

        // Distant swells rolling in.
        for (y, o) in [(66.0, 0.4), (71.0, 0.3)] {
            var s = Path()
            s.move(to: P(8, y))
            s.addQuadCurve(to: P(30, y - 2), control: P(19, y - 3.4))
            s.addQuadCurve(to: P(52, y), control: P(41, y + 1.6))
            s.addQuadCurve(to: P(76, y - 1.6), control: P(64, y - 3))
            stroked(&ctx, s, Color(hex: "9fe8ff").opacity(o), 1.1)
        }

        // A swell rearing up on the left…
        var swell = Path()
        swell.move(to: P(4, 76))
        swell.addCurve(to: P(16, 52), control1: P(6, 66), control2: P(8, 54))
        swell.addCurve(to: P(29, 68), control1: P(24, 52), control2: P(26, 60))
        swell.addCurve(to: P(33, 80), control1: P(31, 72), control2: P(32, 76))
        swell.closeSubpath()
        ctx.fill(swell, with: aShade([Color(hex: "2f8fe6"), Color(hex: "12468f"), Color(hex: "07254f")],
                                     P(12, 52), P(22, 82)))
        var swellLip = Path()
        swellLip.move(to: P(7, 62))
        swellLip.addCurve(to: P(16, 52), control1: P(9, 56), control2: P(11, 52))
        swellLip.addCurve(to: P(27, 65), control1: P(22, 52), control2: P(25, 58))
        stroked(&ctx, swellLip, .white.opacity(0.75), 1.8)

        // …two small islands riding it out in the middle…
        island(&ctx, x: 30, base: 71, w: 11, h: 8.5, palm: true, fine: fine)
        island(&ctx, x: 50, base: 68, w: 5.5, h: 4.0, palm: false, fine: fine)

        // …and the big one, throwing its lip clean over them. The gap between
        // the underside of the lip and the face is the open barrel.
        var wave = Path()
        wave.move(to: P(96, 78))
        wave.addCurve(to: P(74, 26), control1: P(97, 52), control2: P(88, 30))
        wave.addCurve(to: P(36, 45), control1: P(60, 21), control2: P(44, 32))
        wave.addCurve(to: P(64, 43), control1: P(45, 52), control2: P(55, 49))
        wave.addCurve(to: P(78, 64), control1: P(73, 46), control2: P(77, 54))
        wave.addCurve(to: P(96, 78), control1: P(82, 72), control2: P(90, 76))
        wave.closeSubpath()
        ctx.fill(wave, with: aShade([Color(hex: "6ccbfa"), Color(hex: "1e5bd6"), Color(hex: "06214f")],
                                    P(72, 26), P(92, 80)))

        // Light coming through the thin shoulder of the curl.
        var pane = Path()
        pane.move(to: P(74, 27))
        pane.addCurve(to: P(40, 44), control1: P(61, 23), control2: P(47, 33))
        pane.addCurve(to: P(76, 37), control1: P(50, 39), control2: P(65, 31))
        pane.closeSubpath()
        ctx.fill(pane, with: .color(Color(hex: "9fe8ff").opacity(0.32)))

        // The mouth of the barrel: dark inside, with a lit rim on the face.
        var barrel = Path()
        barrel.move(to: P(63, 43))
        barrel.addCurve(to: P(79, 64), control1: P(72, 46), control2: P(77, 54))
        barrel.addCurve(to: P(63, 47), control1: P(72, 56), control2: P(68, 49))
        barrel.closeSubpath()
        ctx.fill(barrel, with: .color(Color(hex: "04182f").opacity(0.6)))
        stroked(&ctx, poly([(64, 44), (73, 50), (78, 62)], closed: false), .white.opacity(0.4), 1.0)

        // Foam along the crest and out to the tip of the lip.
        var lip = Path()
        lip.move(to: P(92, 52))
        lip.addCurve(to: P(74, 26), control1: P(92, 36), control2: P(86, 29))
        lip.addCurve(to: P(36, 45), control1: P(60, 21), control2: P(44, 32))
        glow(&ctx, 2.2) { g in
            g.stroke(lip, with: .color(.white.opacity(0.4)),
                     style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
        }
        stroked(&ctx, lip, .white.opacity(0.9), 1.7)
        ctx.fill(blob([(37, 45, 3.4, 2.8), (44, 39, 2.8, 2.3), (52, 33, 2.4, 1.9), (62, 27, 2.4, 1.9), (73, 26, 2.6, 2)]),
                 with: .color(.white.opacity(0.9)))

        // Water spilling off the tip, and the churn where it lands.
        for (x, y0, y1, w) in [(36.0, 47.0, 58.0, 1.3), (40.0, 46.0, 54.0, 0.9)] {
            var fall = Path()
            fall.move(to: P(x, y0))
            fall.addQuadCurve(to: P(x - 2, y1), control: P(x - 0.5, (y0 + y1) / 2))
            stroked(&ctx, fall, .white.opacity(0.35), w)
        }
        ctx.fill(blob([(35, 61, 4.5, 1.8), (41, 63, 3.2, 1.4)]), with: .color(.white.opacity(0.32)))

        // Contours across the face, so the wall of water has some bulk to it.
        for (pts, o) in [([(78.0, 30.0), (84.0, 44.0), (82.0, 60.0)], 0.22),
                         ([(88.0, 40.0), (91.0, 54.0), (88.0, 68.0)], 0.16)] {
            var c = Path()
            c.move(to: P(pts[0].0, pts[0].1))
            c.addQuadCurve(to: P(pts[2].0, pts[2].1), control: P(pts[1].0, pts[1].1))
            stroked(&ctx, c, Color(hex: "9fe8ff").opacity(o), 1.2)
        }

        // Whitewater on the face, and the churn where it lands.
        let streaks: [([(Double, Double)], Double)] = [
            ([(76, 34), (78, 48), (73, 64), (68, 78)], 0.3),
            ([(86, 40), (88, 54), (83, 72)], 0.22)]
        for (pts, o) in streaks {
            stroked(&ctx, poly(pts, closed: false), .white.opacity(o), 1.3)
        }
        ctx.fill(blob([(68, 84, 7, 2.6), (79, 87, 6, 2.2), (58, 87, 5, 2)]),
                 with: .color(.white.opacity(0.35)))

        guard fine else { return }

        // Spray torn off the crest.
        let spray: [(Double, Double, Double, Double)] = [
            (34, 32, 1.4, 0.8), (28, 26, 1.0, 0.65), (42, 25, 1.2, 0.7), (51, 18, 1.0, 0.6),
            (22, 37, 0.9, 0.5), (60, 14, 1.1, 0.55), (70, 12, 0.9, 0.45), (82, 18, 1.2, 0.5)]
        for (x, y, r, o) in spray {
            ctx.fill(dot(x, y, r), with: .color(.white.opacity(o)))
        }
    }

    /// One small island: a dark hump, a rim of surf, and optionally a lone palm.
    private static func island(_ ctx: inout GraphicsContext, x: Double, base: Double,
                               w: Double, h: Double, palm: Bool, fine: Bool) {
        var hump = Path()
        hump.move(to: P(x - w, base))
        hump.addQuadCurve(to: P(x - w * 0.15, base - h), control: P(x - w * 0.62, base - h * 0.98))
        hump.addQuadCurve(to: P(x + w, base), control: P(x + w * 0.55, base - h * 0.5))
        hump.closeSubpath()
        ctx.fill(hump, with: vShade([Color(hex: "2b6ea8"), Color(hex: "0a2a52")], base - h, base))
        stroked(&ctx, poly([(x - w * 0.9, base - h * 0.55), (x - w * 0.2, base - h * 0.95)], closed: false),
                Color(hex: "6fb6e8").opacity(0.5), 0.9)
        var surf = Path()
        surf.move(to: P(x - w - 2, base + 0.8))
        surf.addQuadCurve(to: P(x + w + 2, base + 0.8), control: P(x, base + 2.2))
        stroked(&ctx, surf, .white.opacity(0.5), 1.0)

        guard palm else { return }
        var trunkPath = Path()
        trunkPath.move(to: P(x - w * 0.12, base - h * 0.8))
        trunkPath.addQuadCurve(to: P(x + w * 0.18, base - h * 2.2), control: P(x - w * 0.24, base - h * 1.6))
        stroked(&ctx, trunkPath, Color(hex: "123f6b"), 1.2)
        let top = P(x + w * 0.18, base - h * 2.2)
        for (dx, dy) in [(-4.6, -2.0), (-3.2, 1.4), (4.4, -1.8), (3.4, 1.6), (0.2, -3.4)] {
            var frond = Path()
            frond.move(to: top)
            frond.addQuadCurve(to: P(top.x + dx, top.y + dy),
                               control: P(top.x + dx * 0.5, top.y + dy - 1.6))
            stroked(&ctx, frond, Color(hex: "1a5480"), fine ? 1.1 : 1.5)
        }
    }

    // MARK: Verdspire — mossy jungle

    private static func verdspire(_ ctx: inout GraphicsContext, _ fine: Bool) {
        nightWash(&ctx, Color(hex: "051d0b"), P(50, 48))

        // A patch of daylight up behind the crowns. Kept high and narrow: the
        // floor has to stay dark or the trunks stop reading as silhouettes.
        ctx.fill(ell(50, 40, 40, 40),
                 with: rShade([Color(hex: "b6e88a").opacity(0.22), Color(hex: "2f9e44").opacity(0.07),
                               Color(hex: "07240f").opacity(0)], P(50, 26), 2, 40))

        // Back of the wood: a few hazed crowns, no detail, purely depth.
        let far: [(Double, Double, Double, Double)] = [
            (16, 78, 56, 6.5), (37, 77, 53, 5.4), (63, 77, 54, 5.8), (85, 78, 57, 6.2)]
        for (x, base, crownY, r) in far {
            tree(&ctx, x: x, base: base, crownY: crownY, r: r, depth: 0, fine: false)
        }

        // Light coming down through the gaps between the crowns.
        let beams: [(Double, Double, Double)] = [(37, 5, 22), (68, 4, 18)]
        for (x, w, spread) in beams {
            ctx.fill(poly([(x, 16), (x + w, 16), (x + w + spread, 90), (x - spread * 0.3, 90)]),
                     with: vShade([Color(hex: "eaffb0").opacity(0),
                                   Color(hex: "eaffb0").opacity(0.13),
                                   Color(hex: "eaffb0").opacity(0)], 16, 92))
        }

        // The stand itself: two mid trees, then the tall one in front of them.
        // Crown centres sit at three different heights, so the skyline stays
        // scalloped instead of flattening into a single band of leaves.
        tree(&ctx, x: 23, base: 85, crownY: 34, r: 12.5, depth: 0.5, fine: fine)
        tree(&ctx, x: 79, base: 85, crownY: 37, r: 11.5, depth: 0.45, fine: fine)
        tree(&ctx, x: 51, base: 88, crownY: 22, r: 15.0, depth: 1, fine: fine)

        // Vines hanging out of the crowns.
        let vines: [(Double, Double, Double, Double)] = [
            (36, 31, 60, 4), (65, 30, 64, -4), (12, 42, 62, 3.5), (90, 46, 66, -3)]
        for (x, y0, y1, sway) in vines {
            var vine = Path()
            vine.move(to: P(x, y0))
            vine.addQuadCurve(to: P(x + sway, y1), control: P(x + sway * 1.9, (y0 + y1) / 2))
            stroked(&ctx, vine, Color(hex: "1f6b30"), 1.1)
            guard fine else { continue }
            for t in [0.5, 0.75, 0.96] {
                let ly = y0 + (y1 - y0) * t
                let lx = x + sway * (t * 1.35)
                ctx.fill(ell(lx + 1.1, ly, 1.4, 0.8), with: .color(Color(hex: "5fd35f").opacity(0.8)))
            }
        }

        // Mossy forest floor.
        softFill(&ctx, ell(50, 89, 42, 9),
                 band(Color(hex: "0c3417"), Color(hex: "1c5f2b")),
                 halo: Color(hex: "0d3a1a").opacity(0.7), radius: 4)
        ctx.fill(blob([(30, 85, 11, 2.4), (60, 86, 10, 2.2), (80, 88, 8, 2), (17, 88, 8, 2)]),
                 with: .color(Color(hex: "3fae52").opacity(0.35)))

        // Undergrowth: ferns in the near corners, a mossy log, roots.
        fern(&ctx, x: 11, y: 91, s: 11, flip: false, fine: fine)
        fern(&ctx, x: 89, y: 92, s: 10, flip: true, fine: fine)
        fern(&ctx, x: 63, y: 88, s: 7, flip: true, fine: fine)
        ctx.fill(ell(35, 92, 9, 2.4), with: .color(Color(hex: "24401d")))
        ctx.fill(ell(35, 91, 9, 1.2), with: .color(Color(hex: "3c6b2a").opacity(0.8)))

        guard fine else { return }

        // Pollen drifting through the beams.
        let motes: [(Double, Double, Double, Double)] = [
            (33, 50, 1.3, 0.7), (66, 42, 1.1, 0.6), (44, 62, 1.0, 0.55), (74, 64, 1.2, 0.5),
            (18, 64, 0.9, 0.45), (40, 38, 0.9, 0.5), (85, 52, 1.0, 0.45), (28, 76, 0.9, 0.4)]
        for (x, y, r, o) in motes {
            glow(&ctx, 1.4) { g in
                g.fill(dot(x, y, r * 2), with: .color(Color(hex: "d9ff9a").opacity(o * 0.5)))
            }
            ctx.fill(dot(x, y, r), with: .color(Color(hex: "f6ffcf").opacity(o)))
        }
    }

    /// One tree: a tapered trunk, a fork of branches and a lobed crown. Crowns
    /// are built as a ring of unequal lobes with frond tips on the rim, and each
    /// one has its own trunk running down to the floor — which is what makes a
    /// stand of these read as a wood instead of a single green cloud.
    /// `depth` runs 0 (far back, hazed into the undergrowth) to 1 (front, lit).
    private static func tree(_ ctx: inout GraphicsContext, x: Double, base: Double,
                             crownY: Double, r: Double, depth: Double, fine: Bool) {
        let shell = blend("06240e", "093315", depth)
        let body = blend("11421d", "3fbb52", depth)
        let lit = blend("1e6129", "96f57e", depth)
        let bark = blend("0a2711", "48331a", depth)
        let barkDark = blend("051b0a", "171007", depth)

        // Trunk, flaring a little where it meets the floor.
        let w = r * 0.15 + 0.55
        var t = Path()
        t.move(to: P(x - w * 1.7, base))
        t.addQuadCurve(to: P(x - w * 0.45, crownY),
                       control: P(x - w * 0.85, base - (base - crownY) * 0.55))
        t.addLine(to: P(x + w * 0.45, crownY))
        t.addQuadCurve(to: P(x + w * 1.7, base),
                       control: P(x + w * 0.85, base - (base - crownY) * 0.55))
        t.closeSubpath()
        ctx.fill(t, with: aShade([bark, barkDark], P(x - w, crownY), P(x + w * 1.7, base)))

        // Branches forking up into the leaves.
        for side in [-1.0, 1.0] {
            var b = Path()
            b.move(to: P(x, crownY + r * 0.85))
            b.addQuadCurve(to: P(x + side * r * 0.6, crownY + r * 0.1),
                           control: P(x + side * r * 0.16, crownY + r * 0.55))
            stroked(&ctx, b, bark, max(0.7, w * 0.55))
        }

        // Crown: a core mass plus a ring of lobes of deliberately uneven size.
        let lobes: [(Double, Double, Double)] = [
            (-2.35, 0.78, 0.46), (-1.62, 0.66, 0.50), (-1.05, 0.80, 0.44), (-0.42, 0.80, 0.42),
            (0.24, 0.70, 0.44), (0.95, 0.58, 0.36), (1.75, 0.55, 0.34), (2.35, 0.74, 0.42),
            (2.95, 0.80, 0.44)]
        func crown(_ scale: Double, _ dx: Double, _ dy: Double) -> Path {
            var p = Path()
            p.addEllipse(in: CGRect(x: x + dx - r * 0.62 * scale, y: crownY + dy - r * 0.66 * scale,
                                    width: r * 1.24 * scale, height: r * 1.32 * scale))
            for (a, d, s) in lobes {
                let lx = x + dx + cos(a) * r * d * 0.9 * scale
                let ly = crownY + dy + sin(a) * r * d * scale
                p.addEllipse(in: CGRect(x: lx - r * s * scale, y: ly - r * s * 0.92 * scale,
                                        width: r * s * 2 * scale, height: r * s * 1.84 * scale))
            }
            return p
        }
        ctx.fill(crown(1, 0, 0), with: .color(shell))
        ctx.fill(crown(0.84, -r * 0.05, -r * 0.09), with: .color(body))
        ctx.fill(crown(0.46, -r * 0.16, -r * 0.26), with: .color(lit.opacity(0.5)))

        // Sun on the top-left leaves, which is what lifts a crown off a bright
        // wrapper — without it the tree sinks into the foil behind it.
        if depth > 0.25 {
            for (a, d) in [(-2.45, 0.82), (-1.72, 0.74), (-1.1, 0.84), (-0.55, 0.86)] {
                ctx.fill(ell(x + cos(a) * r * d * 0.9, crownY + sin(a) * r * d,
                             r * 0.26, r * 0.2),
                         with: .color(lit.opacity(0.55)))
            }
        }

        guard fine else { return }

        // Frond tips breaking the silhouette, so the edge reads as leaves.
        for (a, d) in [(-2.5, 1.0), (-1.75, 0.96), (-0.95, 1.02), (-0.18, 0.98), (2.55, 0.98)] {
            let bx = x + cos(a) * r * d * 0.9, by = crownY + sin(a) * r * d
            let tx = x + cos(a) * r * (d + 0.2) * 0.9, ty = crownY + sin(a) * r * (d + 0.2)
            let nx = -sin(a) * r * 0.18, ny = cos(a) * r * 0.18
            ctx.fill(poly([(bx + nx, by + ny), (tx, ty), (bx - nx, by - ny)]), with: .color(body))
        }

        // Moss creeping up the shaded side of the trunk.
        var moss = Path()
        moss.move(to: P(x - w * 1.35, base - 2))
        moss.addQuadCurve(to: P(x - w * 0.5, crownY + 4),
                          control: P(x - w * 1.1, base - (base - crownY) * 0.5))
        stroked(&ctx, moss, Color(hex: "4faf4f").opacity(0.35), w * 0.55)
        for t0 in [0.24, 0.48, 0.7, 0.86] {
            let y = base - (base - crownY) * t0
            ctx.fill(ell(x - w * (1.15 - t0 * 0.5), y, w * 0.34, 0.9),
                     with: .color(Color(hex: "6ee06e").opacity(0.35)))
        }
    }

    private static func fern(_ ctx: inout GraphicsContext, x: Double, y: Double, s: Double,
                             flip: Bool, fine: Bool) {
        let dir: Double = flip ? -1 : 1
        for (angle, len) in [(-1.35, 1.0), (-0.85, 0.86), (-1.95, 0.74), (-0.42, 0.6)] {
            let ex = x - cos(angle) * s * len * dir
            let ey = y + sin(angle) * s * len
            var spine = Path()
            spine.move(to: P(x, y))
            spine.addQuadCurve(to: P(ex, ey), control: P(x + (ex - x) * 0.4, y + (ey - y) * 0.85))
            stroked(&ctx, spine, Color(hex: "1c5f2b"), 1.3)
            guard fine else { continue }
            for t in [0.4, 0.65, 0.88] {
                let px = x + (ex - x) * t, py = y + (ey - y) * (t * 0.92)
                ctx.fill(ell(px, py, 1.7, 0.9), with: .color(Color(hex: "2f9e44").opacity(0.85)))
            }
        }
    }

    // MARK: Voltcrest — thunderstorm and static

    private static func voltcrest(_ ctx: inout GraphicsContext, _ fine: Bool) {
        nightWash(&ctx, Color(hex: "0c0e1a"), P(50, 36))

        // Charged air around the strike.
        ctx.fill(ell(50, 50, 48, 48),
                 with: rShade([Color(hex: "ffd21a").opacity(0.28), Color(hex: "8a6400").opacity(0.12),
                               Color(hex: "0c0e1a").opacity(0)], P(46, 48), 2, 46))

        // Thunderhead.
        ctx.fill(blob([(22, 18, 18, 10), (47, 11, 22, 11), (72, 16, 19, 10), (88, 21, 12, 8), (10, 23, 11, 7)]),
                 with: vShade([Color(hex: "444a6b"), Color(hex: "141626")], 2, 30))
        ctx.fill(blob([(32, 9, 12, 5), (56, 6, 13, 5)]), with: .color(Color(hex: "5b6389").opacity(0.5)))
        // Underside, lit by the discharge.
        glow(&ctx, 3.2) { g in
            g.fill(blob([(45, 25, 18, 4.2), (70, 24, 12, 3.2), (24, 26, 11, 3.2)]),
                   with: .color(Color(hex: "ffd21a").opacity(0.42)))
        }

        // The ridge the bolt is earthing into.
        var ridge = Path()
        ridge.move(to: P(6, 84))
        ridge.addLine(to: P(16, 74))
        ridge.addLine(to: P(24, 79))
        ridge.addLine(to: P(35, 64))
        ridge.addLine(to: P(45, 76))
        ridge.addLine(to: P(56, 68))
        ridge.addLine(to: P(66, 78))
        ridge.addLine(to: P(78, 71))
        ridge.addLine(to: P(94, 84))
        ridge.closeSubpath()
        softFill(&ctx, ridge, band(Color(hex: "1b2033"), Color(hex: "39415f")),
                 halo: Color(hex: "0c0e1a").opacity(0.85), radius: 4)
        stroked(&ctx, poly([(16, 74), (24, 79), (35, 64), (45, 76), (56, 68), (66, 78), (78, 71)], closed: false),
                Color(hex: "6c78a8").opacity(0.55), 0.8)
        stroked(&ctx, poly([(28, 72), (35, 64), (40, 70)], closed: false),
                Color(hex: "ffe680").opacity(0.75), 1.2)
        stroked(&ctx, poly([(50, 72), (56, 68), (61, 73)], closed: false),
                Color(hex: "ffd21a").opacity(0.3), 0.9)

        // Ground haze under the ridge line, so it doesn't end on a hard edge.
        ctx.fill(ell(50, 86, 40, 6),
                 with: band(Color(hex: "141826").opacity(0.5), Color(hex: "222842").opacity(0.7)))

        // The main bolt and its fork.
        let main = poly([(48, 24), (40, 42), (49, 43), (39, 57), (47, 56), (35, 64)], closed: false)
        let fork = poly([(45, 48), (57, 55), (50, 57), (60, 70)], closed: false)
        for path in [main, fork] {
            glow(&ctx, 3.6) { g in
                g.stroke(path, with: .color(Color(hex: "ffd21a").opacity(0.5)),
                         style: StrokeStyle(lineWidth: 6.5, lineCap: .round, lineJoin: .round))
            }
        }
        stroked(&ctx, main, Color(hex: "ffe680"), 2.6)
        stroked(&ctx, fork, Color(hex: "ffe680").opacity(0.8), 1.5)
        stroked(&ctx, main, Color(hex: "fffdf0"), 1.1)
        stroked(&ctx, fork, Color(hex: "fffdf0").opacity(0.85), 0.7)

        // Flash where it lands.
        glow(&ctx, 4.0) { g in
            g.fill(dot(35, 64, 8), with: .color(Color(hex: "fff3a3").opacity(0.75)))
        }

        // Weaker strikes further out.
        let distant: [([(Double, Double)], Double)] = [
            ([(83, 28), (77, 41), (85, 41), (76, 55)], 0.5),
            ([(17, 30), (11, 41), (18, 41), (11, 53)], 0.36)]
        for (pts, o) in distant {
            let b = poly(pts, closed: false)
            glow(&ctx, 2.6) { g in
                g.stroke(b, with: .color(Color(hex: "ffd21a").opacity(o * 0.7)),
                         style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
            stroked(&ctx, b, Color(hex: "fff3a3").opacity(o + 0.3), 1.2)
        }

        guard fine else { return }

        // Rain, and static crackling off the rock.
        let rain: [(Double, Double)] = [
            (27, 36), (63, 32), (73, 47), (31, 54), (86, 55), (20, 60),
            (55, 26), (44, 66), (91, 40), (12, 46), (68, 60), (24, 46)]
        for (x, y) in rain {
            stroked(&ctx, poly([(x, y), (x - 2.4, y + 9)], closed: false),
                    Color(hex: "cfe0ff").opacity(0.2), 0.8)
        }
        for (x, y, len) in [(30.0, 68.0, 6.0), (41.0, 70.0, 5.0), (26.0, 74.0, 4.0)] {
            stroked(&ctx, poly([(x, y), (x + len * 0.4, y + 2), (x + len, y - 1)], closed: false),
                    Color(hex: "ffe680").opacity(0.5), 0.7)
        }
        let sparks: [(Double, Double, Double, Double)] = [
            (59, 40, 1.3, 0.85), (27, 44, 1.1, 0.7), (70, 60, 1.2, 0.65),
            (42, 32, 1.0, 0.6), (16, 68, 1.1, 0.55), (85, 66, 1.0, 0.5)]
        for (x, y, r, o) in sparks { spark(&ctx, x, y, r, o) }
    }

    /// A four-point static spark.
    private static func spark(_ ctx: inout GraphicsContext, _ x: Double, _ y: Double,
                              _ r: Double, _ o: Double) {
        let s = poly([(x, y - r * 2.4), (x + r * 0.6, y - r * 0.6), (x + r * 2.4, y),
                      (x + r * 0.6, y + r * 0.6), (x, y + r * 2.4), (x - r * 0.6, y + r * 0.6),
                      (x - r * 2.4, y), (x - r * 0.6, y - r * 0.6)])
        glow(&ctx, 1.6) { g in
            g.fill(s, with: .color(Color(hex: "ffd21a").opacity(o * 0.7)))
        }
        ctx.fill(s, with: .color(Color(hex: "fff6b0").opacity(o)))
    }

    // MARK: Umbral Reach — shadow, spirits, eclipse

    private static func umbralReach(_ ctx: inout GraphicsContext, _ fine: Bool) {
        nightWash(&ctx, Color(hex: "090317"), P(50, 42))
        ctx.fill(ell(50, 44, 46, 46),
                 with: rShade([Color(hex: "8a5cf0").opacity(0.42), Color(hex: "45208f").opacity(0.16),
                               Color(hex: "090317").opacity(0)], P(50, 32), 2, 44))

        // Eclipse: a dark disc with a burning rim.
        glow(&ctx, 4.5) { g in
            g.stroke(dot(50, 30, 15.5), with: .color(Color(hex: "b98cff").opacity(0.8)), lineWidth: 4)
        }
        ctx.fill(dot(50, 30, 15), with: .color(Color(hex: "0a0320")))
        ctx.stroke(dot(50, 30, 15), with: .color(Color(hex: "d9b3ff").opacity(0.85)), lineWidth: 1.2)
        var flare = Path()
        flare.addArc(center: P(50, 30), radius: 15, startAngle: .degrees(155), endAngle: .degrees(305),
                     clockwise: false)
        stroked(&ctx, flare, .white.opacity(0.9), 1.9)

        // Standing stones and dead wood, rim-lit by the eclipse behind them.
        for stone in [[(9.0, 84.0), (12.0, 56.0), (18.0, 53.0), (21.0, 84.0)],
                      [(80.0, 84.0), (83.0, 60.0), (89.0, 57.0), (92.0, 84.0)]] {
            ctx.fill(poly(stone), with: .color(Color(hex: "160a2e")))
            stroked(&ctx, poly([stone[1], stone[2]], closed: false),
                    Color(hex: "b98cff").opacity(0.35), 0.9)
        }
        deadTree(&ctx, x: 28, base: 84, h: 32, flip: false)
        deadTree(&ctx, x: 72, base: 84, h: 25, flip: true)

        // The mist bank everything is standing in.
        softFill(&ctx, ell(50, 86, 42, 8),
                 band(Color(hex: "190b34"), Color(hex: "34196e")),
                 halo: Color(hex: "9b5cf6").opacity(0.3), radius: 5)
        if fine {
            glow(&ctx, 3.0) { g in
                g.fill(blob([(32, 82, 14, 2.6), (66, 84, 13, 2.4)]),
                       with: .color(Color(hex: "c9a3ff").opacity(0.28)))
            }
        }

        // Spirits drifting up out of it.
        wisp(&ctx, x: 36, y: 62, s: 8.0, alpha: 0.85, eyes: true)
        wisp(&ctx, x: 66, y: 54, s: 5.6, alpha: 0.55, eyes: fine)
        if fine { wisp(&ctx, x: 24, y: 46, s: 3.8, alpha: 0.35, eyes: false) }

        guard fine else { return }

        // Spirit dust and the odd cold star.
        let dust: [(Double, Double, Double, Double)] = [
            (16, 22, 1.2, 0.8), (32, 12, 0.9, 0.6), (78, 18, 1.3, 0.7), (88, 36, 1.0, 0.55),
            (64, 12, 0.9, 0.5), (12, 48, 0.9, 0.45), (86, 54, 1.1, 0.5), (46, 6, 0.9, 0.45),
            (56, 72, 1.0, 0.45), (22, 66, 0.9, 0.4)]
        for (x, y, r, o) in dust {
            glow(&ctx, 1.5) { g in
                g.fill(dot(x, y, r * 2), with: .color(Color(hex: "c9a3ff").opacity(o * 0.5)))
            }
            ctx.fill(dot(x, y, r), with: .color(.white.opacity(o)))
        }
    }

    private static func deadTree(_ ctx: inout GraphicsContext, x: Double, base: Double,
                                 h: Double, flip: Bool) {
        let dir: Double = flip ? -1 : 1
        var t = Path()
        t.move(to: P(x, base))
        t.addQuadCurve(to: P(x + 3 * dir, base - h), control: P(x - 3 * dir, base - h * 0.55))
        stroked(&ctx, t, Color(hex: "160a2e"), 2.4)
        for (t0, len, lift) in [(0.52, 7.5, 6.5), (0.74, 6.0, 4.6), (0.88, 4.6, 3.6)] {
            let bx = x + (3 * dir) * t0 - (2.2 * dir) * (1 - t0)
            let by = base - h * t0
            var branch = Path()
            branch.move(to: P(bx, by))
            branch.addQuadCurve(to: P(bx - len * dir, by - lift),
                                control: P(bx - len * 0.5 * dir, by - lift * 0.2))
            stroked(&ctx, branch, Color(hex: "160a2e"), 1.3)
            var branch2 = Path()
            branch2.move(to: P(bx, by))
            branch2.addQuadCurve(to: P(bx + len * 0.66 * dir, by - lift * 0.8),
                                 control: P(bx + len * 0.33 * dir, by - lift * 0.15))
            stroked(&ctx, branch2, Color(hex: "160a2e"), 1.0)
        }
    }

    /// A hovering spirit: a wisp of essence curling to a point, tapering into a
    /// tattered hem, with a soft aura so it reads as vapour rather than a solid.
    private static func wisp(_ ctx: inout GraphicsContext, x: Double, y: Double, s: Double,
                             alpha: Double, eyes: Bool) {
        var body = Path()
        body.move(to: P(x + s * 0.16, y - s * 1.2))
        body.addCurve(to: P(x + s * 0.95, y + s * 0.4),
                      control1: P(x + s * 0.86, y - s * 0.9), control2: P(x + s * 1.02, y - s * 0.3))
        body.addQuadCurve(to: P(x + s * 0.58, y + s * 1.3), control: P(x + s * 0.96, y + s * 1.0))
        body.addQuadCurve(to: P(x + s * 0.19, y + s * 1.02), control: P(x + s * 0.39, y + s * 1.72))
        body.addQuadCurve(to: P(x - s * 0.22, y + s * 1.34), control: P(x - s * 0.02, y + s * 0.84))
        body.addQuadCurve(to: P(x - s * 0.62, y + s * 1.04), control: P(x - s * 0.42, y + s * 1.76))
        body.addCurve(to: P(x - s * 0.82, y - s * 0.28),
                      control1: P(x - s * 0.97, y + s * 0.72), control2: P(x - s * 1.0, y + s * 0.1))
        body.addCurve(to: P(x + s * 0.16, y - s * 1.2),
                      control1: P(x - s * 0.62, y - s * 0.86), control2: P(x - s * 0.24, y - s * 1.16))
        body.closeSubpath()

        glow(&ctx, s * 0.5) { g in
            g.fill(body, with: .color(Color(hex: "9b5cf6").opacity(alpha * 0.65)))
        }
        ctx.fill(body, with: vShade([Color(hex: "efe4ff").opacity(alpha * 0.85),
                                     Color(hex: "9b5cf6").opacity(alpha * 0.18)],
                                    y - s * 1.2, y + s * 1.4))
        ctx.stroke(body, with: .color(Color(hex: "f6efff").opacity(alpha * 0.55)), lineWidth: 0.7)

        guard eyes else { return }
        ctx.fill(ell(x - s * 0.26, y - s * 0.1, s * 0.12, s * 0.19),
                 with: .color(Color(hex: "2a1252").opacity(0.85)))
        ctx.fill(ell(x + s * 0.3, y - s * 0.14, s * 0.12, s * 0.19),
                 with: .color(Color(hex: "2a1252").opacity(0.85)))
    }
}

#if DEBUG
#Preview("Set emblems") {
    HStack(spacing: 10) {
        ForEach(1...5, id: \.self) { s in
            SetEmblem(set: s).frame(width: 120, height: 120)
        }
    }
    .padding(20)
    .background(Palette.bg0)
}
#endif
