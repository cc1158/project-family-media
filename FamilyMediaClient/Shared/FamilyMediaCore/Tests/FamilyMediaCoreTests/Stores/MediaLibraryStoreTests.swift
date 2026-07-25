import Foundation
import Testing
@testable import FamilyMediaCore

@MainActor
struct MediaLibraryStoreTests {
    @Test func loadsFirstPage() async {
        let service = FakeMediaService()
        service.pages = [
            MediaPage(items: [makeMediaItem(id: "photo-1")], nextCursor: "next", hasMore: true)
        ]
        let store = MediaLibraryStore(
            title: "全部",
            filter: .all,
            mediaService: service,
            sortPreferences: MediaSortPreferenceStore(defaults: isolatedDefaults())
        )

        await store.load()

        #expect(store.state == .loaded([makeMediaItem(id: "photo-1")]))
        #expect(service.mediaRequests.count == 1)
        #expect(service.mediaRequests[0].filter == .all)
        #expect(service.mediaRequests[0].request.limit == 50)
        #expect(service.mediaRequests[0].request.cursor == nil)
        #expect(service.mediaRequests[0].request.sort == .capturedNewest)
    }

    @Test func changingSortResetsPaginationAndPersistsBySourceAndFilter() async {
        let defaults = isolatedDefaults()
        let preferences = MediaSortPreferenceStore(defaults: defaults)
        let first = makeMediaItem(id: "first")
        let sorted = makeMediaItem(id: "sorted")
        let service = FakeMediaService()
        service.pages = [
            MediaPage(items: [first], nextCursor: "next", hasMore: true),
            MediaPage(items: [sorted])
        ]
        let store = MediaLibraryStore(
            title: "视频",
            filter: .videos,
            mediaService: service,
            sourceID: .familyMedia,
            sortingProfile: .familyMedia,
            sortPreferences: preferences
        )

        await store.load()
        await store.changeSort(to: .nameDescending)

        #expect(store.state == .loaded([sorted]))
        #expect(store.selectedSort == .nameDescending)
        #expect(service.mediaRequests.map(\.request.cursor) == [nil, nil])
        #expect(service.mediaRequests.map(\.request.sort) == [.capturedNewest, .nameDescending])

        let recreated = MediaLibraryStore(
            title: "视频",
            filter: .videos,
            mediaService: FakeMediaService(),
            sourceID: .familyMedia,
            sortingProfile: .familyMedia,
            sortPreferences: preferences
        )
        let photos = MediaLibraryStore(
            title: "照片",
            filter: .photos,
            mediaService: FakeMediaService(),
            sourceID: .familyMedia,
            sortingProfile: .familyMedia,
            sortPreferences: preferences
        )
        #expect(recreated.selectedSort == .nameDescending)
        #expect(photos.selectedSort == .capturedNewest)
    }

    @Test func loadsMoreWhenLastItemAppears() async {
        let firstItem = makeMediaItem(id: "photo-1")
        let secondItem = makeMediaItem(id: "photo-2")
        let service = FakeMediaService()
        service.pages = [
            MediaPage(items: [firstItem], nextCursor: "next", hasMore: true),
            MediaPage(items: [secondItem], nextCursor: "", hasMore: false)
        ]
        let store = MediaLibraryStore(
            title: "全部",
            filter: .all,
            mediaService: service,
            sortPreferences: MediaSortPreferenceStore(defaults: isolatedDefaults())
        )

        await store.load()
        await store.loadMoreIfNeeded(currentItem: firstItem)

        #expect(store.state == .loaded([firstItem, secondItem]))
        #expect(service.mediaRequests.count == 2)
        #expect(service.mediaRequests[1].request.cursor == "next")
        #expect(service.mediaRequests[1].request.sort == .capturedNewest)
    }

    @Test func prefetchesBeforeTheLastItemAppears() async {
        let initialItems = (1...20).map { makeMediaItem(id: "photo-\($0)") }
        let nextItem = makeMediaItem(id: "photo-21")
        let service = FakeMediaService()
        service.pages = [
            MediaPage(items: initialItems, nextCursor: "next", hasMore: true),
            MediaPage(items: [nextItem], nextCursor: "", hasMore: false)
        ]
        let store = MediaLibraryStore(
            title: "全部",
            filter: .all,
            mediaService: service,
            sortPreferences: MediaSortPreferenceStore(defaults: isolatedDefaults())
        )

        await store.load()
        await store.loadMoreIfNeeded(currentItem: initialItems[12])

        #expect(store.state == .loaded(initialItems + [nextItem]))
        #expect(service.mediaRequests.count == 2)
    }

