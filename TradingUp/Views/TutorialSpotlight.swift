import Foundation
import SwiftUI

struct TutorialPrompt: Equatable {
    let target: String
    let title: String
    let message: String
}

extension View {
    /// Attach to the control's bounds, passing the same action used by its Button.
    /// IDs are local to the nearest tutorial host.
    func tutorialTarget(_ id: String, action: @escaping () -> Void) -> some View {
        modifier(TutorialTargetModifier(id: id, action: action))
    }

    /// Hosts descendant targets without advancing steps or scrolling for them.
    /// Wrap the whole interactive surface; content controls are preferable to
    /// native navigation/toolbar controls hosted outside that surface.
    /// Targets must fit within the safe viewport. For oversized controls, the
    /// parent must reflow the layout or target a smaller real action control;
    /// scrolling alone cannot make an oversized target fully visible.
    func tutorialHost(_ prompt: TutorialPrompt?) -> some View {
        modifier(TutorialHostModifier(prompt: prompt))
    }
}

private struct TutorialHostScopeKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}

private extension EnvironmentValues {
    var tutorialHostScope: UUID? {
        get { self[TutorialHostScopeKey.self] }
        set { self[TutorialHostScopeKey.self] = newValue }
    }
}

private struct TutorialTargetAnchor {
    let id: String
    let scope: UUID?
    let bounds: Anchor<CGRect>
    let action: () -> Void
}

private struct TutorialTargetPreferenceKey: PreferenceKey {
    static let defaultValue: [TutorialTargetAnchor] = []

    static func reduce(value: inout [TutorialTargetAnchor], nextValue: () -> [TutorialTargetAnchor]) {
        value.append(contentsOf: nextValue())
    }
}

private struct TutorialTargetModifier: ViewModifier {
    let id: String
    let action: () -> Void
    @Environment(\.tutorialHostScope) private var scope

    func body(content: Content) -> some View {
        content.anchorPreference(key: TutorialTargetPreferenceKey.self, value: .bounds) {
            [TutorialTargetAnchor(id: id, scope: scope, bounds: $0, action: action)]
        }
    }
}

private struct TutorialHostModifier: ViewModifier {
    let prompt: TutorialPrompt?
    @State private var scope = UUID()

    func body(content: Content) -> some View {
        content
            .environment(\.tutorialHostScope, scope)
            .allowsHitTesting(prompt == nil)
            // Scope visibility to a concrete accessibility container. An active
            // host also discards child actions, including navigation controls;
            // an inactive outer host must not unhide a nested host's children.
            // Keep the same view structure so activation preserves content state.
            .accessibilityElement(children: prompt == nil ? .contain : .ignore)
            .accessibilityHidden(prompt != nil)
            .overlayPreferenceValue(TutorialTargetPreferenceKey.self) { targets in
                if let prompt {
                    TutorialSpotlightOverlay(prompt: prompt, scope: scope, targets: targets)
                        .id(prompt.target)
                        .environment(\.isEnabled, true)
                }
            }
        // Do not clear preferences here: nested and sheet hosts retain their own
        // anchors, distinguished by scope rather than preference consumption.
    }
}

/// Pure geometry shared by drawing and hit testing; never moves the target itself.
enum TutorialSpotlightLayout {
    static let cornerRadius: CGFloat = 12
    static let haloPadding: CGFloat = 4
    static let coachGap: CGFloat = 12
    static let coachMargin: CGFloat = 12
    static let coachMaximumWidth: CGFloat = 380

    static func safeBounds(size: CGSize, insets: EdgeInsets) -> CGRect {
        let left = min(max(0, insets.leading), max(0, size.width))
        let top = min(max(0, insets.top), max(0, size.height))
        return CGRect(
            x: left,
            y: top,
            width: max(0, size.width - left - max(0, insets.trailing)),
            height: max(0, size.height - top - max(0, insets.bottom))
        )
    }

    static func overlayViewport(hostFrame: CGRect, overlayFrame: CGRect) -> CGRect {
        let visible = hostFrame.intersection(overlayFrame)
        guard !visible.isNull else { return .zero }
        return visible.offsetBy(dx: -overlayFrame.minX, dy: -overlayFrame.minY)
    }

