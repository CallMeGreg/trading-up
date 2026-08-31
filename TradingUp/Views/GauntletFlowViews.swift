import SwiftUI

// MARK: - Shared bits

/// A small screen title with an eyebrow line, in the mode's voice.
private struct GauntletHeader: View {
    let eyebrow: String
    let title: String
    var body: some View {
        VStack(spacing: 4) {
            Text(eyebrow.uppercased())
                .font(.system(size: 12, weight: .black)).tracking(3)
                .foregroundStyle(Palette.subtle)
            Text(title)
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
        }
    }
}

/// A Trainer's signature accent, matching the colour its emblem is drawn in by
/// tools/generate_trainer_art.py — used to tint its skill graph.
func trainerSignatureColor(_ id: String) -> Color {
    switch id {
    case "ripper":    return Color(hex: "ff6b9d")
    case "curator":   return Color(hex: "9b6cf7")
    case "appraiser": return Color(hex: "74d680")
    case "grader":    return Color(hex: "ffd54a")
    case "merchant":  return Color(hex: "ff9f43")
    case "red":       return Color(hex: "ff3b3b")
    default:           return Color(hex: "8a94a6")   // Rookie / unknown
    }
}

/// The colour and one-letter tag for a difficulty's accomplishment badge.
private func tierBadge(_ tier: GauntletTier) -> (letter: String, color: Color) {
    switch tier {
    case .easy:   return ("E", Color(hex: "5be08a"))
    case .medium: return ("M", Color(hex: "ffd54a"))
    case .hard:   return ("H", Color(hex: "ff5e6c"))
    }
}

/// Human-readable reward tier for the tier picker & headers.
private func rewardBlurb(for tier: GauntletTier) -> String {
    switch tier {
    case .easy:   return "Common Foil Extended Art"
    case .medium: return "Uncommon Foil Extended Art"
    case .hard:   return "Rare / Ultra Foil Extended Art"
    }
}

// MARK: - Trainer select

struct TrainerSelectScreen: View {
    let state: GauntletState

    /// Unlocked Trainers first (in roster order), then locked ones — so the
    /// playable roster always sits up top. (req 12)
    private var orderedTrainers: [Trainer] {
        state.trainers.filter { state.isTrainerUnlocked($0) }
            + state.trainers.filter { !state.isTrainerUnlocked($0) }
    }

    var body: some View {
        VStack(spacing: 16) {
            GauntletHeader(eyebrow: "Gauntlet", title: "Choose your Trainer")
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(orderedTrainers) { trainer in
                        TrainerCard(
                            trainer: trainer,
                            unlocked: state.isTrainerUnlocked(trainer),
                            unlockProgress: state.unlockProgress(for: trainer),
                            clearedTiers: state.clearedTiers(for: trainer)
                        ) { state.chooseTrainer(trainer) }
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }
}

struct TrainerCard: View {
    let trainer: Trainer
    let unlocked: Bool
    let unlockProgress: (have: Int, need: Int)?
    let clearedTiers: Set<GauntletTier>
    let action: () -> Void

    /// A locked *mystery* Trainer (Ash) hides its name behind "???" until it's
    /// earned; ordinary locked specialists still show their name.
    private var concealed: Bool { !unlocked && trainer.mysteryUntilUnlocked }
    /// Every locked Trainer hides its skills and blurb until unlocked; only the
    /// name (for non-mystery) and the unlock requirement stay visible. (req 1)
    private var statsHidden: Bool { !unlocked }
    private var accent: Color { trainerSignatureColor(trainer.id) }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                // The Trainer's identity and (hidden) skills carry the "locked"
                // dimming; the unlock instructions below stay at full strength so
                // a player can clearly read how to earn the Trainer.
                // (req: don't gray out / diminish the unlock text)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        TrainerEmblemRing(trainer: trainer, unlocked: unlocked,
                                          concealed: concealed, cleared: clearedTiers,
                                          showRing: unlocked)
                        Text(concealed ? "???" : trainer.name)
                            .font(.system(size: 19, weight: .heavy, design: .rounded))
                            .foregroundStyle(unlocked ? .white : Palette.subtle)
                        Spacer(minLength: 8)
                        if !unlocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Palette.subtle)
                        }
                    }
                    if unlocked {
                        Text(trainer.blurb)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Palette.subtle)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    SkillGraph(skills: trainer.skills, accent: accent, concealed: statsHidden)
                }
                .opacity(unlocked ? 1 : 0.72)

                if concealed, let p = unlockProgress {
                    Divider().overlay(Palette.stroke)
                    UnlockRequirement(icon: "flame.fill",
                                      text: "Beat Hard mode with every other Trainer.",
                                      have: p.have, need: p.need, noun: "Trainers")
                } else if !unlocked, let u = trainer.unlock {
                    Divider().overlay(Palette.stroke)
                    UnlockRequirement(icon: "target", text: u.summary,
                                      have: unlockProgress?.have, need: unlockProgress?.need, noun: u.noun)
                }
            }
            .panel()
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(unlocked ? Color.clear : Palette.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
    }
}

