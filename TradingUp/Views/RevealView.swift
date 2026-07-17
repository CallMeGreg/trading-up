import SwiftUI

/// Dramatic pack / box opening. Packs reveal one card at a time with a tap;
/// boxes jump to a highlights summary (too many cards to flip individually).
struct RevealView: View {
    let result: OpenResult
    let set: Int
    let onDone: () -> Void

    @State private var phase: Phase = .sealed

    private enum Phase: Equatable {
        case sealed
        case revealing(Int)
        case summary
    }

    private var element: Element { Element.theme(forSet: set) }

    var body: some View {
        ZStack {
            Palette.bg0.ignoresSafeArea()
            RadialGradient(
                gradient: Gradient(colors: [element.palette[2].opacity(0.35), .clear]),
                center: .center, startRadius: 20, endRadius: 400
            )
            .ignoresSafeArea()

            switch phase {
            case .sealed:      sealedView
            case .revealing(let i): revealingView(i)
            case .summary:     SummaryView(result: result, set: set, onDone: onDone)
            }
        }
    }

    // MARK: Sealed

    private var sealedView: some View {
        VStack(spacing: 28) {
            Spacer()
            PackArtwork(set: set, isBox: result.isBox)
            VStack(spacing: 6) {
                Text(result.isBox ? "Booster Box" : "\(CardDatabase.setName(set)) Pack")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text(result.isBox ? "Tap to tear it open" : "Tap to open")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.subtle)
            }
            Spacer()
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { advance() }
    }

    // MARK: Revealing

    private func revealingView(_ i: Int) -> some View {
        let inst = result.pulled[i]
        let showBurst = inst.foil || inst.card.rarity == .rare || inst.card.rarity == .ultra
        return VStack(spacing: 20) {
            HStack(spacing: 7) {
                ForEach(result.pulled.indices, id: \.self) { idx in
                    Circle()
                        .fill(idx <= i ? result.pulled[idx].card.rarity.accent : Palette.stroke)
                        .frame(width: 9, height: 9)
                }
            }
            .padding(.top, 24)

            Spacer()

            ZStack {
                if showBurst {
                    GlowBurst(color: inst.foil ? Color(hex: "ff8ad6") : inst.card.rarity.accent)
                }
                CardView(card: inst.card, instance: inst, width: 280)
                    .id(i)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.55).combined(with: .opacity),
                        removal: .opacity
                    ))
            }

            Spacer()

            VStack(spacing: 4) {
                Text(inst.card.rarity.display.uppercased())
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(inst.card.rarity.accent)
                Text(i + 1 == result.pulled.count ? "Tap to finish" : "Tap for next card")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.subtle)
            }
            .padding(.bottom, 44)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { advance() }
    }

    // MARK: Flow

    private func advance() {
        switch phase {
        case .sealed:
            if result.isBox {
                Haptics.play(.heavy)
                withAnimation(.easeOut(duration: 0.4)) { phase = .summary }
            } else {
                haptic(for: result.pulled[0])
                withAnimation(.spring(response: 0.5, dampingFraction: 0.68)) { phase = .revealing(0) }
            }
        case .revealing(let i):
            let next = i + 1
            if next < result.pulled.count {
                haptic(for: result.pulled[next])
                withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { phase = .revealing(next) }
            } else {
                Haptics.play(.success)
                withAnimation(.easeOut(duration: 0.35)) { phase = .summary }
            }
        case .summary:
            break
        }
    }

    private func haptic(for inst: CardInstance) {
        if inst.foil || inst.card.rarity == .ultra { Haptics.play(.heavy) }
        else if inst.card.rarity == .rare { Haptics.play(.medium) }
        else { Haptics.play(.light) }
    }
}

// MARK: - Summary

private struct SummaryView: View {
    @EnvironmentObject var game: GameState
    let result: OpenResult
    let set: Int
    let onDone: () -> Void

