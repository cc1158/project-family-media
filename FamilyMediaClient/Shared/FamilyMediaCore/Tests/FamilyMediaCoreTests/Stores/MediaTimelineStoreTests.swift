import Foundation
import Testing
@testable import FamilyMediaCore

@MainActor
struct MediaTimelineStoreTests {
    @Test func unavailableSourceFallsBackToDirectory() async {
        let defaults = makeDefaults()
        defaults.set(MediaBrowseMode.month.rawValue, forKey: "media.browseMode.familyMedia.all")
        let store = MediaTimelineStore(
            service: TimelineServiceFake(available: false),
            sourceID: .familyMedia,
            filter: .all,
            containerID: nil,
            defaults: defaults
        )

        await store.prepare()

        #expect(!store.isAvailable)
        #expect(store.mode == .directory)
    }

    @Test func loadsIndexAndMonthAndPersistsModeByFilter() async {
        let defaults = makeDefaults()
        let service = TimelineServiceFake(available: true)
        let store = MediaTimelineStore(
            service: service,
            sourceID: .familyMedia,
            filter: .photos,
            containerID: "folder",
            defaults: defaults,
            timeZone: { "Asia/Shanghai" }
        )

        await store.prepare()
        await store.changeMode(.month)
        await store.loadMonth("2026-07")

        #expect(store.years.map(\.key) == ["2026"])
        #expect(store.monthItems["2026-07"]?.count == 1)
        #expect(defaults.string(forKey: "media.browseMode.familyMedia.photos") == "month")
        let requests = await service.requests
        #expect(requests.first?.timeZone == "Asia/Shanghai")
        #expect(requests.first?.containerID == "folder")
    }

    @Test func changingDirectionClearsOldMonthContent() async {
        let store = MediaTimelineStore(
            service: TimelineServiceFake(available: true),
            sourceID: .familyMedia,
            filter: .all,
            containerID: nil,
            defaults: makeDefaults()
        )
        await store.prepare()
        await store.changeMode(.month)
        await store.loadMonth("2026-07")
        #expect(!store.monthItems.isEmpty)

        await store.changeDirection(.oldest)

        #expect(store.monthItems.isEmpty)
        #expect(store.direction == .oldest)
    }

    @Test func monthRequestsUseTheTimeZoneOfTheirLoadedIndex() async {
        let service = TimelineServiceFake(available: true)
        var currentTimeZone = "Asia/Shanghai"
        let store = MediaTimelineStore(
            service: service,
            sourceID: .familyMedia,
            filter: .all,
            containerID: nil,
            defaults: makeDefaults(),
            timeZone: { currentTimeZone }
        )

        await store.prepare()
        await store.changeMode(.month)
        currentTimeZone = "America/Los_Angeles"
        await store.loadMonth("2026-07")

        let requests = await service.requests
        #expect(requests.map(\.timeZone) == ["Asia/Shanghai", "Asia/Shanghai"])
    }

    @Test func paginationStopsWhenCursorDoesNotAdvance() async {
        let service = SequencedTimelineServiceFake(pages: [
            MediaPage(items: [item("one")], nextCursor: "next", hasMore: true),
            MediaPage(items: [item("two")], nextCursor: "next", hasMore: true)
        ])
        let store = makeStore(service: service)
        await store.prepare()
        await store.changeMode(.month)
        await store.loadMonth("2026-07")
        await store.loadMore(month: "2026-07")
        await store.loadMore(month: "2026-07")

        #expect(await service.monthRequestCount == 2)
        #expect(store.monthItems["2026-07"]?.map(\.name) == ["one", "two"])
    }

    @Test func forceReloadClearsPreviousPaginationState() async {
        let service = SequencedTimelineServiceFake(pages: [
            MediaPage(items: [item("old")], nextCursor: "next", hasMore: true),
            MediaPage(items: [item("fresh")])
        ])
        let store = makeStore(service: service)
        await store.prepare()
        await store.changeMode(.month)
        await store.loadMonth("2026-07")
        await store.loadMonth("2026-07", force: true)
        await store.loadMore(month: "2026-07")

        #expect(await service.monthRequestCount == 2)
        #expect(store.monthItems["2026-07"]?.map(\.name) == ["fresh"])
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "MediaTimelineStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeStore(service: any MediaTimelineServicing) -> MediaTimelineStore {
        MediaTimelineStore(
            service: service,
            sourceID: .familyMedia,
            filter: .all,
            containerID: nil,
            defaults: makeDefaults()
        )
    }

    private func item(_ name: String) -> MediaItem {
        MediaItem(
            id: name,
            name: name,
            kind: .photo,
            size: 1,
            modified: Date(timeIntervalSince1970: 1),
            url: URL(string: "https://example.com/\(name)")!,
            mediaPath: name,
            thumbnailStatus: .ready
        )
    }
}

private actor TimelineServiceFake: MediaTimelineServicing {
    let available: Bool
    private(set) var requests: [MediaTimelineRequest] = []

    init(available: Bool) { self.available = available }

    func supportsTimeline() async -> Bool { available }

    func fetchTimelineIndex(request: MediaTimelineRequest) async throws -> MediaTimelineIndex {
        requests.append(request)
        return MediaTimelineIndex(
            dateSemantics: "captured",
            timeZone: request.timeZone,
            years: [MediaTimelineYear(key: "2026", count: 1, months: [MediaTimelineMonth(key: "2026-07", count: 1)])]
        )
    }

    func fetchTimelineMonth(key: String, request: MediaTimelineRequest, page: MediaPageRequest) async throws -> MediaPage {
        requests.append(request)
        return MediaPage(items: [MediaItem(
            id: "familyMedia:item",
            name: "item.jpg",
            kind: .photo,
            size: 1,
            modified: Date(timeIntervalSince1970: 1),
            timelineDate: Date(timeIntervalSince1970: 1),
            url: URL(string: "https://example.com/item.jpg")!,
            mediaPath: "item.jpg",
            thumbnailStatus: .ready
        )])
    }
}

private actor SequencedTimelineServiceFake: MediaTimelineServicing {
    private var pages: [MediaPage]
    private(set) var monthRequestCount = 0

    init(pages: [MediaPage]) { self.pages = pages }

    func supportsTimeline() async -> Bool { true }

    func fetchTimelineIndex(request: MediaTimelineRequest) async throws -> MediaTimelineIndex {
        MediaTimelineIndex(
            dateSemantics: "captured",
            timeZone: request.timeZone,
            years: [MediaTimelineYear(key: "2026", count: 2, months: [MediaTimelineMonth(key: "2026-07", count: 2)])]
        )
    }

    func fetchTimelineMonth(key: String, request: MediaTimelineRequest, page: MediaPageRequest) async throws -> MediaPage {
        monthRequestCount += 1
        guard !pages.isEmpty else { return MediaPage(items: []) }
        return pages.removeFirst()
    }
}
