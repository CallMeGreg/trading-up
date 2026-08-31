import SwiftUI

/// A single trading card. Scales all internals from `width` (height = 1.4×width).
/// Pass an `instance` to reflect that specific copy's foil/grade/value; omit for catalogue art.
struct CardView: View {
    let card: Card
    var instance: CardInstance? = nil
    var width: CGFloat = 230
    /// When true (and a `{id}-ext` asset exists), render the full-bleed Extended-Art
    /// treatment: new artwork fills the entire card, with the title/value floated on
    /// scrims and foil/grade still layered on top. (req 4)
    var extendedArt: Bool = false
    /// When supplied, the header's element label is replaced by the evolution-series
    /// **stage pips** — one per stage in the card's line, scoped to the caller's
    /// context (the current Classic run, the current Gauntlet Showcase, or the
    /// all-time Binder). Omit it (nil) to keep the plain element label, e.g. in
    /// contexts with no ownership pool. See docs/mockups/evolution.
    var series: CardSeries? = nil
    /// Whether the stage pips glow (the gold "this pull" halo and the soft owned-pip
    /// glow). On while a pack is being opened; off once keep/sell is decided, where
    /// every owned stage settles to a flat set-colour pip. (req: pips glow only on open)
    var pipsGlow: Bool = true

    private var s: CGFloat { width / 230 }
    private var height: CGFloat { width * 1.4 }
    private var foil: Bool { instance?.foil ?? false }
    private var grade: Int? { instance?.grade }
    private var value: Double { instance?.currentValue ?? card.baseValue }
    private var corner: CGFloat { 16 * s }
    private var showExtended: Bool { extendedArt && UIImage(named: card.id + "-ext") != nil }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner)
                .fill(
                    LinearGradient(
                        colors: [Palette.panelHi, Palette.panel],
                        startPoint: .top, endPoint: .bottom
                    )
                )

            if showExtended {
                extendedContent
            } else {
                VStack(spacing: 6 * s) {
                    header
                    artWindow
                    metaRow
                    flavorText
                    Spacer(minLength: 0)
                    valueBar
                }
                .padding(10 * s)
            }

            if foil {
                FoilOverlay(cornerRadius: corner)
                    .clipShape(RoundedRectangle(cornerRadius: corner))
            }

            RoundedRectangle(cornerRadius: corner)
                .strokeBorder(card.rarity.gemGradient, lineWidth: card.rarity == .ultra ? 3 * s : 2 * s)
        }
        .frame(width: width, height: height)
        // The grade slab pins to the artwork's top-right corner (captured via
        // `ArtFrameKey`) rather than the header, so the evolution stage pips in
        // the top-right stay visible in the Collection and Showcase grids.
        .overlayPreferenceValue(ArtFrameKey.self) { anchor in
            if let anchor, let g = grade {
                GeometryReader { proxy in
                    let art = proxy[anchor]
                    gradeBadge(g)
                        .position(x: art.maxX - 19 * s, y: art.minY + 19 * s)
                }
            }
        }
        .shadow(color: .black.opacity(0.45), radius: 8 * s, x: 0, y: 4 * s)
    }

    // MARK: Pieces

    /// Full-bleed Extended-Art face: the `{id}-ext` illustration edge to edge, with a
    /// top scrim carrying the name/element and a bottom scrim carrying set/number and
    /// value. Foil and grade badges are drawn by `body` over this. (req 4)
    private var extendedContent: some View {
        ZStack {
            if let art = UIImage(named: card.id + "-ext") {
                Image(uiImage: art)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            }
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 11 * s)
                    .padding(.top, 10 * s)
                    .padding(.bottom, 11 * s)
                    .background(LinearGradient(colors: [.black.opacity(0.5), .clear],
                                              startPoint: .top, endPoint: .bottom))
                Spacer(minLength: 0)
                VStack(spacing: 5 * s) {
                    metaRow
                    valueBar
                }
                .padding(.horizontal, 11 * s)
                .padding(.top, 16 * s)
                .padding(.bottom, 11 * s)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.65)],
                                          startPoint: .top, endPoint: .bottom))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: corner))
        .anchorPreference(key: ArtFrameKey.self, value: .bounds) { $0 }
    }

    private var header: some View {
        HStack(spacing: 4 * s) {
            Text(card.name)
                .font(.system(size: 16 * s, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 2 * s)
            if let series {
                // The situational stage pips take the element label's spot, glowing
                // in the *set's* colour so a whole set reads as one family (the
                // card's own element still shows in the art and the meta gem).
                SeriesPips(series: series, setTint: Element.theme(forSet: card.set).badgeTint, s: s, glow: pipsGlow)
            } else if !showExtended {
                // Extended Art is a full-bleed showcase treatment, so it drops the
                // element "type" tag entirely — the artwork and the meta gem already
                // carry the element, and the header stays clean over the scrim.
                Text(card.element.display)
                    .font(.system(size: 9 * s, weight: .bold))
                    .foregroundStyle(card.element.badgeTint)
                    .padding(.horizontal, 6 * s).padding(.vertical, 3 * s)
                    .background(Capsule().fill(card.element.badgeTint.opacity(0.14)))
            }
        }
    }

    private var artWindow: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10 * s).fill(card.element.artGradient)
            if let art = UIImage(named: card.id) {
                Image(uiImage: art)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                SigilView(seed: card.name + card.element.rawValue, element: card.element)
                    .padding(6 * s)
            }
            RoundedRectangle(cornerRadius: 10 * s)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        }
        .frame(height: 150 * s)
        .clipShape(RoundedRectangle(cornerRadius: 10 * s))
        .anchorPreference(key: ArtFrameKey.self, value: .bounds) { $0 }
    }

    private var metaRow: some View {
        HStack {
            HStack(spacing: 4 * s) {
                Circle().fill(card.element.badgeTint).frame(width: 9 * s, height: 9 * s)
                Text(CardDatabase.setName(card.set))
                    .font(.system(size: 10 * s, weight: .semibold))
                    .foregroundStyle(Palette.subtle)
            }
            Spacer()
            Text("\(pad3(card.number)) / 050")
                .font(.system(size: 10 * s, weight: .semibold, design: .monospaced))
                .foregroundStyle(Palette.subtle)
        }
    }

    private var flavorText: some View {
        Text(card.flavor)
            .font(.system(size: 10.5 * s, weight: .regular, design: .serif))
            .italic()
            .foregroundStyle(Palette.text.opacity(0.72))
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var valueBar: some View {
        HStack {
            Text(card.rarity.display.uppercased())
                .font(.system(size: 9.5 * s, weight: .heavy))
                .foregroundStyle(card.rarity.accent)
                .padding(.horizontal, 7 * s).padding(.vertical, 3 * s)
                .background(Capsule().fill(card.rarity.accent.opacity(0.16)))
            Spacer()
            Text(value.money)
                .font(.system(size: 15 * s, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.money)
        }
    }

    private func gradeBadge(_ g: Int) -> some View {
        let color: Color = g >= 9 ? Color(hex: "ffd54a") : (g >= 8 ? Color(hex: "8a94a6") : (g == 1 ? Color(hex: "ff5cf0") : Color(hex: "e0663b")))
        return VStack(spacing: 0) {
            Text("PSA").font(.system(size: 8 * s, weight: .black)).foregroundStyle(.black.opacity(0.7))
            Text("\(g)").font(.system(size: 16 * s, weight: .black, design: .rounded)).foregroundStyle(.black)
        }
        .frame(width: 34 * s, height: 34 * s)
        .background(Circle().fill(color))
        .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 2 * s))
    }
}

