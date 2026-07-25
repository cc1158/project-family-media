import FamilyMediaCore
import XCTest
@testable import FamilyMediaiOS

@MainActor
final class MediaBrowseSessionControllerTests: XCTestCase {
    func testPrepareLoadsDirectoryAndChangingModeLoadsTimelineIndex() async {
        let catalog = BrowseSessionCatalogStub()
        let timelineService = BrowseSessionTimelineStub()
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defer { defaults.removePersistentDomain(forName: #function) }

        let library = MediaLibraryStore(
            title: "媒体",
            filter: .all,
            mediaService: catalog,
            sourceID: .familyMedia
        )
        let timeline = MediaTimelineStore(
            service: timelineService,
            sourceID: .familyMedia,
            filter: .all,
            containerID: nil,
            defaults: defaults,
            timeZone: { "Asia/Shanghai" }
        )
        let session = MediaBrowseSessionController(
            library: library,
            timeline: timeline,
            sourceID: .familyMedia
        )

        await session.prepare(preservingItemID: nil)

        let directoryRequestCount = await catalog.requestCount
        XCTAssertEqual(directoryRequestCount, 1)
        guard case .loaded(let items) = library.state else {
            return XCTFail("首次准备应加载目录内容")
        }
        XCTAssertEqual(items.map(\.id), ["familyMedia:item"])

        await session.changeMode(to: .month, preservingItemID: nil)

        XCTAssertEqual(timeline.mode, .month)
        let indexRequestCount = await timelineService.indexRequestCount
        XCTAssertEqual(indexRequestCount, 1)
        XCTAssertEqual(timeline.years.map(\.key), ["2026"])
    }

    func testSourcePresentationUsesCatalogStructureOnlyAtRoot() {
        let catalog = BrowseSessionCatalogStub()
        let family = MediaSourceContext(
            id: .familyMedia,
            catalog: catalog,
            playbackResolver: DirectMediaPlaybackResolver(),
            catalogStructure: .folderTree
        )
        let jellyfin = MediaSourceContext(
            id: .jellyfin,
            catalog: catalog,
            playbackResolver: DirectMediaPlaybackResolver(),
            catalogStructure: .libraryRoot
        )

        XCTAssertEqual(family.containerTypeLabel(containerID: nil), "文件夹")
        XCTAssertEqual(jellyfin.containerTypeLabel(containerID: nil), "媒体库")
        XCTAssertEqual(jellyfin.containerTypeLabel(containerID: "nested"), "文件夹")
    }
}

private actor BrowseSessionCatalogStub: MediaCatalogServicing {
    private(set) var requestCount = 0

    func fetchMedia(filter: MediaFilter, request: MediaPageRequest) async throws -> MediaPage {
        requestCount += 1
        return MediaPage(items: [
            MediaItem(
                id: "familyMedia:item",
                name: "示例",
                kind: .photo,
                size: 1,
                modified: Date(timeIntervalSince1970: 1),
                url: URL(string: "https://example.invalid/media")!,
                mediaPath: "example.jpg",
                thumbnailStatus: .pending
            )
        ])
    }
}

private actor BrowseSessionTimelineStub: MediaTimelineServicing {
    private(set) var indexRequestCount = 0

    func supportsTimeline() async -> Bool { true }

    func fetchTimelineIndex(request: MediaTimelineRequest) async throws -> MediaTimelineIndex {
        indexRequestCount += 1
        return MediaTimelineIndex(
            dateSemantics: "captured",
            timeZone: request.timeZone,
            years: [
                MediaTimelineYear(
                    key: "2026",
                    count: 1,
                    months: [MediaTimelineMonth(key: "2026-07", count: 1)]
                )
            ]
        )
    }

    func fetchTimelineMonth(
        key: String,
        request: MediaTimelineRequest,
        page: MediaPageRequest
    ) async throws -> MediaPage {
        MediaPage(items: [])
    }
}
