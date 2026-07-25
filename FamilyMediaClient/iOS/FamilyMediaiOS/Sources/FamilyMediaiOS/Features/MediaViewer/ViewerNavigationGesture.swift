import SwiftUI

enum ViewerNavigationGestureMetrics {
    static let minimumRecognitionDistance: CGFloat = 12
}

enum ViewerNavigationGesturePolicy {
    static func isEnabled(
        isVoiceOverEnabled: Bool,
        isPhotoInspectionActive: Bool,
        isScrubbing: Bool,
        isOverlayPresented: Bool,
        isTransitioning: Bool
    ) -> Bool {
        !isVoiceOverEnabled
            && !isPhotoInspectionActive
            && !isScrubbing
            && !isOverlayPresented
            && !isTransitioning
    }

    static func canBeginPhotoNavigation(
        isEnabled: Bool,
        zoomScale: CGFloat,
        minimumZoomScale: CGFloat,
        velocity: CGPoint
    ) -> Bool {
        ViewerPagingGesturePolicy.canBeginPhotoPaging(
            isEnabled: isEnabled,
            zoomScale: zoomScale,
            minimumZoomScale: minimumZoomScale,
            velocity: velocity
        ) || ViewerDismissGesturePolicy.canBeginPhotoDismiss(
            isEnabled: isEnabled,
            zoomScale: zoomScale,
            minimumZoomScale: minimumZoomScale,
            velocity: velocity
        )
    }
}

extension View {
    func viewerNavigationGesture(
        isEnabled: Bool,
        onChanged: @escaping (CGSize) -> Void,
        onEnded: @escaping (CGSize, CGSize) -> Void
    ) -> some View {
        simultaneousGesture(
            DragGesture(
                minimumDistance: ViewerNavigationGestureMetrics.minimumRecognitionDistance,
                coordinateSpace: .global
            )
                .onChanged { value in
                    guard isEnabled else { return }
                    onChanged(value.translation)
                }
                .onEnded { value in
                    if isEnabled {
                        onEnded(value.translation, value.predictedEndTranslation)
                    } else {
                        // The scene or another interaction can disable navigation
                        // mid-drag. Sending zero lets the owner clear transforms.
                        onEnded(.zero, .zero)
                    }
                }
        )
    }
}