/// Captures the artwork rectangle within a `CardView` so the grade slab can pin
/// to the art's top-right corner instead of the header, which carries the
/// evolution stage pips. In Extended-Art mode the art is full-bleed, so this is
/// the whole card face.
private struct ArtFrameKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

// MARK: - Evolution-series stage pips

/// The evolution-series model behind a card header's stage pips (which replace
/// the element label). One entry per stage in the card's line; a stage counts as
/// "owned" when it stands in the caller's context pool — the current Classic run,
/// the current Gauntlet Showcase, or the all-time Binder. `nowStage` lights the
/// gold "this pull" pip in the pull modes (Classic, Gauntlet); the Binder is a
/// browsing view with no card in hand, so it resolves with `pull: false`.
///
/// The pip picture is identical in every mode — only the pool a solid pip counts
/// against changes — so a player learns it once and it reads everywhere. See
/// docs/mockups/evolution.
struct CardSeries {
    /// Every card in the line, sorted by stage (length 1 for a single).
    let line: [Card]
    /// Stages (1-based) owned in the current context.
    let ownedStages: Set<Int>
    /// The stage to light as the gold "this pull" pip, or nil when browsing.
    let nowStage: Int?

    /// Resolve the pips for `card` from an ownership test over the cards in its
    /// line. Pass `pull: true` in a mode with a card in hand (Classic, Gauntlet)
    /// to light the card's own stage gold; `false` in the Binder, where the
    /// current stage simply reads as owned.
    init(for card: Card, pull: Bool, owns: (Card) -> Bool) {
        let line = CardDatabase.line(card.lineId)
        self.line = line
        self.ownedStages = Set(line.filter(owns).map(\.stage))
        self.nowStage = pull ? card.stage : nil
    }