/// The Madden-style five-skill dot ladder — one row per skill: icon, name, 1–5
/// pips in the Trainer's signature colour, and, for an unlocked Trainer, the pip's
/// concrete run effect stated in muted text to the right of the pips on every skill
/// that sits off the neutral 3. Concealed rows hide the pip counts behind hollow
/// dots and drop the effect text for any locked Trainer.
private struct SkillGraph: View {
    let skills: TrainerSkills
    let accent: Color
    var concealed: Bool = false

    var body: some View {
        VStack(spacing: 5) {
            ForEach(TrainerSkillAxis.allCases, id: \.self) { axis in
                HStack(spacing: 8) {
                    Image(systemName: axis.symbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(concealed ? Palette.subtle : accent)
                        .frame(width: 16)
                    Text(axis.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(concealed ? Palette.subtle : .white.opacity(0.9))
                        .frame(width: 72, alignment: .leading)
                    PipRow(score: skills.score(axis), accent: accent, concealed: concealed)
                    if !concealed,
                       let phrase = GauntletSkillTuning.compactEffect(axis, score: skills.score(axis)) {
                        Text(phrase)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.subtle)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .layoutPriority(1)
                            .padding(.leading, 2)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(axisLabel(axis))
            }
        }
    }

    /// The row's VoiceOver line: the score, plus the pip's full run effect for an
    /// unlocked Trainer sitting off neutral (the fuller `effect` phrasing reads
    /// better aloud than the abbreviated text shown on the card).
    private func axisLabel(_ axis: TrainerSkillAxis) -> String {
        if concealed { return "\(axis.title): hidden" }
        let base = "\(axis.title): \(skills.score(axis)) of 5"
        if let phrase = GauntletSkillTuning.effect(axis, score: skills.score(axis)) {
            return "\(base). \(phrase)"
        }
        return base
    }
}

/// A row of five pips: the first `score` filled in the accent colour, the rest
/// hollow. Fully hollow when concealed.
private struct PipRow: View {
    let score: Int
    let accent: Color
    var concealed: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { i in
                let filled = !concealed && i <= score
                Circle()
                    .fill(filled ? accent : Color.clear)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().strokeBorder(
                        filled ? Color.clear
                               : (concealed ? Palette.subtle.opacity(0.5) : accent.opacity(0.35)),
                        lineWidth: 1.2))
            }
        }
    }
}

/// The three difficulty badges, lit for tiers this Trainer has cleared and dimmed
/// for those it hasn't — a compact accomplishment track.
/// One exact third of the difficulty ring — the `index`-th 120° arc stepping
/// clockwise from just right of top-centre, inset on each side by half the gap so
/// the three segments stay perfectly symmetric about the vertical.
struct TierArc: Shape {
    /// 0, 1, 2 stepping clockwise from just right of top-centre.
    let index: Int
    var count: Int = 3
    var gapDegrees: Double = 12

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let segment = 360.0 / Double(count)
        // -90° is straight up in SwiftUI's y-down space; a half-gap on each side
        // of every boundary keeps the whole ring symmetric about the vertical.
        let start = -90.0 + Double(index) * segment + gapDegrees / 2
        let end = -90.0 + Double(index + 1) * segment - gapDegrees / 2
        var path = Path()
        path.addArc(center: center, radius: radius,
                    startAngle: .degrees(start), endAngle: .degrees(end),
                    clockwise: false)
        return path
    }
}

/// A Trainer's emblem cropped into a circle and wrapped by a three-segment
/// difficulty ring — one arc per tier (Easy, Medium, Hard, clockwise from the
/// top), each lit in its badge colour once that tier is cleared. This replaces
/// the old row of E/M/H letter chips with a single at-a-glance medallion, and
/// blooms a soft halo in the Trainer's signature colour once all three fall.
struct TrainerEmblemRing: View {
    let trainer: Trainer
    let unlocked: Bool
    var concealed: Bool = false
    let cleared: Set<GauntletTier>
    /// Locked Trainers show only the bare medallion (the lock lives in the name
    /// row); the ring appears once the Trainer has been earned.
    var showRing: Bool = true

