import SwiftUI

struct StatsView: View {
    @EnvironmentObject var game: GameState
    @ObservedObject private var sound = SoundManager.shared
    @State private var confirmNew = false

    private var s: Stats { game.stats }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack(spacing: 12) {
                        StatTile(label: "Cash", value: game.cash.moneyShort, tint: Palette.money)
                        StatTile(label: "Collection Value", value: game.collectionValue.moneyShort)
                        StatTile(label: "Net Worth", value: game.netWorth.moneyShort, tint: Color(hex: "b06cf7"))
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        header("Collection")
                        HStack {
                            Text("Unique cards").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.subtle)
                            Spacer()
                            Text("\(game.uniqueCount) / \(game.totalCards)")
                                .font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(Palette.text)
                        }
                        ProgressBar(value: Double(game.uniqueCount), total: Double(game.totalCards), tint: .white)
                        SetBreakdown()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panel()

                    VStack(alignment: .leading, spacing: 12) {
                        header("Haul")
                        grid([
                            ("Packs Opened", "\(s.packsOpened)"),
                            ("Boxes Opened", "\(s.boxesOpened)"),
                            ("Best Grade", s.bestGrade == 0 ? "—" : "PSA \(s.bestGrade)"),
                            ("Cards Pulled", "\(s.cardsPulled)"),
                            ("Ultras Pulled", "\(s.ultrasPulled)"),
                            ("Foils Pulled", "\(s.foilsPulled)"),
                        ])
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panel()

                    VStack(alignment: .leading, spacing: 12) {
                        header("Economy")
                        grid([
                            ("Spent", s.moneySpent.moneyShort),
                            ("Earned", s.moneyEarned.moneyShort),
                            ("Cards Sold", "\(s.cardsSold)"),
                            ("Peak Cash", s.peakCash.moneyShort),
                            ("Peak Card", s.peakCardValue == 0 ? "—" : s.peakCardValue.moneyShort),
                            ("Peak Sale", s.peakSale == 0 ? "—" : s.peakSale.moneyShort),
                        ])
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panel()

                    VStack(alignment: .leading, spacing: 12) {
                        header("Settings")
                        Toggle(isOn: $sound.isEnabled) {
                            Label("Sound Effects",
                                  systemImage: sound.isEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Palette.text)
                        }
                        .tint(Palette.money)
                        .onChange(of: sound.isEnabled) { _, on in
                            Haptics.play(.light)
                            if on { Sound.play(.coin) }   // brief confirmation you can hear
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panel()

                    Button {
                        confirmNew = true
                    } label: {
                        Label("New Game", systemImage: "arrow.counterclockwise")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(hex: "e0663b"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(hex: "e0663b").opacity(0.5), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
            }
            .background(Palette.screen.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .alert("Start a new game?", isPresented: $confirmNew) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) { game.newGame() }
            } message: {
                Text("This erases your current collection and cash, and starts over with \(Economy.startingCash.money).")
            }
        }
    }

    private func header(_ t: String) -> some View {
        Text(t.uppercased()).font(.system(size: 12, weight: .black)).foregroundStyle(Palette.subtle)
    }

    private func grid(_ items: [(String, String)]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(items, id: \.0) { item in
                StatTile(label: item.0, value: item.1)
            }
        }
    }
}

/// Per-set owned/50 progress rows. Shared by Stats / Win / Lose.
struct SetBreakdown: View {
    @EnvironmentObject var game: GameState

    var body: some View {
        VStack(spacing: 9) {
            ForEach(1...CardDatabase.setCount, id: \.self) { set in
                let owned = game.ownedCount(inSet: set)
                HStack(spacing: 10) {
                    Text(CardDatabase.setName(set))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.text)
                        .frame(width: 96, alignment: .leading)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    ProgressBar(value: Double(owned), total: 50, tint: Element.theme(forSet: set).palette[1], height: 7)
                    Text("\(owned)/50")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(owned == 50 ? Palette.money : Palette.subtle)
                        .frame(width: 46, alignment: .trailing)
                }
            }
        }
    }
}