    @Test func doesNotPrefetchOutsideTheEndWindow() async {
        let initialItems = (1...20).map { makeMediaItem(id: "photo-\($0)") }
        let service = FakeMediaService()
        service.pages = [
            MediaPage(items: initialItems, nextCursor: "next", hasMore: true)
        ]
        let store = MediaLibraryStore(title: "全部", filter: .all, mediaService: service)

        await store.load()
        await store.loadMoreIfNeeded(currentItem: initialItems[11])

        #expect(service.mediaRequests.count == 1)
    }

    @Test func stopsPaginationWhenServerDoesNotAdvanceCursor() async {
        let firstItem = makeMediaItem(id: "photo-1")
        let duplicateItem = makeMediaItem(id: "photo-2")
        let service = FakeMediaService()
        service.pages = [
            MediaPage(items: [firstItem], nextCursor: "stuck", hasMore: true),
            MediaPage(items: [duplicateItem], nextCursor: "stuck", hasMore: true)
        ]
        let store = MediaLibraryStore(title: "全部", filter: .all, mediaService: service)

        await store.load()
        await store.loadMoreIfNeeded(currentItem: firstItem)
        await store.loadMoreIfNeeded(currentItem: duplicateItem)

        #expect(store.state == .loaded([firstItem, duplicateItem]))
        #expect(service.mediaRequests.count == 2)
    }

    @Test func removesDuplicateItemsWithinAndAcrossPages() async {
        let first = makeMediaItem(id: "photo-1")
        let second = makeMediaItem(id: "photo-2")
        let third = makeMediaItem(id: "photo-3")
        let service = FakeMediaService()
        service.pages = [
            MediaPage(items: [first, first, second], nextCursor: "next", hasMore: true),
            MediaPage(items: [second, third, third], nextCursor: "", hasMore: false)
        ]
        let store = MediaLibraryStore(title: "全部", filter: .all, mediaService: service)

        await store.load()
        await store.loadMoreIfNeeded(currentItem: second)

        #expect(store.state == .loaded([first, second, third]))
    }

    @Test func doesNotLoadMoreWhenThereIsNoNextPage() async {
        let item = makeMediaItem(id: "photo-1")
        let service = FakeMediaService()
        service.pages = [
            MediaPage(items: [item], nextCursor: "", hasMore: false)
        ]
        let store = MediaLibraryStore(title: "全部", filter: .all, mediaService: service)

        await store.load()
        await store.loadMoreIfNeeded(currentItem: item)

        #expect(service.mediaRequests.count == 1)
    }

    @Test func forceReloadsLoadedState() async {
        let firstItem = makeMediaItem(id: "photo-1")
        let secondItem = makeMediaItem(id: "photo-2")
        let service = FakeMediaService()
        service.pages = [
            MediaPage(items: [firstItem], nextCursor: "", hasMore: false),
            MediaPage(items: [secondItem], nextCursor: "", hasMore: false)
        ]
        let store = MediaLibraryStore(title: "全部", filter: .all, mediaService: service)

        await store.load()
        await store.load(force: true)

        #expect(store.state == .loaded([secondItem]))
        #expect(service.mediaRequests.count == 2)
    }

