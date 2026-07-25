import FamilyMediaCore
import SwiftUI

struct ViewerAdjacentPreview: View {
    let item: MediaItem
    let resourceRequestAuthorizer: (any MediaResourceRequestAuthorizing)?

    var body: some View {
        ZStack {
            Color.black

            if item.thumbnailURL?.scheme == "demo-art" {
                DemoArtworkView(item: item)
            } else if let thumbnailURL = item.thumbnailURL {
                CachedRemoteImage(
                    url: thumbnailURL,
                    purpose: .thumbnail,
                    requestAuthorizer: resourceRequestAuthorizer
                ) { phase in
                    switch phase {
                    case .success(let image):
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                    case .empty:
                        ProgressView().tint(.white)
                    case .failure:
                        placeholder
                    }
                }
            } else {
                placeholder
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.72)],
                startPoint: .center,
                endPoint: .bottom
            )

            Text(item.displayTitle)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(2)
                .padding(.horizontal, 28)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .clipped()
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        Image(systemName: item.kind == .video ? "film.fill" : "photo.fill")
            .font(.system(size: 48, weight: .semibold))
            .foregroundStyle(.white.opacity(0.58))
    }
}
