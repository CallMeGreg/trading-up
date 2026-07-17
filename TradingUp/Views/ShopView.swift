import SwiftUI

struct ShopView: View {
    @EnvironmentObject var game: GameState
    @State private var pending: PendingOpen?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    CashHeader()
                    ForEach(1...CardDatabase.setCount, id: \.self) { set in
                        SetShopCard(set: set) { buyPack(set) } onBuyBox: { buyBox(set) }
                    }
                }
                .padding(16)
            }
            .background(Palette.screen.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .fullScreenCover(item: $pending) { p in
            RevealView(result: p.result, set: p.set) { pending = nil }
        }
    }

    private func buyPack(_ set: Int) {
        guard let r = game.buyPack(set: set) else { Haptics.play(.error); return }
        Haptics.play(.medium)
        pending = PendingOpen(result: r, set: set)
    }

    private func buyBox(_ set: Int) {
        guard let r = game.buyBox(set: set) else { Haptics.play(.error); return }
        Haptics.play(.heavy)
        pending = PendingOpen(result: r, set: set)
    }
}

// MARK: - Cash header

struct CashHeader: View {
    @EnvironmentObject var game: GameState

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CASH").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.subtle)
                    Text(game.cash.money)
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(Palette.money)
                        .contentTransition(.numericText())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("NET WORTH").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.subtle)
                    Text(game.netWorth.money)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.text)
                }
            }
            VStack(spacing: 4) {
                HStack {
                    Text("Collection").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.subtle)
                    Spacer()
                    Text("\(game.uniqueCount) / \(game.totalCards)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(Palette.text)
                }
                ProgressBar(value: Double(game.uniqueCount), total: Double(game.totalCards),
                            tint: Color(hex: "b06cf7"))
            }
        }
        .panel()
    }
}

// MARK: - Per-set shop card

struct SetShopCard: View {
    @EnvironmentObject var game: GameState
    let set: Int
    let onBuyPack: () -> Void
    let onBuyBox: () -> Void

    private var element: Element { Element.theme(forSet: set) }
    private var owned: Int { game.ownedCount(inSet: set) }
    private var packPrice: Double { Economy.packPrice(set: set) }
    private var boxPrice: Double { Economy.boxPrice(set: set) }
    private var unlocked: Bool { game.isSetUnlocked(set) }
    private var unlockThreshold: Int { game.uniquesToUnlock(set: set) }

    var body: some View {
        VStack(spacing: 0) {
            banner
            if unlocked {
                unlockedBody
            } else {
                lockedBody
            }
        }
        .background(RoundedRectangle(cornerRadius: 18).fill(Palette.panel))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Palette.stroke, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var unlockedBody: some View {
        VStack(spacing: 12) {
            HStack {
                Text("\(owned) / 50 collected")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.subtle)
                Spacer()
                if owned == 50 {
                    Label("Complete", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Palette.money)
                }
            }
            ProgressBar(value: Double(owned), total: 50, tint: element.palette[1])

            BigButton(
                title: "Buy Pack",
                subtitle: "6 cards · \(packPrice.money)",
                systemImage: "shippingbox.fill",
                tint: [element.palette[1], element.palette[2]],
                enabled: game.canAffordPack(set: set),
                action: onBuyPack
            )
            BigButton(
                title: "Buy Booster Box",
                subtitle: "\(Economy.boxPacks) packs · \(boxPrice.money) · ≥\(Economy.boxGuaranteeUltras) ultra, ≥\(Economy.boxGuaranteeFoils) foil",
                systemImage: "cube.box.fill",
                tint: [Color(hex: "b06cf7"), Color(hex: "6d5cf7")],
                enabled: game.canAffordBox(set: set),
                action: onBuyBox
            )
        }
        .padding(16)
    }

    private var lockedBody: some View {
        let have = min(game.uniqueCount, unlockThreshold)
        let remaining = max(0, unlockThreshold - game.uniqueCount)
        return VStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill").font(.system(size: 13, weight: .bold))
                Text("Locked").font(.system(size: 14, weight: .bold))
                Spacer()
                Text("\(have) / \(unlockThreshold)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(Palette.text)
            }
            .foregroundStyle(Palette.subtle)

            Text("Collect **\(remaining) more** unique card\(remaining == 1 ? "" : "s") (\(unlockThreshold) total) to unlock \(CardDatabase.setName(set)).")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.subtle)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            ProgressBar(value: Double(have), total: Double(unlockThreshold), tint: element.palette[1])
        }
        .padding(16)
    }

    private var banner: some View {
        ZStack {
            LinearGradient(colors: [element.palette[2], element.palette[3]],
                           startPoint: .leading, endPoint: .trailing)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SET \(set)").font(.system(size: 11, weight: .black)).foregroundStyle(.white.opacity(0.75))
                    Text(CardDatabase.setName(set))
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }
                Spacer()
                if !unlocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 74)
        .saturation(unlocked ? 1 : 0.3)
        .opacity(unlocked ? 1 : 0.85)
    }
}

/// Identifiable wrapper so an `OpenResult` can drive `.fullScreenCover(item:)`.
struct PendingOpen: Identifiable {
    let id = UUID()
    let result: OpenResult
    let set: Int
}
