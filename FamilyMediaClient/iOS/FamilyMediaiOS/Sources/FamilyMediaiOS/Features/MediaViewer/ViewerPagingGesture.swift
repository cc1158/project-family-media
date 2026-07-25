import SwiftUI

enum ViewerPagingDirection: Equatable {
    case previous
    case next

    var exitSign: CGFloat {
        switch self {
        case .previous: 1
        case .next: -1
        }
    }
}

enum ViewerPagingGesturePolicy {
    static let horizontalIntentRatio: CGFloat = 1.25
    static let distanceRatio: CGFloat = 0.22
    static let projectedDistanceRatio: CGFloat = 0.35
    static let minimumCommitDistance: CGFloat = 72
    static let boundaryResistance: CGFloat = 0.18

    static func offset(
        for translation: CGSize,
        canGoPrevious: Bool,
        canGoNext: Bool
    ) -> CGFloat {
        guard hasHorizontalIntent(translation) else { return 0 }
        if translation.width > 0, !canGoPrevious {
            return translation.width * boundaryResistance
        }
        if translation.width < 0, !canGoNext {
            return translation.width * boundaryResistance
        }
        return translation.width
    }

    static func decision(
        translation: CGSize,
        projectedTranslation: CGSize,
        viewportWidth: CGFloat,
        canGoPrevious: Bool,
        canGoNext: Bool
    ) -> ViewerPagingDirection? {
        guard viewportWidth > 0, hasHorizontalIntent(translation) else { return nil }
        let directThreshold = max(minimumCommitDistance, viewportWidth * distanceRatio)
        let projectedThreshold = viewportWidth * projectedDistanceRatio
        let commits = abs(translation.width) >= directThreshold
            || abs(projectedTranslation.width) >= projectedThreshold
        guard commits else { return nil }

        // Prediction may cross zero when a user reverses direction near the end
        // of a drag. The visible drag always owns direction; prediction only
        // helps decide whether its velocity is strong enough to commit.
        if translation.width > 0, canGoPrevious {
            return .previous
        }
        if translation.width < 0, canGoNext {
            return .next
        }
        return nil
    }

    static func canBeginPhotoPaging(
        isEnabled: Bool,
        zoomScale: CGFloat,
        minimumZoomScale: CGFloat,
        velocity: CGPoint
    ) -> Bool {
        guard isEnabled,
              zoomScale <= minimumZoomScale + 0.01,
              abs(velocity.x) > .ulpOfOne
        else { return false }
        return abs(velocity.x) >= abs(velocity.y) * horizontalIntentRatio
    }

    private static func hasHorizontalIntent(_ translation: CGSize) -> Bool {
        abs(translation.width) >= ViewerNavigationGestureMetrics.minimumRecognitionDistance
            && abs(translation.width) >= abs(translation.height) * horizontalIntentRatio
    }
}

struct ViewerPagingPresentationState: Equatable {
    private(set) var offset: CGFloat = 0
    private(set) var previewDirection: ViewerPagingDirection?
    private(set) var contentOpacity: Double = 1
    private(set) var isTransitioning = false
    private var shouldPreserveChromeOnItemChange = false

    mutating func update(
        translation: CGSize,
        canGoPrevious: Bool,
        canGoNext: Bool
    ) {
        guard !isTransitioning else { return }
        offset = ViewerPagingGesturePolicy.offset(
            for: translation,
            canGoPrevious: canGoPrevious,
            canGoNext: canGoNext
        )
        if offset > 0, canGoPrevious {
            previewDirection = .previous
        } else if offset < 0, canGoNext {
            previewDirection = .next
        } else {
            previewDirection = nil
        }
    }

    mutating func beginTransition(
        direction: ViewerPagingDirection,
        width: CGFloat,
        movesContent: Bool = true
    ) {
        isTransitioning = true
        previewDirection = direction
        offset = movesContent ? direction.exitSign * width : 0
    }

    mutating func setContentVisible(_ isVisible: Bool) {
        contentOpacity = isVisible ? 1 : 0
    }

    mutating func prepareForItemChange() {
        shouldPreserveChromeOnItemChange = true
    }

    mutating func cancelPreparedItemChange() {
        shouldPreserveChromeOnItemChange = false
    }

    mutating func resetForItemChange() -> Bool {
        let shouldPreserveChrome = shouldPreserveChromeOnItemChange
        shouldPreserveChromeOnItemChange = false
        resetVisualState()
        return shouldPreserveChrome
    }

    mutating func resetVisualState() {
        offset = 0
        previewDirection = nil
        contentOpacity = 1
        isTransitioning = false
    }
}