    private let size: CGFloat = 68
    private let ringWidth: CGFloat = 5
    // Sized so the circular emblem meets the ring's inner edge with no dead gap:
    // the arcs sit on a circle of radius (size - ringWidth) / 2, whose inner edge is
    // that minus ringWidth / 2 — i.e. (size - 2·ringWidth) / 2 from centre — so the
    // emblem's radius (emblemDiameter / 2) is set to exactly that. Keep these in sync.
    private let emblemDiameter: CGFloat = 58
    private let gapDegrees: Double = 12

    private var orderedTiers: [GauntletTier] {
        GauntletTier.allCases.sorted { $0.order < $1.order }
    }
    private var mastered: Bool { orderedTiers.allSatisfy(cleared.contains) }
    private var accent: Color { trainerSignatureColor(trainer.id) }

    var body: some View {
        ZStack {
            TrainerEmblem(trainer: trainer, unlocked: unlocked,
                          concealed: concealed, diameter: emblemDiameter)
            if showRing { ring }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var ring: some View {
        ZStack {
            // A soft bloom in the Trainer's colour is the "mastered" flourish.
            if mastered {
                Circle()
                    .strokeBorder(accent.opacity(0.28), lineWidth: ringWidth + 3)
                    .blur(radius: 3)
            }
            ForEach(orderedTiers.indices, id: \.self) { i in
                let tier = orderedTiers[i]
                let on = cleared.contains(tier)
                let color = tierBadge(tier).color
                TierArc(index: i, gapDegrees: gapDegrees)
                    .stroke(on ? color : Palette.stroke.opacity(0.6),
                            style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                    .shadow(color: on ? color.opacity(0.75) : .clear, radius: on ? 3 : 0)
            }
        }
        .padding(ringWidth / 2)
    }

    private var accessibilityText: String {
        if concealed { return "Mystery Trainer, locked" }
        guard unlocked else { return "\(trainer.name), locked" }
        let done = orderedTiers.filter(cleared.contains)
        guard !done.isEmpty else { return "\(trainer.name), no tiers cleared" }
        return "\(trainer.name), cleared " + done.map(\.display).joined(separator: ", ")
    }
}

/// The locked-card requirement line plus its progress bar, shared by stat
/// specialists and the mystery Trainer.
private struct UnlockRequirement: View {
    let icon: String
    let text: String
    let have: Int?
    let need: Int?
    let noun: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(hex: "ffd54a"))
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        if let have, let need {
            ProgressBar(value: Double(have), total: Double(max(need, 1)),
                        tint: Color(hex: "ffd54a"), height: 6)
            Text("\(have) / \(need) \(noun)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Palette.subtle)
        }
    }
}

/// A Trainer's signature emblem — a bespoke flat-vector badge rendered by
/// tools/generate_trainer_art.py and shipped in Assets.xcassets/TrainerArt —
/// cropped into a circle so it fills the inside of its difficulty ring. Grayed
/// and dimmed while the Trainer is still locked, matching the Gauntlet shop's
/// "faded until you can afford it" treatment.
private struct TrainerEmblem: View {
    let trainer: Trainer
    let unlocked: Bool
    var concealed: Bool = false
    var diameter: CGFloat = 56

    var body: some View {
        Group {
            if concealed {
                Circle()
                    .fill(Palette.stroke.opacity(0.5))
                    .overlay(
                        Text("?")
                            .font(.system(size: diameter * 0.46, weight: .black, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7)))
            } else if let art = UIImage(named: "trainer-\(trainer.id)") {
                Image(uiImage: art).resizable().scaledToFill()
            } else {
                Circle()
                    .fill(Palette.stroke.opacity(0.5))
                    .overlay(
                        Text(trainer.name.prefix(1))
                            .font(.system(size: diameter * 0.4, weight: .black, design: .rounded))
                            .foregroundStyle(.white))
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .saturation(unlocked ? 1 : 0.12)
        .opacity(unlocked ? 1 : 0.5)
        .accessibilityHidden(true)
    }
}

// MARK: - Tier select

struct TierSelectScreen: View {
    let state: GauntletState

    var body: some View {
        VStack(spacing: 16) {
            if let t = state.selectedTrainer {
                GauntletHeader(eyebrow: "Trainer · \(t.name)", title: "Pick a Gauntlet")
            }
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(GauntletTier.allCases, id: \.self) { tier in
                        TierCard(tier: tier, unlocked: state.isUnlocked(tier), trainer: state.selectedTrainer) {
                            state.startRun(tier: tier)
                        }
                    }
                }
            }
            Button {
                state.backToTrainerSelect()
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Palette.subtle)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct TierCard: View {
    let tier: GauntletTier
    let unlocked: Bool
    /// The currently selected Trainer, so the rip/slot figures reflect their
    /// skill adjustments rather than the tier's base values (req 5).
    var trainer: Trainer?
    let action: () -> Void

    private var accent: Color {
        switch tier {
        case .easy: return Color(hex: "3fbf7f")
        case .medium: return Color(hex: "3b82f6")
        case .hard: return Color(hex: "b06cf7")
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(tier.display)
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(unlocked ? .white : Palette.subtle)
                    Spacer()
                    if unlocked {
                        Text("\(GauntletEconomy.rounds(tier)) rounds")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(accent)
                    } else {
                        Image(systemName: "lock.fill").foregroundStyle(Palette.subtle)
                    }
                }
                if unlocked {
                    HStack(spacing: 6) {
                        Image(systemName: "gift.fill").font(.system(size: 11))
                            .foregroundStyle(Color(hex: "ffd54a"))
                        Text("Reward: \(rewardBlurb(for: tier))")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.text)
                    }
                    Text(difficultyNote)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.subtle)
                } else if let req = tier.requires {
                    Text("Clear \(req.display) with this Trainer to unlock.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.subtle)
                }
            }
            .panel()
            .overlay(RoundedRectangle(cornerRadius: 18)
                .strokeBorder(unlocked ? accent.opacity(0.5) : Palette.stroke, lineWidth: 1.5))
            .opacity(unlocked ? 1 : 0.7)
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
    }

    private var difficultyNote: String {
        let mods = trainer?.mods ?? .none
        let rips = GauntletEconomy.ripBudget(tier, round: 1) + mods.extraRipsPerRound
        let slots = GauntletEconomy.startingSlots(tier) + mods.extraSlots
        return "\(rips) rips/round · \(slots) showcase slots · \(GauntletEconomy.rounds(tier)) rounds"
    }
}

// MARK: - Results

struct ResultsScreen: View {
    let state: GauntletState
    let onExit: () -> Void

    /// Rendered snapshot of the finished run + prize, shared as an image (req 7).
    @State private var shareImage: Image?

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "trophy.fill")
                .font(.system(size: 60, weight: .bold))
                .foregroundStyle(LinearGradient(colors: GauntletTheme.gold, startPoint: .top, endPoint: .bottom))
                .shadow(color: Color(hex: "ffd54a").opacity(0.5), radius: 16)
            GauntletHeader(eyebrow: "Run Cleared", title: "Gauntlet Complete")

            if let clear = state.lastClear, clear.unlockedTier != nil || state.rewardWasConsolation {
                VStack(spacing: 12) {
                    if let unlocked = clear.unlockedTier {
                        Text("Unlocked \(unlocked.display) Gauntlet!")
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .foregroundStyle(Color(hex: "ffd54a"))
                            .multilineTextAlignment(.center)
                    }
                    if state.rewardWasConsolation {
                        Text("Every Extended Art earned — consolation paid.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Palette.subtle)
                            .multilineTextAlignment(.center)
                    }
                }
                .panel()
            }

            UnlockedTrainersBanner(trainers: state.lastUnlockedTrainers)

            Spacer()
            shareButton
            BigButton(title: "Play Again", systemImage: "arrow.clockwise", tint: GauntletTheme.tint) {
                Haptics.play(.light); state.finish()
            }
            Button("Back to Menu") { onExit() }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Palette.subtle)
        }
        .onAppear(perform: renderShareImage)
    }

