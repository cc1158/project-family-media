import Foundation

public struct MediaThumbnailPresentation: Equatable, Sendable {
    public let imageURL: URL?
    public let placeholderSystemImage: String
    public let placeholderTitle: String
    public let showsPlayBadge: Bool

    public init(item: MediaItem) {
        imageURL = item.readyThumbnailURL
        if item.isContainer {
            placeholderSystemImage = "folder.fill"
            placeholderTitle = "文件夹"
            showsPlayBadge = false
            return
        }
        switch item.thumbnailStatus {
        case .pending:
            placeholderSystemImage = "clock.fill"
            placeholderTitle = "生成中"
        case .failed:
            placeholderSystemImage = "exclamationmark.triangle.fill"
            placeholderTitle = "缩略图失败"
        case .ready:
            placeholderSystemImage = item.kind == .video ? "film.fill" : "photo.fill"
            placeholderTitle = item.kind == .video ? "视频" : "照片"
        }
        showsPlayBadge = item.kind == .video
    }
}
