import Foundation

@MainActor
public final class MediaLibraryStore: ObservableObject {
    private static let pageLimit = 50
    private static let paginationPrefetchItemCount = 8
    public static let foregroundRefreshInterval: TimeInterval = 60

    public let title: String
    public let filter: MediaFilter
    public let sourceID: MediaSourceID
    public let availableSortOptions: [MediaSortOption]
    public let isSortingAvailable: Bool

    @Published public private(set) var state: Loadable<[MediaItem]> = .idle
    @Published public private(set) var selectedSort: MediaSortOption
    @Published public private(set) var isLoadingMore = false
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var refreshMessage: AppMessage?
    @Published public private(set) var loadMoreMessage: AppMessage?

    private let mediaService: any MediaCatalogServicing
    private let containerID: String?
    private let refreshCenter: MediaLibraryRefreshCenter?
    private let sortingProfile: MediaSortingProfile
    private let sortPreferences: MediaSortPreferenceStore
    private let eventLogger: any ClientEventLogging
    private let now: () -> Date
    private var nextCursor: String?
    private var hasMore = false
    private var observedRefreshGeneration = 0
    private var contentGeneration = 0
    private var lastCompletedLoad: Date?
    private var loadedPageCount = 0

    public init(
        title: String,
        filter: MediaFilter,
        mediaService: any MediaCatalogServicing,
        sourceID: MediaSourceID = .familyMedia,
        sortingProfile: MediaSortingProfile? = nil,
        sortPreferences: MediaSortPreferenceStore = MediaSortPreferenceStore(),
        containerID: String? = nil,
        refreshCenter: MediaLibraryRefreshCenter? = nil,
        now: @escaping () -> Date = Date.init,
        eventLogger: any ClientEventLogging = ClientEventLog.shared
    ) {
        self.title = title
        self.filter = filter
        self.mediaService = mediaService
        self.sourceID = sourceID
        self.containerID = containerID
        self.refreshCenter = refreshCenter
        let profile = sortingProfile ?? .standard(for: sourceID)
        self.sortingProfile = profile
        self.sortPreferences = sortPreferences
        self.availableSortOptions = profile.options
        self.isSortingAvailable = profile.isAvailable(containerID: containerID)
        self.selectedSort = sortPreferences.selectedSort(
            sourceID: sourceID,
            filter: filter,
            profile: profile
        )
        self.now = now
        self.eventLogger = eventLogger
        self.observedRefreshGeneration = refreshCenter?.generation ?? 0
    }

    public func load(
        force: Bool = false,
        preservingItemID: String? = nil
    ) async {
        if case .loading = state {
            return
        }
        guard !isRefreshing else { return }

        if !force, case .loaded = state {
            return
        }

        contentGeneration &+= 1
        let requestGeneration = contentGeneration
        let requestedSort = selectedSort

        let retainedItems: [MediaItem]?
        let retainedPageCount: Int
        if force, case .loaded(let items) = state {
            retainedItems = items
            retainedPageCount = max(1, loadedPageCount)
            isRefreshing = true
        } else {
            retainedItems = nil
            retainedPageCount = 1
            state = .loading
        }
        defer {
            if requestGeneration == contentGeneration {
                isRefreshing = false
            }
        }
        refreshMessage = nil
        loadMoreMessage = nil

        do {
            let result = try await fetchPages(
                minimumPageCount: retainedPageCount,
                preservingItemID: preservingItemID,
                sort: requestedSort
            )
            guard requestGeneration == contentGeneration else { return }
            nextCursor = result.nextCursor
            hasMore = result.hasMore
            loadedPageCount = result.pageCount
            loadMoreMessage = nil
            state = result.items.isEmpty ? .empty : .loaded(result.items)
            lastCompletedLoad = now()
        } catch let error where TaskCancellation.matches(error) {
            guard requestGeneration == contentGeneration else { return }
            if let retainedItems {
                state = .loaded(retainedItems)
            } else {
                state = .idle
            }
        } catch {
            guard requestGeneration == contentGeneration else { return }
            let message = AppErrorMapper.message(for: error)
            if let retainedItems {
                state = .loaded(retainedItems)
                refreshMessage = .failure(message)
            } else {
                state = .failed(message)
            }
            lastCompletedLoad = now()
        }
    }

    public func changeSort(to option: MediaSortOption) async {
        guard isSortingAvailable, availableSortOptions.contains(option), option != selectedSort else { return }

        contentGeneration &+= 1
        let requestGeneration = contentGeneration
        selectedSort = option
        sortPreferences.save(option, sourceID: sourceID, filter: filter)
        nextCursor = nil
        hasMore = false
        loadedPageCount = 0
        isLoadingMore = false
        isRefreshing = false
        refreshMessage = nil
        loadMoreMessage = nil
        state = .loading

        do {
            let result = try await fetchPages(
                minimumPageCount: 1,
                preservingItemID: nil,
                sort: option
            )
            guard requestGeneration == contentGeneration else { return }
            nextCursor = result.nextCursor
            hasMore = result.hasMore
            loadedPageCount = result.pageCount
            state = result.items.isEmpty ? .empty : .loaded(result.items)
            lastCompletedLoad = now()
        } catch let error where TaskCancellation.matches(error) {
            guard requestGeneration == contentGeneration else { return }
            state = .idle
        } catch {
            guard requestGeneration == contentGeneration else { return }
            state = .failed(AppErrorMapper.message(for: error))
            lastCompletedLoad = now()
        }
    }

