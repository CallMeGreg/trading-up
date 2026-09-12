import Foundation

/// Presentation-only gesture math shared by the sealed packs in both modes.
struct PackRipMotion {
    static let completionFraction = 0.55

    let translation: CGSize
    let packWidth: CGFloat

    var progress: Double {
        let horizontal = abs(translation.width)
        guard packWidth > 0, horizontal > abs(translation.height) else { return 0 }
        return min(1, Double(horizontal / packWidth) / Self.completionFraction)
    }

    var isComplete: Bool { progress >= 1 }
    var fromRight: Bool { translation.width < 0 }
}