    /// Pips scoped to the current Gauntlet Showcase: a stage counts as owned when
    /// a copy of it stands in the Showcase this run. A pull mode, so the card in
    /// hand lights the gold "now" pip.
    static func gauntlet(_ card: Card, showcase: [CardInstance]) -> CardSeries {
        let owned = Set(showcase.map(\.cardId))
        return CardSeries(for: card, pull: true) { owned.contains($0.id) }
    }
}

/// The stage-pip cluster shown in a card header in place of the element label:
/// one pip per stage in the card's line, glowing in the *set's* signature colour.
/// Solid = a stage owned in context, gold = the card in hand this pull, hollow =
/// a stage still missing; the short connector between two adjacent pips fills once
/// both are present. A single (one pip) draws no connector, so "not a line" reads
/// instantly. Everything scales from `s` (= card width / 230) like the rest of the
/// card. See docs/mockups/evolution.
private struct SeriesPips: View {
    let series: CardSeries
    let setTint: Color
    let s: CGFloat
    /// While opening a pack the owned pips glow and the card in hand lights gold;
    /// once the pull is decided this is off and every owned stage is a flat
    /// set-colour pip. (req: pips glow only on open)
    var glow: Bool = true

    private static let gold = Color(hex: "ffd54a")
    private var d: CGFloat { 9 * s }

    /// A stage is "present" for connector purposes if it's owned or is the card
    /// in hand this pull.
    private func present(_ stage: Int) -> Bool {
        series.nowStage == stage || series.ownedStages.contains(stage)
    }

    var body: some View {
        HStack(spacing: 3 * s) {
            ForEach(Array(series.line.enumerated()), id: \.element.id) { idx, c in
                if idx > 0 {
                    connector(filled: present(series.line[idx - 1].stage) && present(c.stage))
                }
                pip(for: c.stage)
            }
        }
        .padding(.horizontal, 7 * s)
        .padding(.vertical, 4 * s)
        .background(Capsule().fill(Palette.bg0.opacity(0.5)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
        .accessibilityElement()
        .accessibilityLabel(Text(accessibilityText))
    }

    @ViewBuilder
    private func pip(for stage: Int) -> some View {
        if glow && series.nowStage == stage {
            // "This pull" — a white core rimmed and haloed in gold. Only while the
            // pack is being opened; after the decision it settles to a set-tint pip.
            Circle().fill(.white)
                .frame(width: d, height: d)
                .overlay(Circle().stroke(Self.gold, lineWidth: 1.6 * s))
                .shadow(color: Self.gold, radius: 3.5 * s)
        } else if present(stage) {
            // Owned in context — a solid set-tint pip. It carries a soft glow only
            // while opening a pack; once keep/sell is decided it reads flat.
            Circle().fill(setTint)
                .frame(width: d, height: d)
                .shadow(color: glow ? setTint : .clear, radius: glow ? 2.5 * s : 0)
        } else {
            // Missing — a hollow ring.
            Circle().strokeBorder(setTint.opacity(0.55), lineWidth: 1.5 * s)
                .frame(width: d, height: d)
        }
    }

    private func connector(filled: Bool) -> some View {
        Capsule()
            .fill(filled ? setTint : setTint.opacity(0.30))
            .frame(width: 7 * s, height: 2 * s)
    }

    private var accessibilityText: String {
        let held = series.line.filter { present($0.stage) }.count
        if series.line.count == 1 { return "Single card" }
        return "Evolution line, \(held) of \(series.line.count) stages owned"
    }
}

/// Animated holographic sheen for foil cards.
struct FoilOverlay: View {
    var cornerRadius: CGFloat = 16
    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let angle = Angle.degrees((t * 45).truncatingRemainder(dividingBy: 360))
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            Color(hex: "ff4d4d"), Color(hex: "ffd24d"), Color(hex: "4dff88"),
                            Color(hex: "4dd2ff"), Color(hex: "b06cf7"), Color(hex: "ff4d4d"),
                        ]),
                        center: .center, angle: angle
                    )
                )
                .blendMode(.plusLighter)
                .opacity(0.20)
                .allowsHitTesting(false)
        }
    }
}

/// Placeholder shown for an un-collected card slot.
struct LockedCardView: View {
    let card: Card
    var width: CGFloat = 108

    private var s: CGFloat { width / 230 }
    private var height: CGFloat { width * 1.4 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16 * s).fill(Palette.bg0.opacity(0.55))
            RoundedRectangle(cornerRadius: 16 * s)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5 * s, dash: [5 * s, 4 * s]))
                .foregroundStyle(Palette.stroke)
            VStack(spacing: 6 * s) {
                Image(systemName: "questionmark")
                    .font(.system(size: 34 * s, weight: .black))
                    .foregroundStyle(Palette.stroke)
                Text("\(pad3(card.number)) / 050")
                    .font(.system(size: 11 * s, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Palette.subtle.opacity(0.7))
            }
        }
        .frame(width: width, height: height)
    }
}
