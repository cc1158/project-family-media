import SwiftUI

enum ViewerDismissGesturePolicy {
    static let verticalIntentRatio: CGFloat = 1.25
    static let distanceRatio: CGFloat = 0.20
    static let projectedDistanceRatio: CGFloat = 0.32
    static let minimumCommitDistance: CGFloat = 110
    static let minimumScale: CGFloat = 0.86
    static let minimumBackgroundOpacity: Double = 0.22

    static func hasDownwardIntent(_ translation: CGSize) -> Bool {
        translation.height >= ViewerNavigationGestureMetrics.minimumRecognitionDistance
            && translation.height >= abs(translation.width) * verticalIntentRatio
    }

    static func shouldDismiss(
        translation: CGSize,
        projectedTranslation: CGSize,
        viewportHeight: CGFloat
    ) -> Bool {
        guard viewportHeight > 0, hasDownwardIntent(translation) else { return false }
        let directThreshold = max(minimumCommitDistance, viewportHeight * distanceRatio)
        let projectedThreshold = viewportHeight * projectedDistanceRatio
        return translation.height >= directThreshold
            || projectedTranslation.height >= projectedThreshold
    }

    static func canBeginPhotoDismiss(
        isEnabled: Bool,
        zoomScale: CGFloat,
        minimumZoomScale: CGFloat,
        velocity: CGPoint
    ) -> Bool {
        guard isEnabled,
              zoomScale <= minimumZoomScale + 0.01,
              velocity.y > .ulpOfOne
        else { return false }
        return velocity.y >= abs(velocity.x) * verticalIntentRatio
    }
}

struct ViewerDismissPresentationState: Equatable {
    private(set) var offset: CGFloat = 0
    private(set) var scale: CGFloat = 1
    private(set) var backgroundOpacity: Double = 1
    private(set) var contentOpacity: Double = 1
    private(set) var isInteracting = false
    private(set) var isTransitioning = false

    mutating func update(translation: CGSize, viewportHeight: CGFloat) {
        guard !isTransitioning,
              viewportHeight > 0,
              ViewerDismissGesturePolicy.hasDownwardIntent(translation)
        else { return }

        isInteracting = true
        offset = translation.height
        let progress = min(1, translation.height / viewportHeight)
        scale = max(
            ViewerDismissGesturePolicy.minimumScale,
            1 - progress * 0.25
        )
        backgroundOpacity = max(
            ViewerDismissGesturePolicy.minimumBackgroundOpacity,
            1 - Double(progress) * 1.25
        )
    }

    mutating func beginDismiss(viewportHeight: CGFloat, reduceMotion: Bool) {
        isInteracting = false
        isTransitioning = true
        backgroundOpacity = 0
        if reduceMotion {
            offset = 0
            scale = 1
            contentOpacity = 0
        } else {
            offset = viewportHeight
            scale = ViewerDismissGesturePolicy.minimumScale
        }
    }

    mutating func reset() {
        self = ViewerDismissPresentationState()
    }
}