    @Test func refreshRebuildsLoadedPagesAndRecoversMovedAnchor() async {
        let first = makeMediaItem(id: "first")
        let anchor = makeMediaItem(id: "anchor")
        let inserted = makeMediaItem(id: "inserted")
        let service = FakeMediaService()
        service.pages = [
            MediaPage(items: [first], nextCursor: "initial-2", hasMore: true),
            MediaPage(items: [anchor]),
            MediaPage(items: [inserted], nextCursor: "refresh-2", hasMore: true),
            MediaPage(items: [first], nextCursor: "refresh-3", hasMore: true),
            MediaPage(items: [anchor])
        ]
        let store = MediaLibraryStore(title: "全部", filter: .all, mediaService: service)

        await store.load()
        await store.loadMoreIfNeeded(currentItem: first)
        await store.load(force: true, preservingItemID: anchor.id)

        #expect(store.state == .loaded([inserted, first, anchor]))
        #expect(
            service.mediaRequests.map(\.request.cursor) == [
                nil,
                "initial-2",
                nil,
                "refresh-2",
                "refresh-3"
            ]
        )
    }

    @Test func failedRefreshKeepsExistingItemsVisible() async {
        let item = makeMediaItem(id: "photo-1")
        let service = FakeMediaService()
        service.mediaResults = [
            .success(MediaPage(items: [item])),
            .failure(FakeError.failed)
        ]
        let store = MediaLibraryStore(title: "全部", filter: .all, mediaService: service)

        await store.load()
        await store.load(force: true)

        #expect(store.state == .loaded([item]))
        #expect(store.refreshMessage == .failure("测试错误"))
        #expect(store.loadMoreMessage == nil)
        #expect(!store.isRefreshing)
    }

    @Test func surfacesLoadFailure() async {
        let service = FakeMediaService()
        service.error = FakeError.failed
        let store = MediaLibraryStore(title: "全部", filter: .all, mediaService: service)

        await store.load()

        #expect(store.state == .failed("测试错误"))
    }

    @Test func cancelledInitialLoadReturnsToIdleWithoutFailureMessage() async {
        let service = FakeMediaService()
        service.error = CancellationError()
        let store = MediaLibraryStore(title: "全部", filter: .all, mediaService: service)

        await store.load()

        #expect(store.state == .idle)
        #expect(store.refreshMessage == nil)
        #expect(store.loadMoreMessage == nil)
    }

    @Test func foregroundImmediatelyRetriesAnIncompleteCancelledLoad() async {
        let item = makeMediaItem(id: "recovered")
        let service = FakeMediaService()
        service.mediaResults = [
            .failure(CancellationError()),
            .success(MediaPage(items: [item]))
        ]
        let store = MediaLibraryStore(title: "全部", filter: .all, mediaService: service)

        await store.load()
        #expect(store.state == .idle)

        await store.refreshAfterForegroundIfNeeded(minimumInterval: 60)

        #expect(service.mediaRequests.count == 2)
        #expect(store.state == .loaded([item]))
    }

    @Test func invalidCursorReloadsFirstPage() async {
        let firstItem = makeMediaItem(id: "photo-1")
        let refreshedItem = makeMediaItem(id: "photo-2")
        let service = FakeMediaService()
        service.mediaResults = [
            .success(MediaPage(items: [firstItem], nextCursor: "stale", hasMore: true)),
            .failure(APIClientError.unacceptableStatusCode(400, "invalid_cursor")),
            .success(MediaPage(items: [refreshedItem], nextCursor: "", hasMore: false))
        ]
        let store = MediaLibraryStore(title: "全部", filter: .all, mediaService: service)

        await store.load()
        await store.loadMoreIfNeeded(currentItem: firstItem)

        #expect(store.state == .loaded([refreshedItem]))
        #expect(service.mediaRequests.count == 3)
        #expect(service.mediaRequests[2].request.cursor == nil)
    }

    @Test func loadMoreFailureKeepsLoadedItems() async {
        let firstItem = makeMediaItem(id: "photo-1")
        let service = FakeMediaService()
        service.mediaResults = [
            .success(MediaPage(items: [firstItem], nextCursor: "next", hasMore: true)),
            .failure(FakeError.failed)
        ]
        let store = MediaLibraryStore(title: "全部", filter: .all, mediaService: service)

        await store.load()
        await store.loadMoreIfNeeded(currentItem: firstItem)

        #expect(store.state == .loaded([firstItem]))
        #expect(store.loadMoreMessage == .failure("测试错误"))
    }

    @Test func retriesFailedLoadMoreFromTheSameCursor() async {
        let firstItem = makeMediaItem(id: "photo-1")
        let secondItem = makeMediaItem(id: "photo-2")
        let service = FakeMediaService()
        service.mediaResults = [
            .success(MediaPage(items: [firstItem], nextCursor: "next", hasMore: true)),
            .failure(FakeError.failed),
            .success(MediaPage(items: [secondItem], nextCursor: "", hasMore: false))
        ]
        let store = MediaLibraryStore(title: "全部", filter: .all, mediaService: service)

        await store.load()
        await store.loadMoreIfNeeded(currentItem: firstItem)
        await store.retryLoadMore()

        #expect(store.state == .loaded([firstItem, secondItem]))
        #expect(store.loadMoreMessage == nil)
        #expect(service.mediaRequests.map(\.request.cursor) == [nil, "next", "next"])
    }

    @Test func loadClearsLoadMoreMessage() async {
        let firstItem = makeMediaItem(id: "photo-1")
        let refreshedItem = makeMediaItem(id: "photo-2")
        let service = FakeMediaService()
        service.mediaResults = [
            .success(MediaPage(items: [firstItem], nextCursor: "next", hasMore: true)),
            .failure(FakeError.failed),
            .success(MediaPage(items: [refreshedItem], nextCursor: "", hasMore: false))
        ]
        let store = MediaLibraryStore(title: "全部", filter: .all, mediaService: service)

        await store.load()
        await store.loadMoreIfNeeded(currentItem: firstItem)
        await store.load(force: true)

        #expect(store.state == .loaded([refreshedItem]))
        #expect(store.loadMoreMessage == nil)
    }

    @Test func successfulRefreshClearsRefreshMessage() async {
        let firstItem = makeMediaItem(id: "photo-1")
        let refreshedItem = makeMediaItem(id: "photo-2")
        let service = FakeMediaService()
        service.mediaResults = [
            .success(MediaPage(items: [firstItem])),
            .failure(FakeError.failed),
            .success(MediaPage(items: [refreshedItem]))
        ]
        let store = MediaLibraryStore(title: "全部", filter: .all, mediaService: service)

        await store.load()
        await store.load(force: true)
        #expect(store.refreshMessage == .failure("测试错误"))

        await store.load(force: true)

        #expect(store.state == .loaded([refreshedItem]))
        #expect(store.refreshMessage == nil)
    }

    @Test func stalePaginationResponseCannotOverwriteRefreshedContent() async throws {
        let oldItem = makeMediaItem(id: "old")
        let stalePageItem = makeMediaItem(id: "stale-page")
        let refreshedItem = makeMediaItem(id: "refreshed")
        let service = RacingMediaCatalogService(
            initialItem: oldItem,
            stalePageItem: stalePageItem,
            refreshedItem: refreshedItem
        )
        let store = MediaLibraryStore(title: "全部", filter: .all, mediaService: service)

        await store.load()
        let paginationTask = Task { @MainActor in
            await store.loadMoreIfNeeded(currentItem: oldItem)
        }
        try await waitUntil {
            await service.paginationRequestCount == 1
        }
        let paginationRequestCount = await service.paginationRequestCount
        #expect(paginationRequestCount == 1)
        await store.load(force: true)
        await paginationTask.value

        #expect(store.state == .loaded([refreshedItem]))
        #expect(store.loadMoreMessage == nil)
    }

    @Test func rapidSortChangesIgnoreTheOlderResponse() async throws {
        let initial = makeMediaItem(id: "initial")
        let stale = makeMediaItem(id: "stale-sort")
        let latest = makeMediaItem(id: "latest-sort")
        let service = RacingSortCatalogService(initial: initial, stale: stale, latest: latest)
        let store = MediaLibraryStore(
            title: "全部",
            filter: .all,
            mediaService: service,
            sortPreferences: MediaSortPreferenceStore(defaults: isolatedDefaults())
        )

        await store.load()
        let olderChange = Task { @MainActor in
            await store.changeSort(to: .nameAscending)
        }
        try await waitUntil { await service.slowRequestCount == 1 }
        await store.changeSort(to: .dateAddedNewest)
        await olderChange.value

        #expect(store.selectedSort == .dateAddedNewest)
        #expect(store.state == .loaded([latest]))
    }

    @Test func cancelledPaginationKeepsContentAndCanRetrySameCursor() async throws {
        let firstItem = makeMediaItem(id: "first")
        let nextItem = makeMediaItem(id: "next")
        let service = CancellablePaginationCatalogService(
            firstItem: firstItem,
            nextItem: nextItem
        )
        let store = MediaLibraryStore(title: "全部", filter: .all, mediaService: service)

        await store.load()
        let firstPagination = Task { @MainActor in
            await store.loadMoreIfNeeded(currentItem: firstItem)
        }
        try await waitUntil { await service.paginationRequestCount == 1 }

        firstPagination.cancel()
        await firstPagination.value

        #expect(store.state == .loaded([firstItem]))
        #expect(!store.isLoadingMore)
        #expect(store.loadMoreMessage == nil)

        await store.loadMoreIfNeeded(currentItem: firstItem)

        #expect(store.state == .loaded([firstItem, nextItem]))
        #expect(await service.requestedCursors == [nil, "next", "next"])
    }

    @Test func refreshesWhenRefreshCenterPublishes() async {
        let service = FakeMediaService()
        service.pages = [
            MediaPage(items: [makeMediaItem(id: "old")]),
            MediaPage(items: [makeMediaItem(id: "new")])
        ]
        let refreshCenter = MediaLibraryRefreshCenter()
        let store = MediaLibraryStore(
            title: "全部",
            filter: .all,
            mediaService: service,
            refreshCenter: refreshCenter
        )

        await store.load()
        refreshCenter.publishRefresh()
        await store.refreshIfNeeded()

        guard case .loaded(let items) = store.state else {
            Issue.record("expected loaded state")
            return
        }
        #expect(items.map(\.id) == ["new"])
    }

    @Test func deferredRefreshGenerationsCoalesceUntilVisibleStoreConsumesThem() async {
        let oldItem = makeMediaItem(id: "old")
        let newItem = makeMediaItem(id: "new")
        let service = FakeMediaService()
        service.pages = [
            MediaPage(items: [oldItem]),
            MediaPage(items: [newItem])
        ]
        let refreshCenter = MediaLibraryRefreshCenter()
        let store = MediaLibraryStore(
            title: "文件夹",
            filter: .all,
            mediaService: service,
            refreshCenter: refreshCenter
        )

        await store.load()
        refreshCenter.publishRefresh()
        refreshCenter.publishRefresh()

        await store.refreshIfNeeded(preservingItemID: oldItem.id)
        await store.refreshIfNeeded(preservingItemID: oldItem.id)

        #expect(service.mediaRequests.count == 2)
        #expect(store.state == .loaded([newItem]))
    }

    @Test func foregroundRefreshKeepsContentFreshWithoutDuplicateRequests() async {
        let oldItem = makeMediaItem(id: "old")
        let newItem = makeMediaItem(id: "new")
        let service = FakeMediaService()
        service.pages = [
            MediaPage(items: [oldItem]),
            MediaPage(items: [newItem])
        ]
        var now = Date(timeIntervalSince1970: 1_000)
        let store = MediaLibraryStore(
            title: "全部",
            filter: .all,
            mediaService: service,
            now: { now }
        )

        await store.load()
        now.addTimeInterval(30)
        await store.refreshAfterForegroundIfNeeded(minimumInterval: 60)
        #expect(service.mediaRequests.count == 1)
        #expect(store.state == .loaded([oldItem]))

        now.addTimeInterval(31)
        await store.refreshAfterForegroundIfNeeded(minimumInterval: 60)
        #expect(service.mediaRequests.count == 2)
        #expect(store.state == .loaded([newItem]))
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("等待分页请求启动超时")
    }
}

