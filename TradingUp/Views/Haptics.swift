import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Cross-platform haptic helper. No-ops where UIKit haptics are unavailable.
enum HapticStyle { case light, medium, heavy, soft, rigid, success, warning, error }

enum Haptics {
    static func play(_ style: HapticStyle) {
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
