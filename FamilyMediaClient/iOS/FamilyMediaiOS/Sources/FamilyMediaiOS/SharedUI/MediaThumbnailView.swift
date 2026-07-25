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
        GeometryReader { proxy in
            thumbnailContent
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
        }
        .aspectRatio(1.42, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var thumbnailContent: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.white.opacity(0.06)

            if presentation.imageURL?.scheme == "demo-art" {
                DemoArtworkView(item: item)
            } else if presentation.imageURL == nil {
                VStack(spacing: 6) {
                    Image(systemName: presentation.placeholderSystemImage)
                        .font(.system(size: 28))
                    Text(presentation.placeholderTitle)
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            } else {
                CachedRemoteImage(
                    url: presentation.imageURL,
                    purpose: .thumbnail,
                    reloadID: reloadID,
                    requestAuthorizer: requestAuthorizer
                ) { phase in
                    switch phase {
                    case .success(let image):
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                            .transition(.opacity)
                    case .failure:
                        VStack(spacing: 6) {
                            Image(systemName: "photo.badge.exclamationmark")
                                .font(.system(size: 28))
                            Text("封面不可用").font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                    case .empty:
                        ProgressView().controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: presentation.imageURL)
            }

            if presentation.showsPlayBadge {
                Image(systemName: "play.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.black.opacity(0.72))
                    .clipShape(Circle())
                .padding(7)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}