    static func visibleTarget(_ bounds: CGRect, in viewport: CGRect) -> CGRect? {
        // Do not clamp an offscreen/oversized control into an apparently usable
        // target. Both its visible hole and action must refer to the real bounds.
        guard [bounds.minX, bounds.minY, bounds.width, bounds.height].allSatisfy({ $0.isFinite }),
              bounds.width > 0, bounds.height > 0,
              viewport.width > 0, viewport.height > 0,
              viewport.contains(bounds) else { return nil }
        return bounds
    }

    static func coachRegion(in viewport: CGRect, avoiding target: CGRect?) -> CGRect? {
        guard viewport.width > coachMargin * 2, viewport.height > coachMargin * 2 else { return nil }
        let safe = viewport.insetBy(dx: coachMargin, dy: coachMargin)
        guard let target else { return safe }
        let exclusion = target.insetBy(dx: -(haloPadding + coachGap), dy: -(haloPadding + coachGap))
        let regions = [
            CGRect(x: safe.minX, y: safe.minY, width: safe.width,
                   height: max(0, min(safe.maxY, exclusion.minY) - safe.minY)),
            CGRect(x: safe.minX, y: max(safe.minY, exclusion.maxY), width: safe.width,
                   height: max(0, safe.maxY - max(safe.minY, exclusion.maxY))),
            CGRect(x: safe.minX, y: safe.minY,
                   width: max(0, min(safe.maxX, exclusion.minX) - safe.minX), height: safe.height),
            CGRect(x: max(safe.minX, exclusion.maxX), y: safe.minY,
                   width: max(0, safe.maxX - max(safe.minX, exclusion.maxX)), height: safe.height)
        ].filter { $0.width > 0 && $0.height > 0 }
        // Prefer readable columns over a tall, very narrow sliver. The panel can
        // scroll vertically when large text or landscape leaves little height.
        let readable = regions.filter { $0.width >= min(220, safe.width) }
        return (readable.isEmpty ? regions : readable).max {
            min($0.width, coachMaximumWidth) * $0.height <
                min($1.width, coachMaximumWidth) * $1.height
        }
    }

