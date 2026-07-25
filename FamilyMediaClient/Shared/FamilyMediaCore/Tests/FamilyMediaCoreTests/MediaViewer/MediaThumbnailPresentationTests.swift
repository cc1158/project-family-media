import Foundation
import Testing
@testable import FamilyMediaCore

struct MediaThumbnailPresentationTests {
    @Test func usesReadyThumbnailAndVideoBadgeForVideos() {
        let item = makeMediaItem(id: "video-1", kind: .video)

        let presentation = MediaThumbnailPresentation(item: item)

        #expect(presentation.imageURL == item.thumbnailURL)
        #expect(presentation.placeholderSystemImage == "film.fill")
        #expect(presentation.placeholderTitle == "视频")
        #expect(presentation.showsPlayBadge)
    }

    @Test func showsPendingPlaceholderWhenThumbnailIsNotReady() {
        let item = MediaItem(
            id: "photo-1",
            name: "photo-1.jpg",
            kind: .photo,
            size: 1024,
            modified: Date(timeIntervalSince1970: 1_779_120_000),
            url: URL(string: "http://localhost:8080/media/original/photo-1.jpg")!,
            thumbnailURL: URL(string: "http://localhost:8080/media/thumbnails/photo-1.jpg"),
            mediaPath: "photo-1.jpg",
            thumbnailStatus: .pending
        )

        let presentation = MediaThumbnailPresentation(item: item)

        #expect(presentation.imageURL == nil)
        #expect(presentation.placeholderSystemImage == "clock.fill")
        #expect(presentation.placeholderTitle == "生成中")
        #expect(!presentation.showsPlayBadge)
    }

    @Test func showsFailedPlaceholderWhenThumbnailFailed() {
        let item = MediaItem(
            id: "photo-1",
            name: "photo-1.jpg",
            kind: .photo,
            size: 1024,
            modified: Date(timeIntervalSince1970: 1_779_120_000),
            url: URL(string: "http://localhost:8080/media/original/photo-1.jpg")!,
            thumbnailURL: URL(string: "http://localhost:8080/media/thumbnails/photo-1.jpg"),
            mediaPath: "photo-1.jpg",
            thumbnailStatus: .failed
        )

        let presentation = MediaThumbnailPresentation(item: item)

        #expect(presentation.imageURL == nil)
        #expect(presentation.placeholderSystemImage == "exclamationmark.triangle.fill")
        #expect(presentation.placeholderTitle == "缩略图失败")
        #expect(!presentation.showsPlayBadge)
    }

    @Test func folderWithoutCoverUsesStableFolderPlaceholder() {
        let item = MediaItem(
            id: "family-folder:path:a2lkcw",
            name: "幼儿园",
            kind: .video,
            size: 0,
            modified: Date(timeIntervalSince1970: 1_779_120_000),
            url: URL(string: "http://localhost:8080")!,
            mediaPath: "幼儿园",
            thumbnailStatus: .ready,
            containerID: "family-folder:path:a2lkcw",
            isContainer: true
        )

        let presentation = MediaThumbnailPresentation(item: item)

        #expect(presentation.imageURL == nil)
        #expect(presentation.placeholderSystemImage == "folder.fill")
        #expect(presentation.placeholderTitle == "文件夹")
        #expect(!presentation.showsPlayBadge)
    }
}
