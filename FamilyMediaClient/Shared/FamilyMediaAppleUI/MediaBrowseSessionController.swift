import Combine
import FamilyMediaCore
import Foundation

/// Coordinates the shared directory/timeline lifecycle while leaving scrolling,
/// focus, navigation and layout decisions to the platform view.
@MainActor
final class MediaBrowseSessionController: ObservableObject {
    let library: MediaLibraryStore
    let timeline: MediaTimelineStore

    private let sourceID: MediaSourceID
    private let eventLogger: any ClientEventLogging
    private var cancellables: Set<AnyCancellable> = []

    init(
        title: String,
        filter: MediaFilter,
        source: MediaSourceContext,
        refreshCenter: MediaLibraryRefreshCenter,
        containerID: String? = nil,
        eventLogger: any ClientEventLogging = ClientEventLog.shared
    ) {
        sourceID = source.id
        self.eventLogger = eventLogger
        library = MediaLibraryStore(
            title: title,
            filter: filter,
            mediaService: source.catalog,
            sourceID: source.id,
            sortingProfile: source.sortingProfile,
            containerID: containerID,
            refreshCenter: refreshCenter
        )
        timeline = MediaTimelineStore(
            service: source.timeline,
            sourceID: source.id,
            filter: filter,
            containerID: containerID
        )
        observeStores()
    }

    init(
        library: MediaLibraryStore,
        timeline: MediaTimelineStore,
        sourceID: MediaSourceID,
        eventLogger: any ClientEventLogging = ClientEventLog.shared
    ) {
        self.library = library
        self.timeline = timeline
        self.sourceID = sourceID
        self.eventLogger = eventLogger
        observeStores()
    }

    func prepare(preservingItemID: String?) async {
        let operationID = beginEvent("browse.prepare")
        await timeline.prepare()
        if !Task.isCancelled, timeline.mode == .directory {
            await loadDirectory(preservingItemID: preservingItemID)
        }
        finishEvent("browse.prepare", operationID: operationID)
    }

    func changeMode(
        to mode: MediaBrowseMode,
        preservingItemID: String?
    ) async {
        let operationID = beginEvent("browse.mode.change")
        await timeline.changeMode(mode)
        if !Task.isCancelled, mode == .directory {
            await loadDirectory(preservingItemID: preservingItemID)
        }
        finishEvent("browse.mode.change", operationID: operationID)
    }

    func refresh(preservingItemID: String?) async {
        let operationID = beginEvent("browse.refresh")
        if timeline.mode == .directory {
            await library.refreshIfNeeded(preservingItemID: preservingItemID)
        } else {
            await timeline.refresh()
        }
        finishEvent("browse.refresh", operationID: operationID)
    }

    func refreshAfterForeground(preservingItemID: String?) async {
        guard timeline.mode == .directory else { return }
        let operationID = beginEvent("browse.foreground.refresh")
        await library.refreshAfterForegroundIfNeeded(
            preservingItemID: preservingItemID
        )
        finishEvent("browse.foreground.refresh", operationID: operationID)
    }

    func refreshAfterViewerDismiss(preservingItemID: String?) async {
        guard timeline.mode == .directory else { return }
        let operationID = beginEvent("browse.viewer.return")
        await library.refreshIfNeeded(preservingItemID: preservingItemID)
        finishEvent("browse.viewer.return", operationID: operationID)
    }

    func reloadDirectory(preservingItemID: String?) async {
        let operationID = beginEvent("browse.directory.reload")
        await library.load(force: true, preservingItemID: preservingItemID)
        finishEvent("browse.directory.reload", operationID: operationID)
    }

    private func loadDirectory(preservingItemID: String?) async {
        await library.synchronizePersistedSort()
        guard !Task.isCancelled else { return }
        await library.load()
        guard !Task.isCancelled else { return }
        await library.refreshIfNeeded(preservingItemID: preservingItemID)
        guard !Task.isCancelled else { return }
        await library.refreshAfterForegroundIfNeeded(
            preservingItemID: preservingItemID
        )
    }

    private func observeStores() {
        Publishers.Merge(
            library.objectWillChange,
            timeline.objectWillChange
        )
        .sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        .store(in: &cancellables)
    }

    private func beginEvent(_ code: String) -> UUID {
        let operationID = UUID()
        eventLogger.record(
            category: .browse,
            code: code,
            operationID: operationID,
            outcome: .started,
            sourceID: sourceID
        )
        return operationID
    }

    private func finishEvent(_ code: String, operationID: UUID) {
        eventLogger.record(
            category: .browse,
            code: code,
            operationID: operationID,
            outcome: Task.isCancelled ? .cancelled : currentOutcome,
            sourceID: sourceID
        )
    }

    private var currentOutcome: ClientEventOutcome {
        if timeline.mode == .directory {
            if case .failed = library.state { return .failed }
        } else if case .failed = timeline.indexState {
            return .failed
        }
        return .succeeded
    }
}
