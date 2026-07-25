import FamilyMediaCore
import SwiftUI

struct MediaTileView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let item: MediaItem
    let resourceRequestAuthorizer: (any MediaResourceRequestAuthorizing)?
    var containerLabel = "媒体库"
    var thumbnailReloadID = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MediaThumbnailView(
                item: item,
                reloadID: thumbnailReloadID,
                requestAuthorizer: resourceRequestAuthorizer
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(titleLineCount, reservesSpace: true)
                    .multilineTextAlignment(.leading)

                Label(
                    item.isContainer ? containerLabel : (item.kind == .video ? "视频" : "照片"),
                    systemImage: item.isContainer ? "folder.fill" : (item.kind == .video ? "play.fill" : "photo.fill")
                )
                .font(.caption2.weight(.medium))
                .foregroundStyle(item.isContainer ? FamilyMediaTheme.accent : .secondary)
                .lineLimit(1)
            }
            .padding(.horizontal, 3)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(FamilyMediaTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(FamilyMediaTheme.border, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(item.isContainer ? "双击打开" : "双击查看")
    }

    private var accessibilityLabel: String {
        let type = item.isContainer ? containerLabel : (item.kind == .video ? "视频" : "照片")
        return "\(type)，\(item.displayTitle)"
    }

    private var titleLineCount: Int {
        dynamicTypeSize.isAccessibilitySize ? 3 : 2
    }
}
