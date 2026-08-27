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

/// A compact "Lv N" pill with the mode's gold accent. Even a maxed Trainer shows
/// its number rather than "MAX" — the cap is surfaced in the XP row instead. (req 3)
private struct LevelPill: View {
    let level: Int
    var body: some View {
        Text("Lv \(level)")
            .font(.system(size: 11, weight: .black, design: .rounded))
            .foregroundStyle(Color(hex: "1a0d2e"))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(
                LinearGradient(colors: GauntletTheme.gold, startPoint: .leading, endPoint: .trailing)))
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

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                GauntletHeader(eyebrow: "Gauntlet", title: "Choose your Trainer")
                HStack {
                    Spacer()
                    Button { Haptics.play(.light); state.showIntro() } label: {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 24))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color(hex: "b06cf7"))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("How Gauntlet works")
                }
            }
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(state.trainers) { trainer in
                        TrainerCard(
                            trainer: trainer,
                            unlocked: state.isTrainerUnlocked(trainer),
                            unlockProgress: state.unlockProgress(for: trainer),
                            level: state.level(for: trainer),
                            maxLevel: state.maxTrainerLevel,
                            xp: state.xp(for: trainer),
                            xpToNext: state.xpToNext(for: trainer)
                        ) { state.chooseTrainer(trainer) }
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }
}

private struct TrainerCard: View {
    let trainer: Trainer
    let unlocked: Bool
    let unlockProgress: (have: Int, need: Int)?
    let level: Int
    let maxLevel: Int
    let xp: Int
    let xpToNext: Int?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(trainer.name)
                        .font(.system(size: 19, weight: .heavy, design: .rounded))
                        .foregroundStyle(unlocked ? .white : Palette.subtle)
                    Spacer()
                    if unlocked {
                        LevelPill(level: level)
                    } else {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Palette.subtle)
                    }
                }
                Text(trainer.blurb)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.subtle)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if unlocked {
                    if let xpToNext {
                        let span = xp + xpToNext
                        ProgressBar(value: Double(xp), total: Double(max(span, 1)),
                                    tint: Color(hex: "b06cf7"), height: 6)
                        Text("\(xp) XP · \(xpToNext) to next level")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Palette.subtle)
                    } else {
                        // Maxed: a full gold bar and the cap shown where XP-to-next
                        // normally lives. (req 3)
                        ProgressBar(value: 1, total: 1,
                                    tint: Color(hex: "ffd54a"), height: 6)
                        Text("MAX LEVEL \(maxLevel) · \(xp) XP")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(Color(hex: "ffd54a"))
                    }
                } else if let u = trainer.unlock {
                    Divider().overlay(Palette.stroke)
                    HStack(spacing: 6) {
                        Image(systemName: "target")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(hex: "ffd54a"))
                        Text(u.summary)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let p = unlockProgress {
                        ProgressBar(value: Double(p.have), total: Double(max(p.need, 1)),
                                    tint: Color(hex: "ffd54a"), height: 6)
                        Text("\(p.have) / \(p.need) \(u.noun)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Palette.subtle)
                    }
                }
            }
            .panel()
            .opacity(unlocked ? 1 : 0.72)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(unlocked ? Color.clear : Palette.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
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
                        TierCard(tier: tier, unlocked: state.isUnlocked(tier)) {
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
                    Text("Clear \(req.display) once to unlock.")
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
        let rips = GauntletEconomy.ripBudget(tier, round: 1)
        let slots = GauntletEconomy.startingSlots(tier)
        return "\(rips) rips/round · \(slots) showcase slots · \(GauntletEconomy.rounds(tier)) rounds"
    }
}

// MARK: - Results

struct ResultsScreen: View {
    let state: GauntletState
    let onExit: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "trophy.fill")
                .font(.system(size: 60, weight: .bold))
                .foregroundStyle(LinearGradient(colors: GauntletTheme.gold, startPoint: .top, endPoint: .bottom))
                .shadow(color: Color(hex: "ffd54a").opacity(0.5), radius: 16)
            GauntletHeader(eyebrow: "Run Cleared", title: "Gauntlet Complete")

            if let clear = state.lastClear {
                VStack(spacing: 12) {
                    HStack {
                        Text("XP Earned").foregroundStyle(Palette.subtle)
                        Spacer()
                        Text("+\(clear.xpGained)").foregroundStyle(Palette.money)
                    }
                    .font(.system(size: 15, weight: .bold))

                    if clear.leveledUp {
                        Text("LEVEL UP → Lv \(clear.newLevel)")
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .foregroundStyle(Color(hex: "b06cf7"))
                    }
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
            BigButton(title: "Play Again", systemImage: "arrow.clockwise", tint: GauntletTheme.tint) {
                Haptics.play(.light); state.finish()
            }
            Button("Back to Menu") { onExit() }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Palette.subtle)
        }
    }
}

// MARK: - Lost

struct LostScreen: View {
    let state: GauntletState
    let onExit: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 58, weight: .bold))
                .foregroundStyle(Color(hex: "e0663b"))
            GauntletHeader(eyebrow: "Gauntlet", title: "Run Over")
            if let run = state.run {
                Text("You reached round \(run.round) of \(run.roundsTotal), short of the bar. Every round is single-life in the Gauntlet.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.subtle)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
            }
            if let clear = state.lastClear, clear.xpGained > 0 {
                // Partial runs still bank XP for the rounds cleared. (req 3)
                VStack(spacing: 12) {
                    HStack {
                        Text("XP Earned").foregroundStyle(Palette.subtle)
                        Spacer()
                        Text("+\(clear.xpGained)").foregroundStyle(Palette.money)
                    }
                    .font(.system(size: 15, weight: .bold))
                    if clear.leveledUp {
                        Text("LEVEL UP → Lv \(clear.newLevel)")
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .foregroundStyle(Color(hex: "b06cf7"))
                    }
                }
                .panel()
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
                             detail: "Clear each round's target appraisal before your rips run out. Miss it and the run ends.")
                    IntroRow(icon: "square.stack.3d.up.fill", tint: Color(hex: "6d5cf7"),
                             title: "Score & synergy",
                             detail: "Showcases score on value, foils, and grades — matching elements add a synergy bonus.")
                    IntroRow(icon: "rectangle.on.rectangle.angled", tint: Color(hex: "e0663b"),
                             title: "Five element packs",
                             detail: "Start with one element pack; unlock the other four for cash, in any order.")
                    IntroRow(icon: "bolt.circle.fill", tint: Color(hex: "ffd54a"),
                             title: "Catalysts",
                             detail: "Some rips offer a Catalyst — attune it to buff the rest of your run.")
                    IntroRow(icon: "cart.fill", tint: Color(hex: "5be08a"),
                             title: "The shop, between rounds",
                             detail: "Clear a round to open the shop and buy extra Showcase and Catalyst slots.")
                    IntroRow(icon: "banknote.fill", tint: Palette.money,
                             title: "Interest rewards restraint",
                             detail: "Each clear pays a payout plus 10% interest on banked cash — saving compounds.")
                    IntroRow(icon: "person.2.fill", tint: Color(hex: "b06cf7"),
                             title: "Trainers & prizes",
                             detail: "Unlock and level Trainers by hitting milestones; each win earns a Foil Extended Art card.")
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
