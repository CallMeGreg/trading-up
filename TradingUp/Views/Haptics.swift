import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Cross-platform haptic helper. No-ops where UIKit haptics are unavailable.
enum HapticStyle { case light, medium, heavy, soft, rigid, success, warning, error }

enum Haptics {
    /// User preference key, shared with `HapticsManager`. Read straight from
    /// `UserDefaults` here (not via the `@MainActor` manager) so a haptic can fire
    /// from any context without hopping actors.
    static let prefKey = "tradingup_haptics_enabled"

    /// Whether haptics are on. Defaults to on when the player has never toggled it.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: prefKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: prefKey)
    }

    static func play(_ style: HapticStyle) {
        guard isEnabled else { return }
        #if canImport(UIKit)
        switch style {
        case .light:  UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .heavy:  UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .soft:   UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        case .rigid:  UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning: UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .error:   UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        #endif
    }
}

/// Drives the Settings "Haptics" toggle. Mirrors `SoundManager`'s preference
/// pattern: an observable, `UserDefaults`-backed flag so the switch updates live.
/// `Haptics.play(_:)` reads the same key directly, so it's the single source of
/// truth for whether feedback fires.
@Observable
@MainActor
final class HapticsManager {
    static let shared = HapticsManager()

    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Haptics.prefKey) }
    }

    private init() {
        if UserDefaults.standard.object(forKey: Haptics.prefKey) == nil {
            isEnabled = true   // haptics on by default
        } else {
            isEnabled = UserDefaults.standard.bool(forKey: Haptics.prefKey)
        }
    }
}
