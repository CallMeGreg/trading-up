import SwiftUI

// MARK: - Crimped heat-seal edge

/// One end of a foil wrapper's heat seal: a solid band with a row of 45° teeth
/// along the outer edge, the way a real crimped pack is cut off the roll.
struct CrimpEdge: Shape {
    /// Width of a single tooth. Teeth are 45°, so they stand `toothWidth / 2` tall.
    var toothWidth: CGFloat
    /// `true` puts the teeth on the top edge (the pack's top crimp).
    var teethOnTop: Bool

    func path(in rect: CGRect) -> Path {
        let count = max(2, Int((rect.width / max(toothWidth, 1)).rounded()))
        let step = rect.width / CGFloat(count)
        let tooth = min(step / 2, rect.height)
        var p = Path()
        if teethOnTop {
            p.move(to: CGPoint(x: rect.minX, y: rect.minY + tooth))
            for i in 0..<count {
                let x0 = rect.minX + CGFloat(i) * step
                p.addLine(to: CGPoint(x: x0 + step / 2, y: rect.minY))
                p.addLine(to: CGPoint(x: x0 + step, y: rect.minY + tooth))
            }
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        } else {
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - tooth))
            for i in stride(from: count - 1, through: 0, by: -1) {
                let x0 = rect.minX + CGFloat(i) * step
                p.addLine(to: CGPoint(x: x0 + step / 2, y: rect.maxY))
                p.addLine(to: CGPoint(x: x0, y: rect.maxY - tooth))
            }
        }
        p.closeSubpath()
        return p
    }
}