    static func coachFrame(in region: CGRect, contentHeight: CGFloat, target: CGRect?) -> CGRect {
        let width = min(region.width, coachMaximumWidth)
        let height = min(region.height, contentHeight > 0 ? contentHeight : region.height)
        let x = min(max((target?.midX ?? region.midX) - width / 2, region.minX), region.maxX - width)
        let y: CGFloat
        if let target, region.maxY <= target.minY {
            y = region.maxY - height
        } else if let target, region.minY >= target.maxY {
            y = region.minY
        } else {
            y = min(max((target?.midY ?? region.midY) - height / 2, region.minY), region.maxY - height)
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

private struct TutorialSpotlightOverlay: View {
    let prompt: TutorialPrompt
    let scope: UUID
    let targets: [TutorialTargetAnchor]
    @AccessibilityFocusState private var focusedTarget: String?
    // The host keys this overlay by target ID, resetting the latch on each step.
    @State private var hasActivatedTarget = false

    private struct ResolvedTarget {
        let bounds: CGRect
        let action: () -> Void
    }

    private struct FocusRequest: Equatable {
        let id: String
        let isVisible: Bool
    }

    var body: some View {
        GeometryReader { host in
            // The unexpanded host already receives the safe-area layout
            // proposal. Subtracting its reported insets again excludes visible
            // bottom controls. Only the inner scrim expands into the safe area.
            GeometryReader { geometry in
                spotlight(
                    in: geometry,
                    viewport: TutorialSpotlightLayout.overlayViewport(
                        hostFrame: host.frame(in: .global),
                        overlayFrame: geometry.frame(in: .global)
                    )
                )
            }
            .ignoresSafeArea()
        }
        // A static halo also respects Reduce Motion. Inherited step animations
        // must not move the hit area independently of the resolved anchor.
        .transaction { $0.animation = nil }
    }

    private func spotlight(in geometry: GeometryProxy, viewport: CGRect) -> some View {
        let target = resolve(in: geometry, viewport: viewport)
        return ZStack(alignment: .topLeading) {
            TutorialScrim(hole: target?.bounds)
                .fill(.black.opacity(0.72), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            // The hole is visual only. No event passes through to an underlying
            // control; the overlay Button below invokes its recorded action.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {}
                .accessibilityHidden(true)

            if let target {
                RoundedRectangle(cornerRadius: TutorialSpotlightLayout.cornerRadius)
                    .strokeBorder(Palette.tapCue, lineWidth: 2)
                    .shadow(color: Palette.tapCue.opacity(0.9), radius: 8)
                    .frame(
                        width: target.bounds.width + TutorialSpotlightLayout.haloPadding * 2,
                        height: target.bounds.height + TutorialSpotlightLayout.haloPadding * 2
                    )
                    .position(x: target.bounds.midX, y: target.bounds.midY)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            if let region = TutorialSpotlightLayout.coachRegion(in: viewport, avoiding: target?.bounds) {
                TutorialCoachPanel(prompt: prompt, region: region, target: target?.bounds)
                    .accessibilityHidden(target != nil)
            }

            if let target {
                Button {
                    // Set synchronously before invoking an action that can
                    // charge currency or trigger an asynchronous transition.
                    guard !hasActivatedTarget else { return }
                    hasActivatedTarget = true
                    target.action()
                } label: {
                    Color.clear
                        .frame(width: target.bounds.width, height: target.bounds.height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(hasActivatedTarget)
                .frame(width: target.bounds.width, height: target.bounds.height)
                .contentShape(Rectangle())
                .accessibilityLabel(Text("\(prompt.title). \(prompt.message)"))
                .accessibilityIdentifier("tutorialTarget-\(prompt.target)")
                .accessibilityFocused($focusedTarget, equals: prompt.target)
                .id(prompt.target)
                .position(x: target.bounds.midX, y: target.bounds.midY)
            }
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .task(id: FocusRequest(id: prompt.target, isVisible: target != nil)) {
            focusedTarget = nil
            await Task.yield()
            guard !Task.isCancelled, target != nil else { return }
            focusedTarget = prompt.target
        }
    }

    private func resolve(in geometry: GeometryProxy, viewport: CGRect) -> ResolvedTarget? {
        for target in targets.reversed() where target.scope == scope && target.id == prompt.target {
            if let bounds = TutorialSpotlightLayout.visibleTarget(geometry[target.bounds], in: viewport) {
                return ResolvedTarget(bounds: bounds, action: target.action)
            }
        }
        // Keep listening to anchors while the parent scrolls/mounts the target.
        // A missing or offscreen target never exposes underlying interactions.
        return nil
    }
}

private struct TutorialScrim: Shape {
    let hole: CGRect?

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        if let hole {
            path.addRoundedRect(
                in: hole.insetBy(dx: -TutorialSpotlightLayout.haloPadding, dy: -TutorialSpotlightLayout.haloPadding),
                cornerSize: CGSize(
                    width: TutorialSpotlightLayout.cornerRadius,
                    height: TutorialSpotlightLayout.cornerRadius
                )
            )
        }
        return path
    }
}

private struct TutorialCoachHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct TutorialCoachPanel: View {
    let prompt: TutorialPrompt
    let region: CGRect
    let target: CGRect?
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        let frame = TutorialSpotlightLayout.coachFrame(in: region, contentHeight: contentHeight, target: target)
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 8) {
                Text(prompt.title)
                    .font(.headline)
                    .foregroundStyle(Palette.text)
                Text(prompt.message)
                    .font(.subheadline)
                    .foregroundStyle(Palette.text.opacity(0.9))
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(key: TutorialCoachHeightKey.self, value: geometry.size.height)
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: frame.width, height: frame.height)
        .background(RoundedRectangle(cornerRadius: 16).fill(Palette.panel))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Palette.stroke, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .position(x: frame.midX, y: frame.midY)
        .onPreferenceChange(TutorialCoachHeightKey.self) { contentHeight = $0 }
    }
}
