import SwiftUI

/// Card detail sheet: big art, evolution line, and per-copy sell / grade actions.
struct CardDetailView: View {
    let card: Card
    @Environment(GameState.self) var game: GameState
    @Environment(\.dismiss) private var dismiss
    @State private var gradeResult: GradeResult?

    private var copies: [CardInstance] {
        game.instances(of: card.id).sorted { $0.currentValue > $1.currentValue }
    }
    private var line: [Card] { CardDatabase.line(card.lineId) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    CardView(card: card, instance: copies.first, width: 250)
                        .padding(.top, 8)

                    if line.count > 1 { evolutionSection }
                    copiesSection
                }
                .padding(16)
                .readableWidth()
            }
            .background(Palette.screen.ignoresSafeArea())
            .navigationTitle(card.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay {
                if let r = gradeResult {
                    GradeRevealOverlay(result: r) { gradeResult = nil }
                }
            }
        }
    }

    // MARK: Evolution line

    private var evolutionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Evolution Line")
            HStack(spacing: 6) {
                ForEach(Array(line.enumerated()), id: \.element.id) { idx, stageCard in
                    VStack(spacing: 5) {
                        miniStage(stageCard)
                        Text(stageCard.name)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(game.owns(stageCard.id) ? Palette.text : Palette.subtle)
                            .lineLimit(1).minimumScaleFactor(0.5)
                            .frame(width: 68)
                    }
                    if idx < line.count - 1 {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Palette.subtle)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private func miniStage(_ c: Card) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(game.owns(c.id) ? AnyShapeStyle(c.element.artGradient) : AnyShapeStyle(Palette.bg0.opacity(0.5)))
            if game.owns(c.id) {
                // Same shipped illustration the card itself uses, so the line
                // reads as a row of familiar creatures rather than placeholders.
                if let art = UIImage(named: c.id) {
                    Image(uiImage: art)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                } else {
                    SigilView(seed: c.name + c.element.rawValue, element: c.element).padding(6)
                }
            } else {
                Image(systemName: "questionmark")
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(Palette.stroke)
            }
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(c.id == card.id ? card.rarity.accent : Palette.stroke,
                              lineWidth: c.id == card.id ? 2 : 1)
        }
        .frame(width: 68, height: 68)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Copies

    private var copiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Your Copies (\(copies.count))")
            ForEach(copies) { inst in
                copyRow(inst)
                if inst.id != copies.last?.id { Divider().overlay(Palette.stroke) }
            }
            if copies.count == 1 {
                Label("You can't sell your last copy — it stays safe in your collection.",
                      systemImage: "lock.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.subtle)
                    .padding(.top, 2)
            } else {
                Label("The shop buys extra copies at \(Int((Economy.sellbackRate * 100).rounded()))% of market value.",
                      systemImage: "tag.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.subtle)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private func copyRow(_ inst: CardInstance) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    if inst.foil { badge("★ FOIL", Color(hex: "ff8ad6")) }
                    if let g = inst.grade { badge("PSA \(g)", gradeColor(g)) }
                    if !inst.foil && inst.grade == nil {
                        Text("Standard").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.subtle)
                    }
                }
                Text(inst.currentValue.money)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.money)
            }
            Spacer(minLength: 0)
            VStack(spacing: 6) {
                miniButton("Sell \(inst.sellValue.moneyShort)", "dollarsign.circle.fill", Color(hex: "2fae63"),
                           enabled: game.isSellable(inst)) {
                    if game.sell(inst.id) != nil { Haptics.play(.success); Sound.play(.coin) }
                    else { Haptics.play(.error) }
                }
                if inst.card.rarity.canBeGraded && inst.grade == nil {
                    miniButton("Grade \(Economy.gradeFee(set: card.set).money)", "seal.fill",
                               Color(hex: "6d5cf7"),
                               enabled: game.canAffordGrade(set: card.set)) {
                        if let r = game.grade(inst.id) { Haptics.play(.rigid); gradeResult = r }
                        else { Haptics.play(.error) }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: Helpers

    private func sectionHeader(_ t: String) -> some View {
        Text(t.uppercased())
            .font(.system(size: 12, weight: .black))
            .foregroundStyle(Palette.subtle)
    }

    private func badge(_ t: String, _ color: Color) -> some View {
        Text(t)
            .font(.system(size: 10, weight: .black))
            .foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color))
    }

    private func miniButton(_ title: String, _ icon: String, _ tint: Color,
                            enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .padding(.vertical, 7).padding(.horizontal, 12)
                .frame(minWidth: 118)
                .background(Capsule().fill(enabled ? tint : Palette.stroke))
                .opacity(enabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// MARK: - Grade reveal

struct GradeRevealOverlay: View {
    let result: GradeResult
    let onClose: () -> Void
    @State private var shown = false

    private enum ValueDirection { case up, neutral, down }
    private var direction: ValueDirection {
        if abs(result.newValue - result.oldValue) < 0.001 { return .neutral }
        return result.newValue > result.oldValue ? .up : .down
    }
    private var directionColor: Color {
        switch direction {
        case .up:      return Palette.money
        case .neutral: return Palette.text
        case .down:    return Color(hex: "e0663b")
        }
    }
    private var directionText: String {
        switch direction {
        case .up:      return "▲ Value up!"
        case .neutral: return "▬ Value neutral"
        case .down:    return "▼ Value down"
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
                .onTapGesture { onClose() }
            VStack(spacing: 14) {
                Text("GRADED")
                    .font(.system(size: 13, weight: .black)).tracking(3)
                    .foregroundStyle(Palette.subtle)
                Text("PSA \(result.grade)")
                    .font(.system(size: 60, weight: .black, design: .rounded))
                    .foregroundStyle(gradeColor(result.grade))
                Text(Economy.gradeLabel(result.grade))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Palette.text)

                HStack(spacing: 18) {
                    valueColumn("Was", result.oldValue, Palette.subtle)
                    Image(systemName: "arrow.right").foregroundStyle(Palette.subtle)
                    valueColumn("Now", result.newValue, directionColor)
                }
                .padding(.top, 4)

                Text(directionText)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(directionColor)

                Button {
                    onClose()
                } label: {
                    Text("Continue")
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                        .padding(.vertical, 10).padding(.horizontal, 40)
                        .background(Capsule().fill(Palette.panelHi))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(28)
            .background(RoundedRectangle(cornerRadius: 22).fill(Palette.panel))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Palette.stroke, lineWidth: 1))
            .padding(36)
            .scaleEffect(shown ? 1 : 0.7)
            .opacity(shown ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { shown = true }
        }
    }

    private func valueColumn(_ label: String, _ value: Double, _ tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(label).font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.subtle)
            Text(value.money).font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(tint)
        }
    }
}
