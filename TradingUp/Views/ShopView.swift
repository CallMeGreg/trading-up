import SwiftUI

struct ShopView: View {
    @EnvironmentObject var game: GameState
    @State private var pending: PendingOpen?
    /// Collection counts captured at purchase time. While a reveal is on screen
    /// the shop shows these frozen values so the fullScreenCover sliding in/out
    /// never briefly spoilers how many new uniques the pack contained.
    @State private var freeze: ShopFreeze?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    CashHeader(freeze: freeze)
                    ForEach(1...CardDatabase.setCount, id: \.self) { set in
                        SetShopCard(set: set, freeze: freeze) { buyPack(set) } onBuyBox: { buyBox(set) }
                    }
                }
                .padding(16)
            }
            .background(Palette.screen.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .fullScreenCover(item: $pending) { p in
            RevealView(content: p.content, set: p.set) { pending = nil; freeze = nil }
        }
    }

    private func buyPack(_ set: Int) {
        let snapshot = ShopFreeze(game)
        guard let r = game.buyPack(set: set) else { Haptics.play(.error); return }
        freeze = snapshot
        Haptics.play(.medium)
        Sound.play(.purchase)
        pending = PendingOpen(content: .pack(r), set: set)
    }

    private func buyBox(_ set: Int) {
        let snapshot = ShopFreeze(game)
        guard let results = game.buyBoxPacks(set: set) else { Haptics.play(.error); return }
        freeze = snapshot
        Haptics.play(.heavy)
        Sound.play(.purchase)
        pending = PendingOpen(content: .box(results: results), set: set)
    }
}

/// A snapshot of the collection counts the Shop displays, captured just before a
/// pack/box is opened. Held while the reveal is on screen so the underlying shop
/// doesn't reveal the pull's new-unique count during the cover transition.
struct ShopFreeze {
    let uniqueCount: Int
    let ownedInSet: [Int: Int]

    init(_ game: GameState) {
        uniqueCount = game.uniqueCount
        var owned: [Int: Int] = [:]
        for set in 1...CardDatabase.setCount { owned[set] = game.ownedCount(inSet: set) }
        ownedInSet = owned
    }
}

// MARK: - Cash header

struct CashHeader: View {
    @EnvironmentObject var game: GameState
    var freeze: ShopFreeze? = nil

    private var uniqueCount: Int { freeze?.uniqueCount ?? game.uniqueCount }

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
                    Text("\(uniqueCount) / \(game.totalCards)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(Palette.text)
                }
                ProgressBar(value: Double(uniqueCount), total: Double(game.totalCards),
                            tint: .white)
            }
        }
        .panel()
    }
}

// MARK: - Per-set shop card

struct SetShopCard: View {
    @EnvironmentObject var game: GameState
    let set: Int
    var freeze: ShopFreeze? = nil
    let onBuyPack: () -> Void
    let onBuyBox: () -> Void

    private var element: Element { Element.theme(forSet: set) }
    private var displayUnique: Int { freeze?.uniqueCount ?? game.uniqueCount }
    private var owned: Int { freeze?.ownedInSet[set] ?? game.ownedCount(inSet: set) }
    private var packPrice: Double { Economy.packPrice(set: set) }
    private var boxPrice: Double { Economy.boxPrice(set: set) }
    private var unlockThreshold: Int { game.uniquesToUnlock(set: set) }
    private var unlocked: Bool { displayUnique >= unlockThreshold }

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
                tint: [element.palette[2], element.palette[3]],
                enabled: game.canAffordBox(set: set),
                action: onBuyBox
            )
        }
        .padding(16)
    }

    private var lockedBody: some View {
        let have = min(displayUnique, unlockThreshold)
        let remaining = max(0, unlockThreshold - displayUnique)
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

/// What a `RevealView` is opening: a single already-opened pack, or a booster
/// box whose packs are revealed one at a time (all cards are already added).
enum RevealContent {
    case pack(OpenResult)
    case box(results: [OpenResult])
}

/// Identifiable wrapper so a pending open can drive `.fullScreenCover(item:)`.
struct PendingOpen: Identifiable {
    let id = UUID()
    let content: RevealContent
    let set: Int
}
