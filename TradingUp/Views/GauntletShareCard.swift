import SwiftUI
import UIKit

/// A self-contained, fixed-width snapshot of a finished Gauntlet run, designed to
/// be rasterized by `ImageRenderer` and shared as an image (req 7). It leads with
/// the prize the player chose, then spells out the run's identity — Trainer,
/// difficulty, the Showcase they built, and the Catalysts they attuned — with app
/// branding so the shared image stands on its own.
struct GauntletShareCard: View {
    let trainer: Trainer
    let tier: GauntletTier
    let showcase: [CardInstance]
    let attuned: [Catalyst]
    let showcaseAura: Double
    /// The chosen Extended-Art prize, or `nil` on the complete-catalogue
    /// consolation win (nothing to pick), where the card reads as a clean sweep.
    let prize: GauntletRewardOption?

    private var auraText: String {
        showcaseAura >= 1000
            ? String(format: "%.1fk", showcaseAura / 1000)
            : String(Int(showcaseAura.rounded()))
    }

    var body: some View {
        VStack(spacing: 16) {
            header
            if let prize { prizeBlock(prize) } else { consolationBlock }
            identityRow
            showcaseBlock
            if !attuned.isEmpty { attunedBlock }
        }
        .padding(24)
        .frame(width: 380)
        .background(
            ZStack {
                LinearGradient(colors: [Color(hex: "1a1030"), Palette.bg0],
                               startPoint: .top, endPoint: .bottom)
                RadialGradient(gradient: Gradient(colors: [Color(hex: "b98cff").opacity(0.4), .clear]),
                               center: .top, startRadius: 20, endRadius: 480)
            }
        )
    }

    // MARK: Pieces

    private var header: some View {
        VStack(spacing: 3) {
            Text("TRADING UP")
                .font(.system(size: 13, weight: .black)).tracking(3)
                .foregroundStyle(Color(hex: "c9a9ff"))
            Text("Gauntlet Cleared")
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private func prizeBlock(_ prize: GauntletRewardOption) -> some View {
        VStack(spacing: 7) {
            Text("PRIZE CARD")
                .font(.system(size: 10, weight: .black)).tracking(2)
                .foregroundStyle(Color(hex: "ffd54a"))
            CardView(card: prize.card, instance: prize.instance, width: 150, extendedArt: true)
        }
    }

    private var consolationBlock: some View {
        VStack(spacing: 4) {
            Text("CLEAN SWEEP")
                .font(.system(size: 11, weight: .black)).tracking(2)
                .foregroundStyle(Color(hex: "ffd54a"))
            Text("Every Extended Art already earned")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.subtle)
        }
        .padding(.vertical, 8)
    }

    /// Trainer + difficulty on the left, the Showcase Aura they reached on the right.
    private var identityRow: some View {
        HStack(spacing: 12) {
            emblem
            VStack(alignment: .leading, spacing: 2) {
                Text(trainer.name)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text(tier.display)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.subtle)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                Text("SHOWCASE AURA")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(Palette.subtle)
                Text(auraText)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(Color(hex: "b98cff"))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.1), lineWidth: 1))
    }

    private var emblem: some View {
        Group {
            if let art = UIImage(named: "trainer-\(trainer.id)") {
                Image(uiImage: art).resizable().scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Palette.stroke.opacity(0.5))
                    .overlay(Text(trainer.name.prefix(1))
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(.white))
            }
        }
        .frame(width: 48, height: 48)
    }

    @ViewBuilder private var showcaseBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SHOWCASE · \(showcase.count) CARD\(showcase.count == 1 ? "" : "S")")
                .font(.system(size: 10, weight: .black)).tracking(1)
                .foregroundStyle(Palette.subtle)
            if showcase.isEmpty {
                Text("Won on Catalysts alone.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.subtle)
            } else {
                let cols = showcaseColumns
                let width = showcaseCardWidth(columns: cols)
                let rows = stride(from: 0, to: showcase.count, by: cols).map {
                    Array(showcase[$0..<min($0 + cols, showcase.count)])
                }
                VStack(spacing: Self.showcaseSpacing) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: Self.showcaseSpacing) {
                            ForEach(row) { inst in
                                CardView(card: inst.card, instance: inst, width: width)
                            }
                            if row.count < cols { Spacer(minLength: 0) }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Showcase grid sizing

    /// The share card renders *every* Showcase card — no cap, no "+N more" — so
    /// the shared image never hides part of what the player built. To keep a wide
    /// Showcase from growing very tall, the grid adapts: it packs more (smaller)
    /// thumbnails per row to stay within ~2 rows, shrinking them only down to a
    /// legible floor before it lets a third row form.
    private var showcaseColumns: Int {
        let count = showcase.count
        let byTwoRows = Int((Double(count) / 2.0).rounded(.up))
        return min(max(Self.showcaseBaseColumns, byTwoRows), Self.showcaseMaxColumns)
    }

    private func showcaseCardWidth(columns: Int) -> CGFloat {
        let gaps = Self.showcaseSpacing * CGFloat(columns - 1)
        let fitted = (Self.showcaseContentWidth - gaps) / CGFloat(columns)
        return min(Self.showcaseMaxCardWidth, fitted)
    }

    /// Usable width inside the fixed 380-pt card after its 24-pt side padding.
    private static let showcaseContentWidth: CGFloat = 380 - 24 * 2
    private static let showcaseSpacing: CGFloat = 6
    /// The app's standard 5-up grid at full thumbnail size for small Showcases.
    private static let showcaseBaseColumns = 5
    private static let showcaseMaxCardWidth: CGFloat = 56
    /// Don't shrink thumbnails below this — beyond it, add a row instead.
    private static let showcaseMinCardWidth: CGFloat = 42
    private static var showcaseMaxColumns: Int {
        Int((showcaseContentWidth + showcaseSpacing) / (showcaseMinCardWidth + showcaseSpacing))
    }

    private var attunedBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ATTUNED · \(attuned.count)")
                .font(.system(size: 10, weight: .black)).tracking(1)
                .foregroundStyle(Palette.subtle)
            FlexWrap(attuned) { catalyst in
                HStack(spacing: 5) {
                    Circle().fill(catalyst.element.badgeTint).frame(width: 8, height: 8)
                    Text(catalyst.name)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Palette.text)
                }
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(Capsule().fill(catalyst.element.badgeTint.opacity(0.14)))
                .overlay(Capsule().strokeBorder(catalyst.element.badgeTint.opacity(0.4), lineWidth: 1))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A tiny wrapping row for the attuned Catalyst chips — a self-contained flow so
/// the share card doesn't depend on the run screen's private layout helpers, and
/// so `ImageRenderer` lays every chip out (no lazy offscreen culling).
private struct FlexWrap<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let content: (Item) -> Content

    init(_ items: [Item], @ViewBuilder content: @escaping (Item) -> Content) {
        self.items = items
        self.content = content
    }

    /// Chunk into rows of up to three chips — plenty for a run's Catalyst count.
    private var rows: [[Item]] {
        stride(from: 0, to: items.count, by: 3).map {
            Array(items[$0..<min($0 + 3, items.count)])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    ForEach(row) { content($0) }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}
