import Foundation
import Testing
@testable import FamilyMediaCore

struct MediaInformationPresentationTests {
    private let shanghai = TimeZone(identifier: "Asia/Shanghai")!
    private let locale = Locale(identifier: "zh_CN")

    @Test func familyMediaUsesCapturedTimeAndDirectory() {
        let capturedAt = Date(timeIntervalSince1970: 1_687_075_920)
        let item = mediaItem(
            capturedAt: capturedAt,
            mediaPath: "成长/幼儿园/照片.jpg",
            size: 1_572_864
        )

        let presentation = MediaInformationPresentation(
            item: item,
            timeZone: shanghai,
            locale: locale
        )

        #expect(presentation.compactDateText == "2023年6月18日 16:12")
        #expect(presentation.value(for: .date) == "2023年6月18日 16:12")
        #expect(presentation.title(for: .date) == "拍摄时间")
        #expect(presentation.value(for: .fileSize) == "1.5 MB")
        #expect(presentation.value(for: .directory) == "成长/幼儿园")
        #expect(presentation.value(for: .source) == "家庭媒体")
    }

    @Test func familyMediaLabelsModifiedTimeAndRootAsUnclassified() {
        let item = mediaItem(capturedAt: nil, mediaPath: "照片.jpg")
        let presentation = MediaInformationPresentation(
            item: item,
            timeZone: shanghai,
            locale: locale
        )

        #expect(presentation.compactDateText.hasPrefix("文件日期 · "))
        #expect(presentation.title(for: .date) == "文件日期")
        #expect(presentation.value(for: .directory) == "未分类")
    }

    @Test func jellyfinUsesJoinedTimeAndHidesSyntheticDirectory() {
        let item = mediaItem(
            capturedAt: nil,
            mediaPath: "jellyfin-item-id",
            sourceID: .jellyfin
        )
        let presentation = MediaInformationPresentation(
            item: item,
            timeZone: shanghai,
            locale: locale
        )

        #expect(presentation.compactDateText.hasPrefix("加入时间 · "))
        #expect(presentation.title(for: .date) == "加入时间")
        #expect(presentation.value(for: .directory) == nil)
        #expect(presentation.value(for: .source) == "Jellyfin")
    }

    @Test func invalidDateAndEmptySizeAreShownAsUnknown() {
        let item = mediaItem(
            capturedAt: nil,
            mediaPath: "jellyfin-item-id",
            size: 0,
            modified: .distantPast,
            sourceID: .jellyfin
        )
        let presentation = MediaInformationPresentation(item: item)

        #expect(presentation.compactDateText == "时间未知")
        #expect(presentation.value(for: .date) == "未知")
        #expect(presentation.value(for: .fileSize) == "未知")
    }

    private func mediaItem(
        capturedAt: Date?,
        mediaPath: String,
        size: Int64 = 1_024,
        modified: Date = Date(timeIntervalSince1970: 1_687_075_920),
        sourceID: MediaSourceID = .familyMedia
    ) -> MediaItem {
        MediaItem(
            id: "item",
            name: "照片.jpg",
            kind: .photo,
            size: size,
            modified: modified,
            capturedAt: capturedAt,
            url: URL(string: "http://localhost/item")!,
            mediaPath: mediaPath,
            thumbnailStatus: .ready,
            sourceID: sourceID
        )
    }
}

private extension MediaInformationPresentation {
    func title(for field: MediaInformationField) -> String? {
        rows.first(where: { $0.id == field })?.title
    }

    func value(for field: MediaInformationField) -> String? {
        rows.first(where: { $0.id == field })?.value
    }
}
