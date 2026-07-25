import FamilyMediaCore
import SwiftUI

struct MediaCardView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: MediaItem
    let isFocused: Bool
    let resourceRequestAuthorizer: (any MediaResourceRequestAuthorizing)?
    var containerLabel = "媒体库"
    var thumbnailReloadID = 0

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            MediaThumbnailView(
                item: item,
                reloadID: thumbnailReloadID,
                requestAuthorizer: resourceRequestAuthorizer
            )

            LinearGradient(
                colors: [
                    .clear,
                    .black.opacity(isFocused ? 0.28 : 0.18),
                    .black.opacity(isFocused ? 0.9 : 0.74)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 8) {
                if item.isContainer {
                    Label(containerLabel, systemImage: "folder.fill")
                        .font(.caption.weight(.bold))
                } else if item.kind == .video {
                    videoBadge
                } else {
                    photoBadge
                }

                Text(item.displayTitle)
                    .font(.system(size: isFocused ? 24 : 22, weight: .semibold))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .shadow(color: .black.opacity(0.75), radius: 4, y: 2)
            }
            .foregroundStyle(.white)
            .padding(14)
        }
        .frame(width: MediaArtworkMetrics.width, height: MediaArtworkMetrics.height)
        .clipShape(RoundedRectangle(cornerRadius: MediaArtworkMetrics.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: MediaArtworkMetrics.cornerRadius)
                .stroke(isFocused ? Color.white : Color.white.opacity(0.12), lineWidth: isFocused ? 5 : 1)
        }
        .overlay {
            if isFocused {
                RoundedRectangle(cornerRadius: MediaArtworkMetrics.cornerRadius)
                    .stroke(Color.cyan.opacity(0.55), lineWidth: 2)
                    .padding(7)
            }
        }
        .scaleEffect(isFocused ? MediaArtworkMetrics.focusedScale : 1)
        .shadow(color: .black.opacity(isFocused ? 0.72 : 0.28), radius: isFocused ? 24 : 8, y: isFocused ? 16 : 4)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isFocused)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(item.isContainer ? "按下打开" : "按下查看")
    }

    private var videoBadge: some View {
        Label("视频", systemImage: "play.fill")
            .font(.caption.weight(.bold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.black.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var photoBadge: some View {
        Label("照片", systemImage: "photo.fill")
            .font(.caption.weight(.bold))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.black.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var accessibilityLabel: String {
        let type = item.isContainer ? containerLabel : (item.kind == .video ? "视频" : "照片")
        return "\(type)，\(item.displayTitle)"
    }
}
