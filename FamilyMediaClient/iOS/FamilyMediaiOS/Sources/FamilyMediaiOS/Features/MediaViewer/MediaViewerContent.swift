import AVFoundation
import FamilyMediaCore
import SwiftUI

struct MediaViewerContent: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let item: MediaItem
    let player: AVPlayer?
    let resourceRequestAuthorizer: (any MediaResourceRequestAuthorizing)?
    let onPhotoInspectionChanged: (String, Bool) -> Void
    let onPhotoLoadStateChanged: (String, MediaPhotoLoadState) -> Void
    let onToggleChrome: () -> Void
    let isNavigationGestureEnabled: Bool
    let onNavigationDragChanged: (CGSize) -> Void
    let onNavigationDragEnded: (CGSize, CGSize) -> Void
    @State private var photoReloadID = 0

    var body: some View {
        switch item.kind {
        case .video:
            PlayerSurfaceView(player: player)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onToggleChrome)
                .viewerNavigationGesture(
                    isEnabled: isNavigationGestureEnabled,
                    onChanged: onNavigationDragChanged,
                    onEnded: onNavigationDragEnded
                )
                .accessibilityIdentifier("viewer.surface")
                .accessibilityValue(item.displayTitle)
        case .photo:
            if item.thumbnailURL?.scheme == "demo-art" {
                DemoArtworkView(item: item)
                    .aspectRatio(0.75, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(24)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onToggleChrome)
                    .viewerNavigationGesture(
                        isEnabled: isNavigationGestureEnabled,
                        onChanged: onNavigationDragChanged,
                        onEnded: onNavigationDragEnded
                    )
                    .accessibilityIdentifier("viewer.surface")
                    .accessibilityValue(item.displayTitle)
            } else {
                StagedRemoteImage(
                    previewURL: item.readyThumbnailURL,
                    originalURL: item.url,
                    originalReloadID: photoReloadID,
                    requestAuthorizer: resourceRequestAuthorizer
                ) { phase in
                    Group {
                        if let image = phase.displayedImage {
                            ZStack {
                                ZoomablePhotoView(
                                    image: image,
                                    mediaID: item.id,
                                    imageTransitionDuration: reduceMotion ? 0 : 0.18,
                                    onInspectionChanged: { onPhotoInspectionChanged(item.id, $0) },
                                    onSingleTap: onToggleChrome,
                                    isNavigationGestureEnabled: isNavigationGestureEnabled,
                                    onNavigationDragChanged: onNavigationDragChanged,
                                    onNavigationDragEnded: onNavigationDragEnded
                                )
                                .blur(radius: phase.displaysPreviewQuality ? 0.45 : 0)
                                .animation(
                                    reduceMotion ? nil : .easeOut(duration: 0.18),
                                    value: phase.displaysPreviewQuality
                                )
                                .accessibilityIdentifier("viewer.surface")
                                .accessibilityValue(item.displayTitle)

                                if phase.isLoadingFullImage {
                                    MediaImageLoadingIndicator(progress: phase.progress)
                                        .frame(
                                            maxWidth: .infinity,
                                            maxHeight: .infinity,
                                            alignment: .center
                                        )
                                }

                                if phase.didFailFullImage {
                                    Button("重新加载高清图片") {
                                        photoReloadID += 1
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .frame(
                                        maxWidth: .infinity,
                                        maxHeight: .infinity,
                                        alignment: .bottom
                                    )
                                    .padding(.bottom, 104)
                                    .accessibilityIdentifier("viewer.photo.retryFull")
                                }
                            }
                        } else if phase.didFailCompletely {
                            VStack(spacing: 14) {
                                Image(systemName: "photo.badge.exclamationmark")
                                    .font(.system(size: 46, weight: .semibold))
                                Text("照片加载失败")
                                    .font(.headline)
                                Button("重新加载") {
                                    photoReloadID += 1
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .foregroundStyle(.secondary)
                        } else {
                            ProgressView()
                                .tint(.white)
                        }
                    }
                    .reportPhotoLoadState(
                        phase.photoLoadState,
                        itemID: item.id,
                        to: onPhotoLoadStateChanged
                    )
                }
                .ignoresSafeArea()
            }
        }
    }
}
