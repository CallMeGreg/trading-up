import SwiftUI

// MARK: - Deterministic RNG (for frame-stable particle layouts)

/// SplitMix64 — tiny, fast, deterministic. Re-seeded every frame so a particle
/// burst renders the same layout across frames (only elapsed time advances).
struct SplitMix64 {
    private var state: UInt64
    init(_ seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    /// Uniform Double in [0, 1).
    mutating func unit() -> Double { Double(next() >> 11) * (1.0 / 9007199254740992.0) }
}

// MARK: - Branded card back

/// The reverse of a card, shown before it flips face-up. Themed to the set's
/// element with a concentric emblem around the element mark and a gold frame —
/// deliberately symmetric so the 3D flip never reveals mirrored text.
struct CardBack: View {
    let set: Int
    var width: CGFloat = 280

    private var s: CGFloat { width / 230 }
    private var height: CGFloat { width * 1.4 }
    private var corner: CGFloat { 16 * s }
    private var e: Element { Element.theme(forSet: set) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner)
                .fill(LinearGradient(colors: [e.palette[2], e.palette[3]],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: corner)
                .fill(RadialGradient(gradient: Gradient(colors: [e.palette[1].opacity(0.55), .clear]),
                                     center: .center, startRadius: 6 * s, endRadius: 150 * s))

            ZStack {
                ForEach(0..<3, id: \.self) { k in
                    RoundedRectangle(cornerRadius: 8 * s)
                        .strokeBorder(.white.opacity(0.18 - Double(k) * 0.045), lineWidth: 1.5 * s)
                        .frame(width: (128 - CGFloat(k) * 28) * s, height: (128 - CGFloat(k) * 28) * s)
                        .rotationEffect(.degrees(45))
                }
                Text(e.emoji)
                    .font(.system(size: 62 * s))
                    .shadow(color: .black.opacity(0.55), radius: 5 * s, y: 2 * s)
            }

            Text("TRADING UP")
                .font(.system(size: 10 * s, weight: .black, design: .rounded))
                .tracking(3 * s)
                .foregroundStyle(.white.opacity(0.5))
                .offset(y: height * 0.40)

            RoundedRectangle(cornerRadius: corner)
                .strokeBorder(LinearGradient(colors: [Color(hex: "ffd54a").opacity(0.85),
                                                      .white.opacity(0.3),
                                                      Color(hex: "ffd54a").opacity(0.6)],
                                             startPoint: .top, endPoint: .bottom),
                              lineWidth: 2.5 * s)
            RoundedRectangle(cornerRadius: corner)
                .inset(by: 6 * s)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1 * s)
        }
        .frame(width: width, height: height)
        .shadow(color: .black.opacity(0.45), radius: 8 * s, x: 0, y: 4 * s)
    }
}

// MARK: - Particle burst

