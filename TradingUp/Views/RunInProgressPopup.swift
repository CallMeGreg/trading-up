import SwiftUI

/// Which step of the run-in-progress flow the popup is showing for a mode the
/// player just tapped. `resume` offers Continue vs. New Run; `confirm` is the
/// destructive "this wipes your run" gate that New Run leads to.
enum RunPopupStep: Equatable {
    case resume(MenuRoute)
    case confirm(MenuRoute)

    var mode: MenuRoute {
        switch self {
        case .resume(let m), .confirm(let m): return m
        }
    }
}

/// The in-theme replacement for the two standard iOS dialogs that used to ask
/// whether to resume a run or start over (req 3, "Compact Rail" design). A small
/// solid panel with the menu-tile accent rail on its leading edge, a mode-tinted
/// eyebrow, and two side-by-side buttons — the affirmative action always on the
/// right. The destructive confirm swaps in a shared warm danger gradient, since
/// the app has no red of its own.
struct RunInProgressCard: View {
    let step: RunPopupStep
    var onContinue: (MenuRoute) -> Void
    var onNewRun: (MenuRoute) -> Void
    var onConfirm: (MenuRoute) -> Void
    var onCancel: () -> Void

    private static let danger = [Color(hex: "ff5a5f"), Color(hex: "df342d")]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow)
                .font(.system(size: 11.5, weight: .heavy))
                .tracking(1.1)
                .foregroundStyle(eyebrowColor)

            Text(title)
                .font(.system(size: 19, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2).minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)

            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.subtle)
                .fixedSize(horizontal: false, vertical: true)

            buttons
                .padding(.top, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 17)
        .padding(.leading, 20)
        .padding(.trailing, 16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Palette.panel)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: railColors, startPoint: .top, endPoint: .bottom))
                        .frame(width: 5)
                        .padding(.vertical, 14)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Palette.stroke, lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.5), radius: 22, y: 12)
    }

    // MARK: Buttons

    @ViewBuilder
    private var buttons: some View {
        let mode = step.mode
        switch step {
        case .resume:
            // Continue sits on the right (the affirmative action).
            HStack(spacing: 10) {
                popupButton(label: "New Run", icon: "arrow.counterclockwise",
                            style: .ghost) { onNewRun(mode) }
                popupButton(label: "Continue", icon: "play.fill",
                            style: .filled(modeGradient(mode))) { onContinue(mode) }
            }
        case .confirm:
            // The destructive action sits on the right, in the danger gradient.
            HStack(spacing: 10) {
                popupButton(label: "Cancel", icon: nil,
                            style: .ghost) { onCancel() }
                popupButton(label: "Start New Run", icon: "arrow.counterclockwise",
                            style: .filled(Self.danger)) { onConfirm(mode) }
            }
        }
    }

    private enum PillStyle {
        case ghost
        case filled([Color])
    }

    private func popupButton(label: String, icon: String?, style: PillStyle,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 13, weight: .bold))
                }
                Text(label)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(pillBackground(style))
        }
        .buttonStyle(PopupPressStyle())
        .accessibilityIdentifier(label)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private func pillBackground(_ style: PillStyle) -> some View {
        switch style {
        case .ghost:
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Palette.panelHi)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Palette.stroke, lineWidth: 1)
                )
        case .filled(let colors):
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
        }
    }

    // MARK: Copy & styling per step

    private var eyebrow: String {
        switch step {
        case .resume(let m): return "\(modeName(m)) · Run in progress".uppercased()
        case .confirm:       return "Heads up".uppercased()
        }
    }

    private var eyebrowColor: Color {
        switch step {
        case .resume(let m): return accent(m)
        case .confirm:       return Color(hex: "ff6b6b")
        }
    }

    private var title: String {
        switch step {
        case .resume:        return "Pick up where you left off?"
        case .confirm(let m): return "Start a new \(modeName(m)) run?"
        }
    }

    private var message: String {
        switch step {
        case .resume:
            return "Continue this run, or start over with a fresh one."
        case .confirm(.classic):
            return "This erases your current Classic collection and cash, and starts over with \(Economy.startingCash.money). Your all-time record is kept."
        case .confirm(.gauntlet):
            return "This discards your in-progress Gauntlet run so it won't resume. Your unlocked trainers and difficulties are kept."
        case .confirm:
            return ""
        }
    }

    private var railColors: [Color] {
        switch step {
        case .resume(let m): return [accent(m), accent(m).opacity(0.6)]
        case .confirm:       return Self.danger
        }
    }

    private func modeName(_ mode: MenuRoute) -> String {
        mode == .classic ? "Classic" : "Gauntlet"
    }

    private func accent(_ mode: MenuRoute) -> Color {
        mode == .classic ? Color(hex: "56d98a") : Color(hex: "b98cff")
    }

    private func modeGradient(_ mode: MenuRoute) -> [Color] {
        mode == .classic
            ? [Color(hex: "2fb673"), Color(hex: "56d98a")]
            : [Color(hex: "6d5cf7"), Color(hex: "b06cf7")]
    }
}

/// A gentle press-scale for the popup's buttons, mirroring the menu tiles.
private struct PopupPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