/// A spiky "starburst" flash, the printed kind that shouts a number on real
/// packaging.
struct StarburstShape: Shape {
    var spikes: Int = 12
    var innerRatio: CGFloat = 0.76

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * innerRatio
        var p = Path()
        for i in 0..<(spikes * 2) {
            let r = i.isMultiple(of: 2) ? outer : inner
            let a = Double(i) / Double(spikes * 2) * 2 * .pi - .pi / 2
            let pt = CGPoint(x: c.x + CGFloat(cos(a)) * r, y: c.y + CGFloat(sin(a)) * r)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - Foil wrapper

/// A sealed booster pack drawn as a real mylar wrapper: serrated crimps top and
/// bottom, a holographic film, wrinkle folds, a bulge where the cards sit, and
/// the set's sigil foil-stamped dead centre.
///
/// Everything is derived from `width`, so the same view is the 280pt hero on the
/// reveal screen and the 58pt thumbnail in the shop list. `detail` only decides
/// how much *type* survives — the art stays centred at every size.
struct PackWrapper: View {
    /// How much printing the wrapper can carry before the type turns to mush.
    enum Detail {
        /// Hero size: brand line, sigil, set name, kind, and the card-count burst.
        case full
        /// ~110pt: the same, without the burst.
        case mid
        /// ~58pt shop thumbnail: sigil and set name.
        case mini
        /// ~34pt chip: sigil only.
        case micro
    }

    let set: Int
    var width: CGFloat = 190
    var detail: Detail = .full
    var isBox: Bool = false
    /// Runs the slow diagonal glint. Off by default so a list of thumbnails
    /// isn't driving a `TimelineView` per row.
    var animatedSheen: Bool = false
    /// 0 = sealed, 1 = the top crimp has torn clean off.
    var tearTop: Double = 0
    /// 0 = intact, 1 = the body has dropped away.
    var dropBody: Double = 0

    private var element: Element { Element.theme(forSet: set) }
    private var pal: [Color] { element.palette }

    private var faceHeight: CGFloat { width * 1.30 }
    private var crimpHeight: CGFloat { width * 0.085 }
    private var toothWidth: CGFloat { width * 0.072 }

    /// Full drawn height, crimps included. Callers that need to reserve space
    /// (or centre the pack) can size off this instead of guessing.
    static func height(forWidth width: CGFloat) -> CGFloat { width * (1.30 + 0.085 * 2) }

    private var showsBrandLine: Bool { detail == .full || detail == .mid }
    private var showsSetName: Bool { detail != .micro }
    private var showsKind: Bool { detail == .full || detail == .mid }
    private var showsBurst: Bool { detail == .full }

    private var padH: CGFloat { showsKind ? width * 0.07 : width * 0.06 }
    private var padTop: CGFloat { showsKind ? width * 0.10 : width * 0.075 }
    private var padBottom: CGFloat { showsKind ? width * 0.085 : width * 0.08 }
    private var innerWidth: CGFloat { width - padH * 2 }

    private var emblemWidth: CGFloat {
        switch detail {
        case .full, .mid: return innerWidth * 0.66
        case .mini:       return innerWidth * 0.82
        case .micro:      return innerWidth * 0.88
        }
    }

    private var setNameSize: CGFloat {
        detail == .mini ? width * 0.16 : width * 0.105
    }

    var body: some View {
        VStack(spacing: 0) {
            crimp(teethOnTop: true)
                .rotationEffect(.degrees(-16 * tearTop), anchor: .bottomLeading)
                .offset(x: width * 0.07 * tearTop, y: -width * 0.37 * tearTop)
                .opacity(1 - tearTop)
            VStack(spacing: 0) {
                face
                crimp(teethOnTop: false)
            }
            .scaleEffect(1 - 0.04 * dropBody)
            .offset(y: width * 0.24 * dropBody)
            .opacity(1 - dropBody)
        }
        .frame(width: width)
        .compositingGroup()
        .shadow(color: .black.opacity(0.5), radius: width * 0.09, y: width * 0.05)
        .accessibilityHidden(true)
    }

    // MARK: Crimp

    private func crimp(teethOnTop: Bool) -> some View {
        let shape = CrimpEdge(toothWidth: toothWidth, teethOnTop: teethOnTop)
        return LinearGradient(
            colors: [pal[1].mixed(with: .white, amount: 0.45), pal[2]],
            startPoint: .top, endPoint: .bottom
        )
        .overlay(CrimpStriations(step: max(2, width * 0.016)))
        .frame(width: width, height: crimpHeight)
        .clipShape(shape)
    }

    // MARK: Face

    private var face: some View {
        ZStack {
            LinearGradient(
                stops: [.init(color: pal[1], location: 0),
                        .init(color: pal[2], location: 0.42),
                        .init(color: pal[3], location: 1)],
                startPoint: UnitPoint(x: 0.29, y: 0), endPoint: UnitPoint(x: 0.71, y: 1)
            )
            RadialGradient(colors: [pal[1].opacity(0.7), .clear],
                           center: UnitPoint(x: 0.5, y: 0),
                           startRadius: 0, endRadius: width * 0.9)
            wrinkles
            HoloFilm(period: width * 0.126)
            bulge
            content
            if showsBurst { burst }
            sheen
        }
        .frame(width: width, height: faceHeight)
        .clipped()
    }

    /// Soft light/dark folds so the wrapper doesn't read as flat plastic.
    private var wrinkles: some View {
        LinearGradient(
            stops: [.init(color: .clear, location: 0.16),
                    .init(color: .white.opacity(0.16), location: 0.21),
                    .init(color: .clear, location: 0.26),
                    .init(color: .clear, location: 0.52),
                    .init(color: .black.opacity(0.24), location: 0.57),
                    .init(color: .clear, location: 0.62),
                    .init(color: .clear, location: 0.71),
                    .init(color: .white.opacity(0.11), location: 0.75),
                    .init(color: .clear, location: 0.80)],
            startPoint: UnitPoint(x: 0, y: 0.42), endPoint: UnitPoint(x: 1, y: 0.58)
        )
        .blur(radius: max(1, width * 0.008))
    }

    /// Darkened side seams plus a highlight across the top: the wrapper is
    /// stretched over six cards, not printed flat.
    private var bulge: some View {
        ZStack {
            LinearGradient(
                stops: [.init(color: .black.opacity(0.38), location: 0),
                        .init(color: .clear, location: 0.16),
                        .init(color: .clear, location: 0.84),
                        .init(color: .black.opacity(0.38), location: 1)],
                startPoint: .leading, endPoint: .trailing
            )
            LinearGradient(
                stops: [.init(color: .white.opacity(0.26), location: 0),
                        .init(color: .clear, location: 0.28)],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(colors: [.clear, .black.opacity(0.5)],
                           center: .center,
                           startRadius: width * 0.34, endRadius: width * 0.95)
        }
        .allowsHitTesting(false)
    }

    // MARK: Printing

    private var content: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                if showsBrandLine {
                    Text("TRADING UP")
                        .font(.system(size: width * 0.062, weight: .black, design: .rounded))
                        .tracking(width * 0.018)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        // Boxed so the wordmark can never grow under the
                        // card-count flash in the top-right corner.
                        .frame(width: innerWidth * 0.58)
                        .foregroundStyle(.white.opacity(0.95))
                        .shadow(color: .black.opacity(0.5), radius: 1, y: 1)
                    LinearGradient(colors: [.clear, .white.opacity(0.6), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: innerWidth * 0.52, height: 1)
                        .padding(.vertical, width * 0.035)
                }
            }

            Spacer(minLength: 0)

            SigilView(seed: CardDatabase.setName(set) + element.rawValue, element: element)
                .frame(width: emblemWidth, height: emblemWidth)
                .shadow(color: .black.opacity(0.5), radius: width * 0.02, y: width * 0.01)

            Spacer(minLength: 0)

            VStack(spacing: 0) {
                if showsSetName {
                    Text(CardDatabase.setName(set))
                        .font(.system(size: setNameSize, weight: .black, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(colors: [Color(hex: "fff6d0"), Color(hex: "ffd54a"), Color(hex: "b8860b")],
                                           startPoint: .top, endPoint: .bottom)
                        )
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .shadow(color: .black.opacity(0.55), radius: 1, y: 1)
                }
                if showsKind {
                    Text(isBox ? "BOOSTER BOX" : "BOOSTER PACK")
                        .font(.system(size: width * 0.055, weight: .heavy))
                        .tracking(width * 0.028)
                        .foregroundStyle(.white.opacity(0.82))
                        .padding(.top, width * 0.022)
                }
            }
        }
        .padding(.horizontal, padH)
        .padding(.top, padTop)
        .padding(.bottom, padBottom)
        .frame(width: width, height: faceHeight)
    }

    /// The printed card-count flash, top-right, exactly where a real pack puts it.
    private var burst: some View {
        let size = width * 0.25
        return ZStack {
            StarburstShape()
                .fill(RadialGradient(colors: [Color(hex: "fff3c4"), Color(hex: "ffd54a"), Color(hex: "e39a12")],
                                     center: UnitPoint(x: 0.4, y: 0.35),
                                     startRadius: 0, endRadius: size * 0.62))
            VStack(spacing: 0) {
                Text("6").font(.system(size: width * 0.088, weight: .black, design: .rounded))
                Text("CARDS").font(.system(size: width * 0.032, weight: .black))
            }
            .foregroundStyle(Color(hex: "4a2b00"))
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(9))
        .shadow(color: .black.opacity(0.5), radius: width * 0.015, y: width * 0.012)
        .frame(width: width, height: faceHeight, alignment: .topTrailing)
        .padding(.top, width * 0.045)
    }

    // MARK: Sheen

    @ViewBuilder
    private var sheen: some View {
        if animatedSheen {
            TimelineView(.animation) { tl in
                let loop = 3.4
                let t = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: loop) / loop
                sheenBar(progress: min(1, t / 0.6), strength: 0.55)
            }
        } else {
            // Parked off to one side: a static glint across the middle of a
            // 58pt thumbnail just washes out the sigil.
            sheenBar(progress: 0.14, strength: 0.34)
        }
    }

    private func sheenBar(progress: Double, strength: Double) -> some View {
        LinearGradient(
            stops: [.init(color: .clear, location: 0),
                    .init(color: .white.opacity(strength), location: 0.45),
                    .init(color: .white.opacity(strength * 0.09), location: 0.62),
                    .init(color: .clear, location: 1)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .frame(width: width * 0.55, height: faceHeight * 1.7)
        .rotationEffect(.degrees(14))
        .offset(x: -width * 0.85 + width * 1.75 * progress)
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }
}

/// The fine vertical striations pressed into a heat seal.
private struct CrimpStriations: View {
    var step: CGFloat

    var body: some View {
        Canvas { ctx, size in
            var x: CGFloat = 0
            while x < size.width {
                ctx.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)),
                         with: .color(.white.opacity(0.30)))
                ctx.fill(Path(CGRect(x: x + 1, y: 0, width: 1, height: size.height)),
                         with: .color(.black.opacity(0.22)))
                x += step
            }
        }
        .allowsHitTesting(false)
    }
}

