import AVFoundation
import FamilyMediaCore
import SwiftUI

/// Composes the full-screen media content and applies navigation transforms,
/// while `MediaViewerScreen` remains responsible for session lifecycle.
struct MediaViewerInteractionSurface: View {
    let item: MediaItem
    let previewItem: MediaItem?
    let pagingState: ViewerPagingPresentationState
    let dismissState: ViewerDismissPresentationState
    let player: AVPlayer?
    let resourceRequestAuthorizer: (any MediaResourceRequestAuthorizing)?
    let reduceMotion: Bool
    let isNavigationGestureEnabled: Bool
    let onPhotoInspectionChanged: (String, Bool) -> Void
    let onPhotoLoadStateChanged: (String, MediaPhotoLoadState) -> Void
    let onToggleChrome: () -> Void
    let onNavigationDragChanged: (CGSize, CGSize) -> Void
    let onNavigationDragEnded: (CGSize, CGSize, CGSize) -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let previewItem, let direction = pagingState.previewDirection {
                    ViewerAdjacentPreview(
                        item: previewItem,
                        resourceRequestAuthorizer: resourceRequestAuthorizer
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .offset(
                        x: previewOffset(
                            direction: direction,
                            viewportWidth: proxy.size.width
                        )
                    )
                }

                MediaViewerContent(
                    item: item,
                    player: player,
                    resourceRequestAuthorizer: resourceRequestAuthorizer,
                    onPhotoInspectionChanged: onPhotoInspectionChanged,
                    onPhotoLoadStateChanged: onPhotoLoadStateChanged,
                    onToggleChrome: onToggleChrome,
                    isNavigationGestureEnabled: isNavigationGestureEnabled,
                    onNavigationDragChanged: { translation in
                        onNavigationDragChanged(translation, proxy.size)
                    },
                    onNavigationDragEnded: { translation, projectedTranslation in
                        onNavigationDragEnded(
                            translation,
                            projectedTranslation,
                            proxy.size
                        )
                    }
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
                .offset(
                    x: reduceMotion ? 0 : pagingState.offset,
                    y: reduceMotion ? 0 : dismissState.offset
                )
                .scaleEffect(reduceMotion ? 1 : dismissState.scale)
                .opacity(pagingState.contentOpacity * dismissState.contentOpacity)
            }
            .clipped()
        }
        .ignoresSafeArea()
    }

    private func previewOffset(
        direction: ViewerPagingDirection,
        viewportWidth: CGFloat
    ) -> CGFloat {
        switch direction {
        case .previous:
            -viewportWidth + pagingState.offset
        case .next:
            viewportWidth + pagingState.offset
        }
    }
}