private actor RacingMediaCatalogService: MediaCatalogServicing {
    let initialItem: MediaItem
    let stalePageItem: MediaItem
    let refreshedItem: MediaItem
    private var firstPageRequestCount = 0
    private(set) var paginationRequestCount = 0

    init(initialItem: MediaItem, stalePageItem: MediaItem, refreshedItem: MediaItem) {
        self.initialItem = initialItem
        self.stalePageItem = stalePageItem
        self.refreshedItem = refreshedItem
    }

    func fetchMedia(filter: MediaFilter, request: MediaPageRequest) async throws -> MediaPage {
        if request.cursor != nil {
            paginationRequestCount += 1
            try await Task.sleep(for: .milliseconds(100))
            return MediaPage(items: [stalePageItem])
        }

        firstPageRequestCount += 1
        if firstPageRequestCount == 1 {
            return MediaPage(items: [initialItem], nextCursor: "next", hasMore: true)
        }
        return MediaPage(items: [refreshedItem])
    }
}

private actor CancellablePaginationCatalogService: MediaCatalogServicing {
    let firstItem: MediaItem
    let nextItem: MediaItem
    private(set) var requestedCursors: [String?] = []
    private(set) var paginationRequestCount = 0

    init(firstItem: MediaItem, nextItem: MediaItem) {
        self.firstItem = firstItem
        self.nextItem = nextItem
    }

    func fetchMedia(filter: MediaFilter, request: MediaPageRequest) async throws -> MediaPage {
        requestedCursors.append(request.cursor)
        guard request.cursor != nil else {
            return MediaPage(items: [firstItem], nextCursor: "next", hasMore: true)
        }

        paginationRequestCount += 1
        if paginationRequestCount == 1 {
            try await Task.sleep(for: .seconds(5))
        }
        return MediaPage(items: [nextItem], nextCursor: "", hasMore: false)
    }
}

private actor RacingSortCatalogService: MediaCatalogServicing {
    let initial: MediaItem
    let stale: MediaItem
    let latest: MediaItem
    private(set) var slowRequestCount = 0

    init(initial: MediaItem, stale: MediaItem, latest: MediaItem) {
        self.initial = initial
        self.stale = stale
        self.latest = latest
    }

    func fetchMedia(filter: MediaFilter, request: MediaPageRequest) async throws -> MediaPage {
        switch request.sort {
        case .nameAscending:
            slowRequestCount += 1
            try await Task.sleep(for: .milliseconds(100))
            return MediaPage(items: [stale])
        case .dateAddedNewest:
            return MediaPage(items: [latest])
        default:
            return MediaPage(items: [initial])
        }
    }
}
