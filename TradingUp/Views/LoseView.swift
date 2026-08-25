import SwiftUI

/// Shown when a Season busts — net worth fell short of the Show's Quota with no
/// legal move left. It banks the run's Renown, lets the player spend it at the
/// Guild on permanent upgrades that carry into every future Season, and doubles
/// as a "look what you pulled" review before the next New Season.
struct LoseView: View {
    @Environment(GameState.self) var game: GameState
    private var s: Stats { game.stats }
    @State private var confirmNew = false
    @State private var selected: Card?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "2a1414"), Palette.bg0],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    header
                    statsRow
                    GuildPanel()
                    CollectionReview { selected = $0 }
                }
                .padding(16)
                .readableWidth()
            }
        }
        .safeAreaInset(edge: .bottom) { resetBar }
        .sheet(item: $selected) { card in
            CardDetailView(card: card)
        }
        .onAppear { Haptics.play(.error) }
        .alert("Start a new Season?", isPresented: $confirmNew) {
            Button("Cancel", role: .cancel) {}
            Button("New Season", role: .destructive) { Haptics.play(.medium); game.startNewSeason() }
        } message: {
            Text("Your binder and cash reset, but your Guild upgrades, Renown and milestones carry over. You'll start with \(Economy.startingStake(stakeLevel: game.guildLevel(.stake)).money).")
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("💥").font(.system(size: 64)).padding(.top, 28)
            Text("BUSTED")
                .font(.system(size: 14, weight: .black)).tracking(3)
                .foregroundStyle(Color(hex: "e0663b"))
            Text("Season Over")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Text("You reached Show \(game.show) but couldn't clear the \(game.currentQuota.money) Quota. You've banked **\(game.renown)★ Renown** — spend it at the Guild.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Palette.subtle)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            StatTile(label: "Best Show", value: "\(game.show)/\(game.seasonShows)", tint: Color(hex: "5aa9ff"))
            StatTile(label: "Packs Opened", value: "\(s.packsOpened)")
            StatTile(label: "Best Grade", value: s.bestGrade == 0 ? "—" : "PSA \(s.bestGrade)", tint: Color(hex: "ffd54a"))
        }
    }

    /// Pinned to the bottom so "start a new Season" stays obvious no matter how
    /// far the player has scrolled through their haul or the Guild.
    private var resetBar: some View {
        BigButton(title: "New Season",
                  subtitle: "Keep your Guild, Renown & milestones",
                  systemImage: "arrow.counterclockwise",
                  tint: [Color(hex: "e0663b"), Color(hex: "c0442b")]) {
            confirmNew = true
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .readableWidth()
        .background(
            LinearGradient(colors: [Palette.bg0.opacity(0), Color(hex: "1a0d0d").opacity(0.9), Color(hex: "12070a")],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

/// The Guild: spend Renown banked from finished Seasons on permanent upgrades.
/// Shown on the Season Over and Champion screens — the only places a Season ends.
struct GuildPanel: View {
    @Environment(GameState.self) var game: GameState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("THE GUILD")
                    .font(.system(size: 12, weight: .black)).tracking(1.5).foregroundStyle(Palette.subtle)
                Spacer()
                Label("\(game.renown)", systemImage: "star.circle.fill")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(Color(hex: "b06cf7"))
            }
            Text("Permanent upgrades. They stay with you across every future Season.")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.subtle)
            ForEach(GuildUpgrade.allCases) { u in
                GuildRow(upgrade: u)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }
}

struct GuildRow: View {
    @Environment(GameState.self) var game: GameState
    let upgrade: GuildUpgrade

    private var level: Int { game.guildLevel(upgrade) }
    private var maxLevel: Int { game.guildMaxLevel(upgrade) }
    private var maxed: Bool { level >= maxLevel }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(upgrade.name).font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.text)
                Text(upgrade.blurb).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Palette.subtle)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                levelDots
            }
            Spacer(minLength: 8)
            buyButton
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Palette.bg0.opacity(0.5)))
    }

    private var levelDots: some View {
        HStack(spacing: 4) {
            ForEach(0..<maxLevel, id: \.self) { i in
                Circle()
                    .fill(i < level ? Color(hex: "b06cf7") : Palette.stroke)
                    .frame(width: 7, height: 7)
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder private var buyButton: some View {
        if maxed {
            Text("MAXED")
                .font(.system(size: 11, weight: .black)).foregroundStyle(Palette.subtle)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Capsule().fill(Palette.bg0.opacity(0.6)))
        } else {
            Button {
                if game.buyGuildUpgrade(upgrade) { Haptics.play(.success); Sound.play(.purchase) }
                else { Haptics.play(.error) }
            } label: {
                VStack(spacing: 1) {
                    Text("\(game.guildCost(upgrade))★").font(.system(size: 14, weight: .black, design: .rounded))
                    Text("Buy").font(.system(size: 9, weight: .bold)).opacity(0.85)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(
                    Capsule().fill(
                        game.canBuyGuild(upgrade)
                            ? LinearGradient(colors: [Color(hex: "b06cf7"), Color(hex: "6d5cf7")],
                                             startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [Palette.stroke, Palette.stroke], startPoint: .leading, endPoint: .trailing)
                    )
                )
                .opacity(game.canBuyGuild(upgrade) ? 1 : 0.5)
            }
            .buttonStyle(.plain)
            .disabled(!game.canBuyGuild(upgrade))
        }
    }
}