    public func synchronizePersistedSort() async {
        let persisted = sortPreferences.selectedSort(
            sourceID: sourceID,
            filter: filter,
            profile: sortingProfile
        )
        await changeSort(to: persisted)
    }

    public func refreshIfNeeded(preservingItemID: String? = nil) async {
        guard let refreshCenter else { return }
        guard refreshCenter.generation != observedRefreshGeneration else { return }
        observedRefreshGeneration = refreshCenter.generation
        await load(force: true, preservingItemID: preservingItemID)
    }

    public func refreshAfterForegroundIfNeeded(
        minimumInterval: TimeInterval = foregroundRefreshInterval,
        preservingItemID: String? = nil
    ) async {
        guard let lastCompletedLoad else {
            await load()
            return
        }
        guard now().timeIntervalSince(lastCompletedLoad) >= minimumInterval else { return }
        await load(force: true, preservingItemID: preservingItemID)
    }

    public func loadMoreIfNeeded(currentItem item: MediaItem) async {
        guard
            hasMore,
            !isLoadingMore,
            !isRefreshing,
            case .loaded(let items) = state,
            items.suffix(Self.paginationPrefetchItemCount).contains(where: { $0.id == item.id })
        else {
            return
        }

        isLoadingMore = true
        defer { isLoadingMore = false }
        let requestGeneration = contentGeneration
        let requestedCursor = nextCursor
        let requestedSort = selectedSort
        let operationID = UUID()
        logPagination(operationID: operationID, outcome: .started)

        do {
            let page = try await mediaService.fetchMedia(
                containerID: containerID,
                filter: filter,
                request: MediaPageRequest(
                    limit: Self.pageLimit,
                    cursor: nextCursor,
                    sort: requestedSort
                )
            )
            guard requestGeneration == contentGeneration else {
                logPagination(operationID: operationID, outcome: .cancelled)
                return
            }
            let candidateCursor = page.nextCursor.isEmpty ? nil : page.nextCursor
            let cursorAdvanced = candidateCursor != nil && candidateCursor != requestedCursor
            nextCursor = cursorAdvanced ? candidateCursor : nil
            hasMore = page.hasMore && cursorAdvanced
            loadedPageCount &+= 1
            loadMoreMessage = nil
            state = .loaded(Self.removingDuplicateItems(items + page.items))
            logPagination(operationID: operationID, outcome: .succeeded)
        } catch APIClientError.unacceptableStatusCode(400, "invalid_cursor") {
            guard requestGeneration == contentGeneration else {
                logPagination(operationID: operationID, outcome: .cancelled)
                return
            }
            logPagination(operationID: operationID, outcome: .failed)
            await load(force: true)
        } catch let error where TaskCancellation.matches(error) {
            logPagination(operationID: operationID, outcome: .cancelled)
            return
        } catch {
            guard requestGeneration == contentGeneration else {
                logPagination(operationID: operationID, outcome: .cancelled)
                return
            }
            loadMoreMessage = .failure(AppErrorMapper.message(for: error))
            logPagination(operationID: operationID, outcome: .failed)
        }
    }

    public func retryLoadMore() async {
        guard case .loaded(let items) = state, let lastItem = items.last else { return }
        await loadMoreIfNeeded(currentItem: lastItem)
    }

    private static func removingDuplicateItems(_ items: [MediaItem]) -> [MediaItem] {
        var seenIDs = Set<String>()
        return items.filter { seenIDs.insert($0.id).inserted }
    }

    private func logPagination(operationID: UUID, outcome: ClientEventOutcome) {
        eventLogger.record(
            category: .browse,
            code: "browse.directory.page",
            operationID: operationID,
            outcome: outcome,
            sourceID: sourceID
        )
    }

    /// Rebuilds the already-loaded pagination window during refresh so a user who
    /// has browsed beyond the first page does not suddenly lose their position.
    /// At most two extra pages are inspected when an anchor moved because new
    /// media was inserted ahead of it.
    private func fetchPages(
        minimumPageCount: Int,
        preservingItemID: String?,
        sort: MediaSortOption
    ) async throws -> PageWindow {
        var items: [MediaItem] = []
        var cursor: String?
        var hasMore = false
        var pageCount = 0
        var seenCursors = Set<String>()
        let anchorSearchLimit = minimumPageCount + 2

        repeat {
            let page = try await mediaService.fetchMedia(
                containerID: containerID,
                filter: filter,
                request: MediaPageRequest(limit: Self.pageLimit, cursor: cursor, sort: sort)
            )
            pageCount &+= 1
            items = Self.removingDuplicateItems(items + page.items)
            hasMore = page.hasMore

            let candidateCursor = page.nextCursor.isEmpty ? nil : page.nextCursor
            guard hasMore, let candidateCursor else {
                hasMore = false
                cursor = nil
                break
            }
            guard seenCursors.insert(candidateCursor).inserted else {
                hasMore = false
                cursor = nil
                break
            }
            cursor = candidateCursor

            let loadedPreviousDepth = pageCount >= minimumPageCount
            let anchorWasRecovered = preservingItemID.map { anchorID in
                items.contains { $0.id == anchorID }
            } ?? true
            if loadedPreviousDepth && (anchorWasRecovered || pageCount >= anchorSearchLimit) {
                break
            }
        } while hasMore

        return PageWindow(
            items: items,
            nextCursor: cursor,
            hasMore: hasMore,
            pageCount: pageCount
        )
    }
}

private struct PageWindow {
    let items: [MediaItem]
    let nextCursor: String?
    let hasMore: Bool
    let pageCount: Int
}
