import SwiftUI

/// The Collectors' Guild, reached from New Run. Spend Renown on permanent
/// upgrades, pick your Trainer, choose one of three Grails, and start the Hunt.
struct GuildView: View {
    @Environment(ChaseState.self) private var state
    @State private var selectedTrainer: TrainerKind = .digger
    @State private var selectedTier: GrailTier? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                renownHeader
                grailSection
                trainerSection
                upgradeSection
                startButton
            }
            .padding(20)
            .readableWidth()
        }
        .navigationTitle("Collectors' Guild")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if state.pendingGrails.isEmpty { state.rollGrails() } }
    }

    // MARK: Renown

    private var renownHeader: some View {
        HStack {
            Image(systemName: "seal.fill").foregroundStyle(Color(hex: "ffd54a"))
            Text("\(Int(state.renown)) Renown").font(.system(size: 18, weight: .heavy, design: .rounded))
            Spacer()
        }
        .foregroundStyle(Palette.text)
        .panel(14)
    }

    // MARK: Grail choice

    private var grailSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Choose your Grail")
            ForEach(state.pendingGrails, id: \.tier) { grail in
                grailRow(grail)
            }
        }
    }

    private func grailRow(_ grail: Grail) -> some View {
        let selected = selectedTier == grail.tier
        return Button {
            selectedTier = grail.tier
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(grail.tier.label.uppercased())
                        .font(.system(size: 10, weight: .heavy)).tracking(2)
                        .foregroundStyle(tierColor(grail.tier))
                    Text(grail.headline).font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.text)
                    Text("Land for $\(Int(grail.price)) · +\(Int(Economy.grailBounty(tier: grail.tier))) Renown bounty")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.subtle)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20)).foregroundStyle(selected ? Palette.money : Palette.stroke)
            }
            .panel(14)
            .overlay(RoundedRectangle(cornerRadius: 18)
                .strokeBorder(selected ? Palette.money : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    // MARK: Trainer choice

    private var trainerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Pick your Trainer")
            ForEach(TrainerKind.allCases) { trainer in
                trainerRow(trainer)
            }
        }
    }

    private func trainerRow(_ trainer: TrainerKind) -> some View {
        let unlocked = state.meta.isTrainerUnlocked(trainer)
        let selected = selectedTrainer == trainer && unlocked
        return Button {
            if unlocked { selectedTrainer = trainer }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(trainer.title).font(.system(size: 15, weight: .bold))
                        .foregroundStyle(unlocked ? Palette.text : Palette.subtle)
                    Text(unlocked ? trainer.blurb : "Locked — recruit at the Guild below.")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.subtle)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: unlocked ? (selected ? "checkmark.circle.fill" : "circle") : "lock.fill")
                    .font(.system(size: 18)).foregroundStyle(selected ? Palette.money : Palette.stroke)
            }
            .panel(14)
            .overlay(RoundedRectangle(cornerRadius: 18)
                .strokeBorder(selected ? Palette.money : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .opacity(unlocked ? 1 : 0.7)
    }

    // MARK: Guild upgrades

    private var upgradeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Spend Renown")
            ForEach(GuildUpgrade.allCases) { upgrade in
                upgradeRow(upgrade)
            }
        }
    }

    private func upgradeRow(_ upgrade: GuildUpgrade) -> some View {
        let cost = state.meta.upgradeCost(upgrade)
        let canBuy = state.canAffordUpgrade(upgrade)
        let maxed = !state.meta.canUpgrade(upgrade)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(upgrade.title).font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.text)
                Text(upgrade.blurb).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.subtle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if maxed {
                Text("Maxed").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.subtle)
            } else if let cost {
                Button {
                    state.purchaseUpgrade(upgrade)
                } label: {
                    Text("\(Int(cost))")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .padding(.vertical, 7).padding(.horizontal, 12)
                        .background(Capsule().fill(canBuy ? Palette.money.opacity(0.2) : Palette.bg0))
                        .foregroundStyle(canBuy ? Palette.money : Palette.subtle)
                        .overlay(Capsule().strokeBorder(canBuy ? Palette.money : Palette.stroke, lineWidth: 1))
                }
                .buttonStyle(.plain).disabled(!canBuy)
            }
        }
        .panel(14)
    }

    // MARK: Start

    private var startButton: some View {
        let grail = state.pendingGrails.first { $0.tier == selectedTier }
        return BigButton(title: "Start the Hunt",
                         subtitle: grail.map { "Chase: \($0.headline)" } ?? "Choose a Grail above",
                         systemImage: "figure.run",
                         tint: [Palette.money, Color(hex: "39c46e")],
                         enabled: grail != nil) {
            if let grail { state.startHunt(grail: grail, trainer: selectedTrainer) }
        }
        .padding(.top, 4)
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t.uppercased()).font(.system(size: 11, weight: .heavy)).tracking(2).foregroundStyle(Palette.subtle)
    }

    private func tierColor(_ tier: GrailTier) -> Color {
        switch tier {
        case .easy:   return Palette.money
        case .medium: return Palette.tapCue
        case .hard:   return Color(hex: "b06cf7")
        }
    }
}
