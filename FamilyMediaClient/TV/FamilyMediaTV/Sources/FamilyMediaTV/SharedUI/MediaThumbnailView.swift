import FamilyMediaCore
import SwiftUI
import UIKit

struct MediaThumbnailView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: MediaItem
    var reloadID = 0
    var requestAuthorizer: (any MediaResourceRequestAuthorizing)?

    private var presentation: MediaThumbnailPresentation {
        MediaThumbnailPresentation(item: item)
    }

    var body: some View {
        ZStack {
            placeholderBackground

            if presentation.imageURL?.scheme == "demo-art" {
                DemoArtworkView(item: item)
            } else if let imageURL = presentation.imageURL {
                CachedRemoteImage(
                    url: imageURL,
                    purpose: .thumbnail,
                    reloadID: reloadID,
                    requestAuthorizer: requestAuthorizer
                ) { phase in
                    switch phase {
                    case .success(let image):
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .transition(.opacity)
                    case .failure:
                        VStack(spacing: 10) {
                            Image(systemName: "photo.badge.exclamationmark")
                                .font(.system(size: 42, weight: .semibold))
                            Text("封面不可用")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(.white.opacity(0.52))
                    case .empty:
                        ProgressView()
                    }
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: imageURL)
            } else {
                placeholderContent
            }
        }
        .frame(width: MediaArtworkMetrics.width, height: MediaArtworkMetrics.height)
        .clipped()
    }

    private var placeholderBackground: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.12), Color.white.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private var placeholderContent: some View {
        VStack(spacing: 12) {
            Image(systemName: presentation.placeholderSystemImage)
                .font(.system(size: 46, weight: .semibold))
            Text(presentation.placeholderTitle)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.white.opacity(0.48))
    }
}