    private var totalValue: Double { result.pulled.reduce(0) { $0 + $1.currentValue } }
    private var foils: [CardInstance] { result.pulled.filter { $0.foil } }
    private var ultras: [CardInstance] { result.pulled.filter { $0.card.rarity == .ultra } }
    private var highlights: [CardInstance] {
        // Boxes: show the exciting cards. Packs: show everything.
        result.isBox ? Array((ultras + foils.filter { $0.card.rarity != .ultra })
            .reduce(into: [CardInstance]()) { acc, x in if !acc.contains(where: { $0.id == x.id }) { acc.append(x) } })
            : result.pulled
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 18) {
                    Text(result.isBox ? "Booster Box Opened!" : "Pack Opened!")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.top, 28)

                    HStack(spacing: 10) {
                        StatTile(label: "Cards", value: "\(result.pulled.count)")
                        StatTile(label: "Foils", value: "\(foils.count)", tint: Color(hex: "ff8ad6"))
                        StatTile(label: "Ultras", value: "\(ultras.count)", tint: Color(hex: "b06cf7"))
                        StatTile(label: "Value", value: totalValue.moneyShort, tint: Palette.money)
                    }

                    ForEach(result.bonuses) { bonus in
                        BonusBanner(bonus: bonus)
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12)], spacing: 12) {
                        ForEach(highlights) { inst in
                            CardView(card: inst.card, instance: inst, width: 104)
                        }
                    }
                    .padding(.top, 4)

                    if result.isBox && highlights.count < result.pulled.count {
                        Text("+ \(result.pulled.count - highlights.count) more commons & uncommons added to your collection")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Palette.subtle)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(16)
            }

            BigButton(title: "Add to Collection", systemImage: "checkmark.circle.fill",
                      tint: [Palette.money, Color(hex: "2fae63")]) {
                Haptics.play(.light)
                onDone()
            }
            .padding(16)
        }
        .background(Palette.bg0.ignoresSafeArea())
    }
}

// MARK: - Bits

struct BonusBanner: View {
    let bonus: BonusEvent
    var body: some View {
        HStack(spacing: 10) {
            Text(bonus.kind == .set ? "🏆" : "🧬").font(.system(size: 20))
            Text(bonus.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
            Spacer(minLength: 4)
            Text("+\(bonus.amount.money)")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.money)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Palette.money.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.money.opacity(0.4), lineWidth: 1))
    }
}

/// Rotating light rays behind rare pulls.
struct GlowBurst: View {
    var color: Color
    var body: some View {
        TimelineView(.animation) { tl in
            let angle = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 12) / 12
            ZStack {
                Circle()
                    .fill(RadialGradient(gradient: Gradient(colors: [color.opacity(0.5), .clear]),
                                         center: .center, startRadius: 10, endRadius: 220))
                    .frame(width: 440, height: 440)
                AngularGradient(
                    gradient: Gradient(stops: raysStops()),
                    center: .center,
                    angle: .degrees(angle * 360)
                )
                .frame(width: 420, height: 420)
                .mask(Circle())
                .opacity(0.18)
                .blendMode(.plusLighter)
            }
        }
    }

    private func raysStops() -> [Gradient.Stop] {
        var stops: [Gradient.Stop] = []
        let n = 12
        for i in 0..<n {
            let l = Double(i) / Double(n)
            let r = Double(i) + 0.5
            stops.append(.init(color: .clear, location: l))
            stops.append(.init(color: color, location: r / Double(n)))
        }
        stops.append(.init(color: .clear, location: 1))
        return stops
    }
}

/// Sealed pack / box graphic.
struct PackArtwork: View {
    let set: Int
    var isBox: Bool
    private var element: Element { Element.theme(forSet: set) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(LinearGradient(colors: [element.palette[1], element.palette[3]],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 18)
                .fill(LinearGradient(colors: [.clear, .white.opacity(0.7), .clear],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .blendMode(.plusLighter)
                .opacity(0.25)
            VStack(spacing: 10) {
                Text("TRADING UP")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .tracking(2)
                Text(element.emoji).font(.system(size: 64))
                Text(CardDatabase.setName(set).uppercased())
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.95))
                    .tracking(1)
                Text(isBox ? "BOOSTER BOX" : "BOOSTER PACK")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(20)
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(.white.opacity(0.25), lineWidth: 1.5)
        }
        .frame(width: isBox ? 230 : 190, height: isBox ? 240 : 300)
        .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
    }
}