/// The rainbow film on a foil wrapper — diagonal stripes, dodged and knocked
/// almost all the way back so it reads as iridescence rather than colour.
private struct HoloFilm: View {
    var period: CGFloat

    private static let colors = ["ff3c8c", "3cdcff", "ffeb78", "a06eff"].map { Color(hex: $0) }

    var body: some View {
        Canvas { ctx, size in
            let band = max(1, period / 4)
            let reach = size.width + size.height
            ctx.rotate(by: .degrees(22))
            var x = -reach
            var i = 0
            while x < reach {
                ctx.fill(Path(CGRect(x: x, y: -reach, width: band, height: reach * 2)),
                         with: .color(Self.colors[i % Self.colors.count].opacity(0.16)))
                x += band
                i += 1
            }
        }
        .blendMode(.colorDodge)
        .opacity(0.3)
        .allowsHitTesting(false)
    }
}

// MARK: - Booster box

/// A sealed booster box: a shrink-wrapped display box drawn as three faces, so
/// the biggest purchase in the game stops looking like a pack with different
/// text on it.
struct BoosterBoxArt: View {
    let set: Int
    var width: CGFloat = 230

    private var element: Element { Element.theme(forSet: set) }
    private var pal: [Color] { element.palette }

    private var frontWidth: CGFloat { width * 0.77 }
    private var depth: CGFloat { frontWidth * 0.30 }
    private var rise: CGFloat { frontWidth * 0.175 }
    private var frontHeight: CGFloat { frontWidth * 0.92 }

