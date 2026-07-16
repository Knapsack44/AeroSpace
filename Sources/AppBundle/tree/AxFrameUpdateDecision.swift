import AppKit

package struct AxFrameUpdateDecision {
    package let shouldUpdateTopLeft: Bool
    package let shouldUpdateSize: Bool

    package var hasUpdates: Bool {
        shouldUpdateTopLeft || shouldUpdateSize
    }

    package init(
        currentTopLeft: CGPoint?,
        targetTopLeft: CGPoint?,
        currentSize: CGSize?,
        targetSize: CGSize?,
        tolerance: CGFloat = 0.5,
    ) {
        shouldUpdateTopLeft = Self.needsUpdate(current: currentTopLeft, target: targetTopLeft, tolerance: tolerance)
        shouldUpdateSize = Self.needsUpdate(current: currentSize, target: targetSize, tolerance: tolerance)
    }

    private static func needsUpdate(current: CGPoint?, target: CGPoint?, tolerance: CGFloat) -> Bool {
        guard let target else { return false }
        guard let current else { return true }
        return abs(current.x - target.x) > tolerance || abs(current.y - target.y) > tolerance
    }

    private static func needsUpdate(current: CGSize?, target: CGSize?, tolerance: CGFloat) -> Bool {
        guard let target else { return false }
        guard let current else { return true }
        return abs(current.width - target.width) > tolerance || abs(current.height - target.height) > tolerance
    }
}