    @ViewBuilder private var shareButton: some View {
        let label = BigButtonLabel(title: "Share your run",
                                   subtitle: "Trainer, showcase, catalysts & prize",
                                   systemImage: "square.and.arrow.up",
                                   tint: [Color(hex: "3b82f6"), Color(hex: "6d5cf7")])
        if let shareImage {
            ShareLink(item: shareImage,
                      preview: SharePreview("Trading Up — Gauntlet", image: shareImage)) {
                label
            }
            .buttonStyle(.plain)
        } else {
            label
        }
    }

    /// Rasterize `GauntletShareCard` from the just-finished run so the share sheet
    /// can attach it. No-op if the run is gone (defensive: results keep it around).
    @MainActor private func renderShareImage() {
        guard let run = state.run else { return }
        let card = GauntletShareCard(
            trainer: run.trainer,
            tier: run.tier,
            showcase: run.showcase,
            attuned: run.attunedCatalysts,
            showcaseAura: run.showcaseAura,
            prize: state.lastPrize
        )
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        guard let ui = renderer.uiImage else { return }
        shareImage = Image(uiImage: ui)
    }
}

// MARK: - Lost

struct LostScreen: View {
    let state: GauntletState
    let onExit: () -> Void

    /// A stable, inspirational send-off, chosen once per appearance of this screen.
    @State private var quote: String = GauntletQuotes.pool.randomElement() ?? ""

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 58, weight: .bold))
                .foregroundStyle(Color(hex: "e0663b"))
            GauntletHeader(eyebrow: "Gauntlet", title: "Run Over")
            if let run = state.run {
                VStack(spacing: 12) {
                    Text("You reached round \(run.round) of \(run.roundsTotal), short of the bar.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Palette.subtle)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                    Text("“\(quote)”")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .italic()
                        .foregroundStyle(Color(hex: "ffd54a"))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20)
                }
            }
            UnlockedTrainersBanner(trainers: state.lastUnlockedTrainers)
            Spacer()
            BigButton(title: "New Run", systemImage: "arrow.clockwise", tint: GauntletTheme.tint) {
                Haptics.play(.light); state.finish()
            }
            Button("Back to Menu") { onExit() }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Palette.subtle)
        }
    }
}