/// A one-shot sparkle/confetti burst rendered in a single `Canvas`. Particles
/// fly outward, fall under a little gravity, and fade. Frame-stable via a
/// re-seeded RNG, and self-terminating after `duration`.
struct ParticleBurst: View {
    var colors: [Color]
    var count: Int = 26
    var duration: Double = 1.05
    var radius: CGFloat = 185
    var seed: UInt64 = 0x1234_5678

    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let elapsed = tl.date.timeIntervalSince(start)
                guard elapsed <= duration else { return }
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                var rng = SplitMix64(seed)
                for _ in 0..<count {
                    let ang = rng.unit() * 2 * .pi
                    let spd = 0.35 + rng.unit() * 0.65
                    let life = 0.72 + rng.unit() * 0.28
                    let psz = 2.5 + rng.unit() * 4.5
                    let colIdx = min(colors.count - 1, Int(rng.unit() * Double(colors.count)))
                    let isStar = rng.unit() < 0.5
                    let p = elapsed / (duration * life)
                    if p >= 1 { continue }
                    let ease = 1 - pow(1 - p, 3)
                    let dist = radius * CGFloat(spd) * CGFloat(ease)
                    let gravity = CGFloat(95.0 * p * p)
                    let x = c.x + CGFloat(cos(ang)) * dist
                    let y = c.y + CGFloat(sin(ang)) * dist + gravity
                    let alpha = pow(1 - p, 1.4)
                    let rect = CGRect(x: x - psz, y: y - psz, width: psz * 2, height: psz * 2)
                    ctx.opacity = alpha
                    if isStar {
                        ctx.fill(Self.starPath(in: rect), with: .color(colors[colIdx]))
                    } else {
                        ctx.fill(Path(ellipseIn: rect), with: .color(colors[colIdx]))
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// A 4-point sparkle inscribed in `rect`.
    static func starPath(in rect: CGRect) -> Path {
        let cx = rect.midX, cy = rect.midY
        let ro = rect.width / 2
        let ri = ro * 0.34
        var p = Path()
        for i in 0..<8 {
            let r = (i % 2 == 0) ? ro : ri
            let a = Double(i) / 8 * 2 * .pi - .pi / 2
            let pt = CGPoint(x: cx + CGFloat(cos(a)) * r, y: cy + CGFloat(sin(a)) * r)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - Revealing card (flip + drama)

/// One card being revealed: it flips up from a `CardBack`, and — scaled to the
/// pull's rarity — fires a glow burst, screen flash, sparkle particles, and the
/// matching audio sting at the moment it turns face-up.
struct RevealingCardView: View {
    let inst: CardInstance
    var isNew: Bool = false
    var width: CGFloat = 280

    @State private var rotation: Double = 180   // 180 = back showing, 0 = face-up
    @State private var flash: Double = 0
    @State private var showParticles = false
    @State private var sheen = false

    private var s: CGFloat { width / 230 }
    private var rarity: Rarity { inst.card.rarity }
    private var isSpecial: Bool { inst.foil || rarity == .rare || rarity == .ultra }
    private var isBig: Bool { rarity == .ultra || inst.foil }
    private var faceUp: Bool { rotation < 90 }
    private var burstColor: Color { inst.foil ? Color(hex: "ff8ad6") : rarity.accent }

    private var particleColors: [Color] {
        if inst.foil {
            return [Color(hex: "ff8ad6"), Color(hex: "ffd54a"), .white, Color(hex: "8fd3ff")]
        }
        switch rarity {
        case .ultra: return [Color(hex: "ffd54a"), Color(hex: "ff8ad6"), Color(hex: "b06cf7"), .white]
        default:     return [rarity.accent, .white, rarity.accent.opacity(0.7)]
        }
    }

    var body: some View {
        // The flip stack alone defines this view's layout. Everything else —
        // glow, particles, flash, badge — rides along as a background/overlay so
        // it can't push the card around: the 460pt particle field is wider than
        // a 390pt phone, and as a ZStack sibling it dragged rare pulls ~35pt off
        // centre on an iPhone 14. The effects are sized off `width` too, so they
        // stay in proportion on every device instead of being fixed at iPad scale.
        ZStack {
            CardBack(set: inst.card.set, width: width)
                .opacity(faceUp ? 0 : 1)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))   // keep un-mirrored
            CardView(card: inst.card, instance: inst, width: width)
                .opacity(faceUp ? 1 : 0)
        }
        .rotation3DEffect(.degrees(rotation), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
        .overlay {
            if isBig && faceUp { sheenSweep }
        }
        .background {
            if isSpecial {
                GlowBurst(color: burstColor, diameter: width * 1.57)
                    .scaleEffect(faceUp ? 1 : 0.55)
                    .opacity(faceUp ? 1 : 0)
                    .animation(.easeOut(duration: 0.4), value: faceUp)
            }
        }
        .overlay {
            if showParticles && isSpecial {
                ParticleBurst(colors: particleColors,
                              count: isBig ? 34 : 20,
                              duration: isBig ? 1.15 : 0.9,
                              radius: width * (isBig ? 0.75 : 0.54),
                              seed: seedFromID())
                    .frame(width: fxSize, height: fxSize)
            }
        }
        .overlay {
            Color.white
                .opacity(flash)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
                .frame(width: fxSize, height: fxSize)
        }
        .overlay {
            if isNew {
                Color.clear
                    .frame(width: width, height: width * 1.4)
                    .overlay(alignment: .topTrailing) { newBadge }
                    .allowsHitTesting(false)
            }
        }
        .onAppear(perform: run)
    }

    /// Footprint of the burst effects, scaled off the card so a reveal looks the
    /// same on a 4.7" phone as it does on a 13" iPad.
    private var fxSize: CGFloat { width * 1.64 }

    /// The gold "NEW" flag that pops onto a brand-new card as it turns face-up —
    /// the same badge shown on the pack summary, so the reveal reads consistently.
    private var newBadge: some View {
        Text("✦ NEW")
            .font(.system(size: 13 * s, weight: .black))
            .foregroundStyle(.white)
            .padding(.horizontal, 11 * s).padding(.vertical, 5 * s)
            .background(Capsule().fill(Color(hex: "ffd54a")))
            .overlay(Capsule().strokeBorder(.white.opacity(0.4), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.5), radius: 3 * s, y: 1)
            .offset(x: 10 * s, y: -10 * s)
            .scaleEffect(faceUp ? 1 : 0.4, anchor: .center)
            .opacity(faceUp ? 1 : 0)
            .animation(.spring(response: 0.4, dampingFraction: 0.55), value: faceUp)
    }

    /// A quick diagonal light sweep across the freshly-revealed hero card.
    private var sheenSweep: some View {
        GeometryReader { geo in
            LinearGradient(colors: [.clear, .white.opacity(0.55), .clear],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(width: geo.size.width * 0.5)
                .rotationEffect(.degrees(20))
                .offset(x: sheen ? geo.size.width * 1.1 : -geo.size.width * 1.1)
                .blendMode(.plusLighter)
                .mask(RoundedRectangle(cornerRadius: 16 * (width / 230)))
        }
        .allowsHitTesting(false)
    }

    private func run() {
        // The soft flip "ffttt" rides the card's motion; every card gets it.
        Sound.play(.cardFlip, volume: 0.7)

        let response = isBig ? 0.75 : 0.5
        withAnimation(.spring(response: response, dampingFraction: 0.72)) { rotation = 0 }

        // Land the sting + effects right as the card crosses to face-up.
        let mid = response * 0.42
        DispatchQueue.main.asyncAfter(deadline: .now() + mid) {
            // Foil is a shimmer overlay on any rarity; the rarity sting layers
            // under it, so a foil rare/ultra gets both.
            if inst.foil { Sound.play(.foilShimmer, volume: 0.8) }
            if rarity == .ultra { Sound.play(.ultra) }
            else if rarity == .rare { Sound.play(.rare) }

            if isSpecial {
                showParticles = true
                withAnimation(.easeOut(duration: 0.10)) { flash = isBig ? 0.55 : 0.30 }
                withAnimation(.easeOut(duration: 0.55).delay(0.10)) { flash = 0 }
            }
            if isBig {
                withAnimation(.easeInOut(duration: 0.85)) { sheen = true }
            }
        }
    }

    private func seedFromID() -> UInt64 {
        var h: UInt64 = 1469598103934665603
        for byte in inst.id.uuidString.utf8 { h = (h ^ UInt64(byte)) &* 1099511628211 }
        return h
    }
}

// MARK: - Sealed pack (idle + tear-open)

/// The sealed pack/box on the reveal screen: it floats and shimmers to invite a
/// tap, then tears open with a flash and hands off to the card reveal.
struct SealedPackView: View {
    let set: Int
    let isBox: Bool
    let onOpen: () -> Void

    @State private var floaty = false
    @State private var hint = false
    @State private var tearing = false
    /// Split from `tearing` so the crimp rips off first and the body only falls
    /// once it's gone — a pack opens in two beats, not one.
    @State private var tearTop: Double = 0
    @State private var dropBody: Double = 0
    @State private var flash: Double = 0

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 28) {
                    Spacer(minLength: 0)
                    ZStack {
                        PackArtwork(set: set, isBox: isBox, tearTop: tearTop, dropBody: dropBody)
                            .rotationEffect(.degrees(floaty ? 1.6 : -1.6))
                            .offset(y: floaty ? -9 : 9)
                    }
                    VStack(spacing: 6) {
                        Text(isBox ? "Booster Box" : "\(CardDatabase.setName(set)) Pack")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text(isBox ? "Tap to tear it open" : "Tap to open")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Palette.subtle)
                    }
                    .opacity(tearing ? 0 : 1)
                    Spacer(minLength: 0)
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.white.opacity(0.6))
                        .scaleEffect(hint ? 1.14 : 0.92)
                        .opacity((hint ? 0.9 : 0.5) * (tearing ? 0 : 1))
                        .padding(.bottom, 40)
                }
                // At least fill the screen (so the Spacers still centre things
                // on a normal portrait phone), but let the VStack grow taller
                // than that and scroll rather than clip on a very short frame
                // (e.g. 402pt-tall landscape phone).
                .frame(minWidth: geo.size.width, minHeight: geo.size.height)
            }
        }
        .overlay {
            Color.white.opacity(flash).blendMode(.plusLighter).ignoresSafeArea().allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture { open() }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.1).repeatForever(autoreverses: true)) { floaty = true }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { hint = true }
        }
    }

    private func open() {
        guard !tearing else { return }
        Haptics.play(isBox ? .heavy : .medium)
        Sound.play(.packOpen)
        tearing = true
        withAnimation(.easeIn(duration: 0.34)) { tearTop = 1 }
        withAnimation(.easeIn(duration: 0.42).delay(0.1)) { dropBody = 1 }
        withAnimation(.easeOut(duration: 0.12).delay(0.12)) { flash = 0.45 }
        withAnimation(.easeOut(duration: 0.35).delay(0.22)) { flash = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) { onOpen() }
    }
}
