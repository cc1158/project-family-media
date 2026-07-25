import Foundation

public struct MediaTimelineMonthContent: Equatable, Sendable {
    public let items: [MediaItem]
    public let isLoaded: Bool
    public let isLoading: Bool
    public let errorMessage: String?
}

@MainActor
public final class MediaTimelineStore: ObservableObject {
    private static let pageLimit = 50

    @Published public private(set) var mode: MediaBrowseMode = .directory
    @Published public private(set) var direction: MediaTimelineDirection = .newest
    @Published public private(set) var isAvailable = false
    @Published public private(set) var indexState: Loadable<MediaTimelineIndex> = .idle
    @Published private var monthStates: [String: MonthPageState] = [:]

    private let service: (any MediaTimelineServicing)?
    private let filter: MediaFilter
    private let containerID: String?
    private let preferences: MediaTimelinePreferenceStore
    private let sourceID: MediaSourceID
    private let eventLogger: any ClientEventLogging
    private let currentTimeZoneIdentifier: () -> String
    private var activeTimeZoneIdentifier: String
    private var generation = 0

    public init(
        service: (any MediaTimelineServicing)?,
        sourceID: MediaSourceID,
        filter: MediaFilter,
        containerID: String?,
        defaults: UserDefaults = .standard,
        timeZone: @escaping () -> String = { TimeZone.current.identifier },
        eventLogger: any ClientEventLogging = ClientEventLog.shared
    ) {
        self.service = service
        self.filter = filter
        self.containerID = containerID
        self.sourceID = sourceID
        self.eventLogger = eventLogger
        self.currentTimeZoneIdentifier = timeZone
        self.activeTimeZoneIdentifier = timeZone()
        let preferences = MediaTimelinePreferenceStore(
            sourceID: sourceID,
            filter: filter,
            defaults: defaults
        )
        self.preferences = preferences
        mode = preferences.mode
        direction = preferences.direction
    }

    public var years: [MediaTimelineYear] {
        guard case .loaded(let index) = indexState else { return [] }
        return index.years
    }

    public var months: [MediaTimelineMonth] { years.flatMap(\.months) }

    public var flattenedItems: [MediaItem] {
        months.flatMap { monthStates[$0.key]?.items ?? [] }
    }

    public var monthItems: [String: [MediaItem]] {
        monthStates.mapValues(\.items)
    }

    public func content(for monthKey: String) -> MediaTimelineMonthContent {
        let state = monthStates[monthKey] ?? MonthPageState()
        return MediaTimelineMonthContent(
            items: state.items,
            isLoaded: state.hasLoaded,
            isLoading: state.isLoading,
            errorMessage: state.errorMessage
        )
    }

    public func prepare() async {
        guard let service else { mode = .directory; return }
        isAvailable = await service.supportsTimeline()
        guard isAvailable else {
            mode = .directory
            return
        }
        if mode != .directory { await loadIndex() }
    }

    public func changeMode(_ newMode: MediaBrowseMode) async {
        guard newMode == .directory || isAvailable else { return }
        mode = newMode
        preferences.save(mode: newMode)
        if newMode != .directory { await loadIndex() }
    }

    public func changeDirection(_ newDirection: MediaTimelineDirection) async {
        guard newDirection != direction else { return }
        direction = newDirection
        preferences.save(direction: newDirection)
        resetContent()
        await loadIndex(force: true)
    }

    public func loadIndex(force: Bool = false) async {
        guard let service, isAvailable else { return }
        if !force, case .loaded = indexState { return }
        generation &+= 1
        let requestGeneration = generation
        let timeZoneIdentifier = currentTimeZoneIdentifier()
        activeTimeZoneIdentifier = timeZoneIdentifier
        let indexRequest = makeRequest(timeZoneIdentifier: timeZoneIdentifier)
        let operationID = UUID()
        log(code: "browse.timeline.index", operationID: operationID, outcome: .started)
        indexState = .loading
        do {
            let value = try await service.fetchTimelineIndex(request: indexRequest)
            guard generation == requestGeneration else {
                log(code: "browse.timeline.index", operationID: operationID, outcome: .cancelled)
                return
            }
            indexState = value.years.isEmpty ? .empty : .loaded(value)
            log(code: "browse.timeline.index", operationID: operationID, outcome: .succeeded)
        } catch let error where TaskCancellation.matches(error) {
            guard generation == requestGeneration else {
                log(code: "browse.timeline.index", operationID: operationID, outcome: .cancelled)
                return
            }
            indexState = .idle
            log(code: "browse.timeline.index", operationID: operationID, outcome: .cancelled)
        } catch {
            guard generation == requestGeneration else {
                log(code: "browse.timeline.index", operationID: operationID, outcome: .cancelled)
                return
            }
            indexState = .failed(AppErrorMapper.message(for: error))
            log(code: "browse.timeline.index", operationID: operationID, outcome: .failed)
        }
    }

