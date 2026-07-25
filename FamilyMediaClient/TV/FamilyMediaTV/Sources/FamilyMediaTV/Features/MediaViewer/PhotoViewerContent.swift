import FamilyMediaCore
import SwiftUI
import UIKit

struct PhotoViewerContent: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let item: MediaItem
    let resourceRequestAuthorizer: (any MediaResourceRequestAuthorizing)?
    let onLoadStateChanged: (String, MediaPhotoLoadState) -> Void
    @State private var reloadID = 0

    var body: some View {
        if item.thumbnailURL?.scheme == "demo-art" {
            DemoArtworkView(item: item)
                .aspectRatio(1.5, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(80)
                .reportPhotoLoadState(
                    .ready,
                    itemID: item.id,
                    to: onLoadStateChanged
                )
        } else {
            StagedRemoteImage(
                previewURL: item.readyThumbnailURL,
                originalURL: item.url,
                originalReloadID: reloadID,
                requestAuthorizer: resourceRequestAuthorizer
            ) { phase in
                Group {
                    if let image = phase.displayedImage {
                        ZStack {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .blur(radius: phase.displaysPreviewQuality ? 0.6 : 0)
                                .contentTransition(.opacity)
                                .animation(
                                    reduceMotion ? nil : .easeInOut(duration: 0.18),
                                    value: ObjectIdentifier(image)
                                )
                                .animation(
                                    reduceMotion ? nil : .easeOut(duration: 0.18),
                                    value: phase.displaysPreviewQuality
                                )

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
                                    reloadID += 1
                                }
                                .buttonStyle(.borderedProminent)
                                .frame(
                                    maxWidth: .infinity,
                                    maxHeight: .infinity,
                                    alignment: .bottom
                                )
                                .padding(.bottom, 72)
                                .accessibilityIdentifier("viewer.photo.retryFull")
                            }
                        }
                    } else if phase.didFailCompletely {
                        VStack(spacing: 18) {
                            Image(systemName: "photo.badge.exclamationmark")
                                .font(.system(size: 64, weight: .semibold))
                            Text("照片加载失败")
                                .font(.title3.weight(.semibold))
                            Button("重新加载") {
                                reloadID += 1
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                    }
                }
                .reportPhotoLoadState(
                    phase.photoLoadState,
                    itemID: item.id,
                    to: onLoadStateChanged
                )
            }
            .ignoresSafeArea()
        }
    }
}