    static func height(forWidth width: CGFloat) -> CGFloat {
        let fw = width * 0.77
        return fw * 0.92 + fw * 0.175
    }

    private var totalHeight: CGFloat { frontHeight + rise }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Face(points: [CGPoint(x: frontWidth, y: rise),
                          CGPoint(x: frontWidth + depth, y: 0),
                          CGPoint(x: frontWidth + depth, y: frontHeight),
                          CGPoint(x: frontWidth, y: rise + frontHeight)])
                .fill(LinearGradient(colors: [pal[2].mixed(with: .black, amount: 0.3),
                                              pal[3].mixed(with: .black, amount: 0.4)],
                                     startPoint: .top, endPoint: .bottom))

            Face(points: [CGPoint(x: 0, y: rise),
                          CGPoint(x: depth, y: 0),
                          CGPoint(x: frontWidth + depth, y: 0),
                          CGPoint(x: frontWidth, y: rise)])
                .fill(LinearGradient(colors: [pal[1].mixed(with: .white, amount: 0.25), pal[2]],
                                     startPoint: .top, endPoint: .bottom))

            frontFace
                .frame(width: frontWidth, height: frontHeight)
                .offset(y: rise)
        }
        .frame(width: width, height: totalHeight, alignment: .topLeading)
        .compositingGroup()
        .shadow(color: .black.opacity(0.6), radius: width * 0.1, y: width * 0.09)
        .accessibilityHidden(true)
    }

    private var frontFace: some View {
        ZStack {
            LinearGradient(
                stops: [.init(color: pal[1], location: 0),
                        .init(color: pal[2], location: 0.45),
                        .init(color: pal[3], location: 1)],
                startPoint: UnitPoint(x: 0.3, y: 0), endPoint: UnitPoint(x: 0.7, y: 1)
            )
            RadialGradient(colors: [.clear, .black.opacity(0.5)],
                           center: .center, startRadius: width * 0.2, endRadius: width * 0.6)

            VStack(spacing: width * 0.015) {
                Text("TRADING UP")
                    .font(.system(size: width * 0.05, weight: .black, design: .rounded))
                    .tracking(width * 0.018)
                    .foregroundStyle(.white.opacity(0.9))
                SigilView(seed: CardDatabase.setName(set) + element.rawValue, element: element)
                    .frame(width: frontWidth * 0.4, height: frontWidth * 0.4)
                Text(CardDatabase.setName(set))
                    .font(.system(size: width * 0.115, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(colors: [Color(hex: "fff6d0"), Color(hex: "ffd54a"), Color(hex: "b8860b")],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .lineLimit(1).minimumScaleFactor(0.5)
                Text("\(Economy.boxPacks) BOOSTER PACKS")
                    .font(.system(size: width * 0.046, weight: .heavy))
                    .tracking(width * 0.018)
                    .foregroundStyle(.white.opacity(0.95))
                    .shadow(color: .black.opacity(0.55), radius: width * 0.008, y: 1)
                Text("≥\(Economy.boxGuaranteeUltras) ULTRA · ≥\(Economy.boxGuaranteeFoils) FOIL GUARANTEED")
                    .font(.system(size: width * 0.042, weight: .heavy))
                    .foregroundStyle(Color(hex: "ffd54a"))
                    .padding(.horizontal, width * 0.05).padding(.vertical, width * 0.022)
                    .background(Capsule().fill(.black.opacity(0.3)))
                    .overlay(Capsule().strokeBorder(Color(hex: "ffd54a").opacity(0.6), lineWidth: 1))
                    .padding(.top, width * 0.02)
            }
            .padding(width * 0.05)
            .minimumScaleFactor(0.5)

            // Shrink wrap.
            LinearGradient(
                stops: [.init(color: .clear, location: 0.28),
                        .init(color: .white.opacity(0.3), location: 0.36),
                        .init(color: .clear, location: 0.44),
                        .init(color: .clear, location: 0.58),
                        .init(color: .white.opacity(0.18), location: 0.64),
                        .init(color: .clear, location: 0.70)],
                startPoint: UnitPoint(x: 0, y: 0.35), endPoint: UnitPoint(x: 1, y: 0.65)
            )
            .allowsHitTesting(false)
        }
        .clipped()
    }

    /// A flat quad in the box's own coordinate space.
    private struct Face: Shape {
        var points: [CGPoint]
        func path(in rect: CGRect) -> Path {
            var p = Path()
            guard let first = points.first else { return p }
            p.move(to: first)
            for pt in points.dropFirst() { p.addLine(to: pt) }
            p.closeSubpath()
            return p
        }
    }
}

/// The 12 pack wells inside an opened booster box. A well only ever says
/// "still sealed" or "already opened" — never which pack is carrying the box's
/// guarantee, because that would spoil the pull before the tear.
struct PackTray: View {
    let set: Int
    /// How many packs have already been taken out of the tray.
    let opened: Int
    var total: Int = Economy.boxPacks
    var width: CGFloat = 250
    var columns: Int = 6
    /// Defaults to a "packs left" count.
    var caption: String? = nil

    private var element: Element { Element.theme(forSet: set) }
    private var remaining: Int { max(0, total - opened) }
    private var captionText: String { caption ?? "\(remaining) of \(total) packs left" }

    private var slotWidth: CGFloat {
        let cols = CGFloat(max(1, min(total, columns)))
        return (width - 20 - (cols - 1) * 5) / cols
    }

    var body: some View {
        VStack(spacing: 7) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5),
                                     count: max(1, min(total, columns))),
                      spacing: 5) {
                ForEach(0..<total, id: \.self) { i in
                    slot(sealed: i >= opened)
                        .frame(height: slotWidth * 1.5)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [Color(hex: "171d29"), Color(hex: "0e131c")],
                                         startPoint: .top, endPoint: .bottom))
            )
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.stroke, lineWidth: 1))

            Text(captionText)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.subtle)
        }
        .frame(width: width)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(captionText)
    }

    @ViewBuilder
    private func slot(sealed: Bool) -> some View {
        if sealed {
            RoundedRectangle(cornerRadius: 3)
                .fill(LinearGradient(colors: [element.palette[1], element.palette[2], element.palette[3]],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(alignment: .top) {
                    LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.05)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: slotWidth * 0.46)
                }
                .clipShape(RoundedRectangle(cornerRadius: 3))
        } else {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(hex: "0a0e15"))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.black.opacity(0.6), lineWidth: 1))
        }
    }
}

// MARK: - Colour mixing

extension Color {
    /// Blends towards `other` — the SwiftUI stand-in for CSS `color-mix`.
    func mixed(with other: Color, amount: Double) -> Color {
        let t = max(0, min(1, amount))
        #if canImport(UIKit)
        let a = UIColor(self), b = UIColor(other)
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        guard a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa),
              b.getRed(&br, green: &bg, blue: &bb, alpha: &ba) else { return self }
        return Color(red: Double(ar) + (Double(br) - Double(ar)) * t,
                     green: Double(ag) + (Double(bg) - Double(ag)) * t,
                     blue: Double(ab) + (Double(bb) - Double(ab)) * t)
        #else
        return self
        #endif
    }
}