    public func loadMonth(_ key: String, force: Bool = false) async {
        guard let service, isAvailable else { return }
        var state = monthStates[key] ?? MonthPageState()
        guard !state.isLoading else { return }
        if !force, state.hasLoaded { return }
        state.beginLoading(resetPage: true)
        monthStates[key] = state
        let requestGeneration = generation
        let operationID = UUID()
        log(code: "browse.timeline.month", operationID: operationID, outcome: .started)
        do {
            let page = try await service.fetchTimelineMonth(
                key: key,
                request: activeRequest,
                page: MediaPageRequest(limit: Self.pageLimit)
            )
            guard generation == requestGeneration else {
                log(code: "browse.timeline.month", operationID: operationID, outcome: .cancelled)
                return
            }
            state.completeInitialPage(page)
            monthStates[key] = state
            log(code: "browse.timeline.month", operationID: operationID, outcome: .succeeded)
        } catch let error where TaskCancellation.matches(error) {
            guard generation == requestGeneration else {
                log(code: "browse.timeline.month", operationID: operationID, outcome: .cancelled)
                return
            }
            state.cancelLoading()
            monthStates[key] = state
            log(code: "browse.timeline.month", operationID: operationID, outcome: .cancelled)
            return
        } catch {
            guard generation == requestGeneration else {
                log(code: "browse.timeline.month", operationID: operationID, outcome: .cancelled)
                return
            }
            state.fail(with: AppErrorMapper.message(for: error))
            monthStates[key] = state
            log(code: "browse.timeline.month", operationID: operationID, outcome: .failed)
        }
    }

    public func loadMore(month key: String) async {
        guard let service, var state = monthStates[key], state.canLoadMore else { return }
        let requestedCursor = state.nextCursor
        state.beginLoading(resetPage: false)
        monthStates[key] = state
        let requestGeneration = generation
        let operationID = UUID()
        log(code: "browse.timeline.page", operationID: operationID, outcome: .started)
        do {
            let page = try await service.fetchTimelineMonth(
                key: key,
                request: activeRequest,
                page: MediaPageRequest(limit: Self.pageLimit, cursor: requestedCursor)
            )
            guard generation == requestGeneration else {
                log(code: "browse.timeline.page", operationID: operationID, outcome: .cancelled)
                return
            }
            state.append(page, requestedCursor: requestedCursor)
            monthStates[key] = state
            log(code: "browse.timeline.page", operationID: operationID, outcome: .succeeded)
        } catch APIClientError.unacceptableStatusCode(400, "invalid_cursor") {
            guard generation == requestGeneration else {
                log(code: "browse.timeline.page", operationID: operationID, outcome: .cancelled)
                return
            }
            state.cancelLoading()
            monthStates[key] = state
            log(code: "browse.timeline.page", operationID: operationID, outcome: .failed)
            await loadMonth(key, force: true)
        } catch let error where TaskCancellation.matches(error) {
            guard generation == requestGeneration else {
                log(code: "browse.timeline.page", operationID: operationID, outcome: .cancelled)
                return
            }
            state.cancelLoading()
            monthStates[key] = state
            log(code: "browse.timeline.page", operationID: operationID, outcome: .cancelled)
        } catch {
            guard generation == requestGeneration else {
                log(code: "browse.timeline.page", operationID: operationID, outcome: .cancelled)
                return
            }
            state.fail(with: AppErrorMapper.message(for: error))
            monthStates[key] = state
            log(code: "browse.timeline.page", operationID: operationID, outcome: .failed)
        }
    }

    public func refresh() async {
        resetContent()
        await loadIndex(force: true)
    }

    public func needsMore(month key: String, item: MediaItem) -> Bool {
        monthStates[key]?.needsPrefetch(for: item) == true
    }

    private var activeRequest: MediaTimelineRequest {
        makeRequest(timeZoneIdentifier: activeTimeZoneIdentifier)
    }

    private func makeRequest(timeZoneIdentifier: String) -> MediaTimelineRequest {
        MediaTimelineRequest(
            containerID: containerID,
            filter: filter,
            timeZone: timeZoneIdentifier,
            direction: direction
        )
    }

    private func resetContent() {
        generation &+= 1
        monthStates = [:]
        indexState = .idle
    }

    private func log(
        code: String,
        operationID: UUID,
        outcome: ClientEventOutcome
    ) {
        eventLogger.record(
            category: .browse,
            code: code,
            operationID: operationID,
            outcome: outcome,
            sourceID: sourceID
        )
    }
}

private struct MonthPageState: Equatable {
    var items: [MediaItem] = []
    var nextCursor: String?
    var hasMore = false
    var isLoading = false
    var hasLoaded = false
    var errorMessage: String?

    var canLoadMore: Bool {
        hasLoaded && hasMore && nextCursor != nil && !isLoading
    }

    mutating func beginLoading(resetPage: Bool) {
        isLoading = true
        errorMessage = nil
        if resetPage {
            nextCursor = nil
            hasMore = false
        }
    }

    mutating func completeInitialPage(_ page: MediaPage) {
        items = Self.removingDuplicates(page.items)
        hasLoaded = true
        isLoading = false
        updatePagination(page, previousCursor: nil)
    }

    mutating func append(_ page: MediaPage, requestedCursor: String?) {
        items = Self.removingDuplicates(items + page.items)
        isLoading = false
        updatePagination(page, previousCursor: requestedCursor)
    }

    mutating func fail(with message: String) {
        isLoading = false
        errorMessage = message
    }

    mutating func cancelLoading() {
        isLoading = false
    }

    func needsPrefetch(for item: MediaItem) -> Bool {
        canLoadMore && items.suffix(8).contains(item)
    }

    private mutating func updatePagination(_ page: MediaPage, previousCursor: String?) {
        let candidate = page.nextCursor.isEmpty ? nil : page.nextCursor
        let advanced = candidate != nil && candidate != previousCursor
        nextCursor = advanced ? candidate : nil
        hasMore = page.hasMore && advanced
    }

    private static func removingDuplicates(_ items: [MediaItem]) -> [MediaItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }
}
