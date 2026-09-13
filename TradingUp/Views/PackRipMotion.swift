import Foundation

/// Presentation-only gesture math shared by the sealed packs in both modes.
struct PackRipMotion {
    static let completionFraction = 0.55

    let translation: CGSize
    let packWidth: CGFloat
    /// Gesture origin relative to the wrapper, excluding its padded hit target.
    var startX: CGFloat = 0

    var progress: Double {
        let horizontal = abs(translation.width)
        guard packWidth > 0, horizontal > abs(translation.height) else { return 0 }
        return min(1, Double(horizontal / packWidth) / Self.completionFraction)
    }

    var isComplete: Bool { progress >= 1 }
    var fromRight: Bool { translation.width < 0 }

    var fingerX: CGFloat { clamped(startX + translation.width) }
    var trailStart: CGFloat { min(clamped(startX), fingerX) }
    var trailWidth: CGFloat {
        progress > 0 ? abs(fingerX - clamped(startX)) : 0
    }

    private func clamped(_ x: CGFloat) -> CGFloat {
        min(max(0, x), max(0, packWidth))
    }
}