/// The pool of ten "keep going" send-offs shown on the Gauntlet loss screen. One
/// is picked at random each time a run ends — a small nudge back to the rail.
enum GauntletQuotes {
    static let pool: [String] = [
        "Every champion has a stack of runs that ended right here.",
        "The next pack could be the one. Rip again.",
        "A lost run is tuition — go spend what it taught you.",
        "Grit beats luck when you come back for another round.",
        "You found the bar. Next time, clear it.",
        "Dust off the binder. The Gauntlet isn't done with you.",
        "Comebacks are just runs that started with a loss.",
        "Fortune favors the collector who shuffles up again.",
        "Every great Showcase began with a run that fell short.",
        "Setback today, Showcase tomorrow. Keep ripping.",
    ]
}

/// Celebrates any Trainers a just-finished run unlocked (win or loss). Renders
/// nothing when none were earned.
private struct UnlockedTrainersBanner: View {
    let trainers: [Trainer]
    var body: some View {
        if !trainers.isEmpty {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 14, weight: .bold))
                    Text(trainers.count == 1 ? "New Trainer Unlocked!" : "New Trainers Unlocked!")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                }
                .foregroundStyle(Color(hex: "ffd54a"))
                ForEach(trainers) { t in
                    Text(t.name)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(hex: "ffd54a").opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color(hex: "ffd54a").opacity(0.5), lineWidth: 1)))
        }
    }
}

// MARK: - Intro / how-to explainer

/// First-run (and replayable) primer for Gauntlet Mode. Shown automatically the
/// first time the mode is opened, and any time from the ⓘ on Trainer select. It
/// frames the loop, the scoring, the shop, and how interest rewards restraint.
struct IntroScreen: View {
    let state: GauntletState

    var body: some View {
        VStack(spacing: 16) {
            GauntletHeader(eyebrow: "Welcome to", title: "Gauntlet Mode")

            ScrollView {
                VStack(spacing: 10) {
                    IntroRow(icon: "target", tint: Color(hex: "ff8ad6"),
                             title: "Hit the round's bar",
                             detail: "Clear each round's target Aura before your rips run out. Miss it and the run ends.")
                    IntroRow(icon: "square.stack.3d.up.fill", tint: Color(hex: "6d5cf7"),
                             title: "Aura & evolutions",
                             detail: "Your showcase scores on value, foils, and grades — complete an evolution line to boost its value.")
                    IntroRow(icon: "person.2.fill", tint: Color(hex: "b06cf7"),
                             title: "Trainers",
                             detail: "Each Trainer has a five-skill profile — Energy, Aura, Selling, Grading, Inventory — that shapes your run. Unlock more Trainers by hitting milestones.")
                    IntroRow(icon: "bolt.circle.fill", tint: Color(hex: "ff9500"),
                             title: "Catalysts",
                             detail: "Some packs offer a Catalyst — attune it to buff the rest of your run.")
                    IntroRow(icon: "cart.fill", tint: Color(hex: "5be08a"),
                             title: "The shop, between rounds",
                             detail: "Clear a round to open the shop and buy extra Showcase and Catalyst slots.")
                    IntroRow(icon: "trophy.fill", tint: Color(hex: "ffd54a"),
                             title: "Prizes",
                             detail: "Win a run to earn a Foil Extended Art card for your Binder.")
                }
                .padding(.bottom, 8)
            }

            BigButton(title: "Let's Rip", systemImage: "sparkles", tint: GauntletTheme.tint) {
                Haptics.play(.light); state.dismissIntro()
            }
        }
    }
}

private struct IntroRow: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Palette.subtle)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .panel()
    }
}
