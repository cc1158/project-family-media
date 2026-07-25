import AVKit
import Combine
import Foundation

public enum MediaViewerNavigationOrigin: Equatable, Sendable {
    case initial
    case manual
    case automatic
}

public struct MediaViewerNavigationEvent: Equatable, Sendable {
    public let sequence: UInt64
    public let itemID: String
    public let index: Int
    public let origin: MediaViewerNavigationOrigin

    public init(
        sequence: UInt64,
        itemID: String,
        index: Int,
        origin: MediaViewerNavigationOrigin
    ) {
        self.sequence = sequence
        self.itemID = itemID
        self.index = index
        self.origin = origin
    }
}

@MainActor
public final class MediaViewerCoordinator: ObservableObject {
    public typealias DismissHandler = @MainActor () -> Void
    public typealias CurrentItemHandler = @MainActor (MediaItem) -> Void

    public private(set) var session: MediaViewerSession
    @Published public private(set) var navigationEvent: MediaViewerNavigationEvent
    @Published public private(set) var playbackSnapshot: MediaPlaybackSnapshot
    @Published public private(set) var isPhotoAutoAdvancePaused = false
    @Published public private(set) var isAwaitingAutoplayContinuation = false
    @Published public private(set) var isRegeneratingThumbnail = false
    @Published public private(set) var regenerationMessage: AppMessage?

    private let playbackSession: MediaPlaybackSessionController
    private let photoAutoAdvanceScheduler: any DelayedActionScheduling
    private let regenerationStore: ThumbnailRegenerationStore
    private var cancellables: Set<AnyCancellable> = []
    private var onShouldDismiss: DismissHandler?
    private var onCurrentItemChanged: CurrentItemHandler?
    private var autoplayLimit = PlaybackSettings.defaultAutoplayLimit
    private var photoDurationSeconds = PlaybackSettings.defaultPhotoDurationSeconds
    private var lastPublishedItemID: String?
    private var isInterrupted = false
    private var videoRecoveryAfterInterruption: VideoInterruptionRecovery = .none
    private var isPhotoAutoAdvanceSuspended = false
    private var isCurrentPhotoReady = false
    private var navigationSequence: UInt64 = 0

    public init(
        items: [MediaItem],
        initialItem: MediaItem,
        thumbnailService: (any FamilyMediaAdminServicing)? = nil,
        playbackResolver: any MediaPlaybackResolving = DirectMediaPlaybackResolver(),
        playbackReporter: (any MediaPlaybackReporting)? = nil,
        photoAutoAdvanceScheduler: any DelayedActionScheduling = DelayedActionScheduler()
    ) {
        let session = MediaViewerSession(items: items, initialItem: initialItem)
        self.session = session
        navigationEvent = MediaViewerNavigationEvent(
            sequence: 0,
            itemID: session.currentItem.id,
            index: session.currentIndex,
            origin: .initial
        )
        regenerationStore = ThumbnailRegenerationStore(mediaService: thumbnailService)
        self.photoAutoAdvanceScheduler = photoAutoAdvanceScheduler
        let playbackSession = MediaPlaybackSessionController(
            resolver: playbackResolver,
            reporter: playbackReporter
        )
        self.playbackSession = playbackSession
        playbackSnapshot = playbackSession.snapshot

        playbackSession.$snapshot
            .sink { [weak self] snapshot in
                self?.playbackSnapshot = snapshot
            }
            .store(in: &cancellables)

        regenerationStore.$isWorking
            .sink { [weak self] isWorking in
                self?.isRegeneratingThumbnail = isWorking
            }
            .store(in: &cancellables)

        regenerationStore.$message
            .sink { [weak self] message in
                self?.regenerationMessage = message
            }
            .store(in: &cancellables)
    }

    public convenience init(
        items: [MediaItem],
        initialItem: MediaItem,
        mediaService: any MediaServicing
    ) {
        self.init(items: items, initialItem: initialItem, thumbnailService: mediaService)
    }

    public var currentItem: MediaItem {
        session.currentItem
    }

    public var player: AVPlayer? { playbackSnapshot.player }

    public var isPlaying: Bool { playbackSnapshot.isPlaying }

    public var isMuted: Bool { playbackSnapshot.isMuted }

    public var playbackState: MediaPlaybackState { playbackSnapshot.state }

    public var playbackPositionSeconds: Double {
        playbackSnapshot.timeline.positionSeconds
    }

    public var playbackDurationSeconds: Double {
        playbackSnapshot.timeline.durationSeconds
    }

    public var playbackBufferedSeconds: Double {
        playbackSnapshot.timeline.bufferedSeconds
    }

    public var currentIndex: Int {
        session.currentIndex
    }

    public var canGoPrevious: Bool {
        session.canGoPrevious
    }

    public var canGoNext: Bool {
        session.canGoNext
    }

    public var previousItem: MediaItem? {
        guard canGoPrevious else { return nil }
        return session.items[currentIndex - 1]
    }

    public var nextItem: MediaItem? {
        guard canGoNext else { return nil }
        return session.items[currentIndex + 1]
    }

    public func start(
        autoplayLimit: Int,
        photoDurationSeconds: Int,
        onShouldDismiss: @escaping DismissHandler,
        onCurrentItemChanged: @escaping CurrentItemHandler
    ) {
        isPhotoAutoAdvancePaused = false
        isAwaitingAutoplayContinuation = false
        self.autoplayLimit = PlaybackSettings.normalizedAutoplayLimit(autoplayLimit)
        self.photoDurationSeconds = PlaybackSettings.normalizedPhotoDurationSeconds(photoDurationSeconds)
        self.onShouldDismiss = onShouldDismiss
        self.onCurrentItemChanged = onCurrentItemChanged

        publishNavigation(origin: .initial)
        publishCurrentItem()
        configureCurrentItem(autoplay: true)
    }

    public func stop() {
        photoAutoAdvanceScheduler.cancel()
        playbackSession.stop()
        isInterrupted = false
        videoRecoveryAfterInterruption = .none
        isPhotoAutoAdvanceSuspended = false
        isCurrentPhotoReady = false
        isPhotoAutoAdvancePaused = false
        isAwaitingAutoplayContinuation = false
        onShouldDismiss = nil
        onCurrentItemChanged = nil
    }

    @discardableResult
    public func goPrevious() -> Bool {
        guard canGoPrevious else { return false }
        session.goPreviousManually()
        currentItemDidChange(origin: .manual)
        return true
    }

    @discardableResult
    public func goNext() -> Bool {
        guard canGoNext else { return false }
        session.goNextManually()
        currentItemDidChange(origin: .manual)
        return true
    }

    public func togglePlayback() {
        guard currentItem.kind == .video else { return }
        playbackSession.togglePlayback()
    }

    public func setMuted(_ muted: Bool) {
        playbackSession.setMuted(muted)
    }

    public func toggleMuted() {
        playbackSession.toggleMuted()
    }

    public func togglePhotoAutoAdvance() {
        guard currentItem.kind == .photo else { return }
        isPhotoAutoAdvancePaused.toggle()
        if isPhotoAutoAdvancePaused {
            photoAutoAdvanceScheduler.cancel()
        } else {
            schedulePhotoAutoAdvance()
        }
    }

    public func continueAutoplay() {
        guard isAwaitingAutoplayContinuation else { return }
        isAwaitingAutoplayContinuation = false
        guard session.continueAutoplayAfterLimitIfPossible() else {
            dismissAfterPublishingCurrentItem()
            return
        }
        currentItemDidChange(origin: .automatic)
    }

    public func returnToLibraryAfterAutoplayLimit() {
        guard isAwaitingAutoplayContinuation else { return }
        isAwaitingAutoplayContinuation = false
        dismissAfterPublishingCurrentItem()
    }

    public func retryPlayback() {
        guard currentItem.kind == .video else { return }
        playbackSession.retry(item: currentItem, autoplay: true) { [weak self] in
            self?.currentItemDidFinish()
        }
    }

    public func seek(to seconds: Double) {
        guard currentItem.kind == .video else { return }
        playbackSession.seek(to: seconds)
    }

    public var playbackTimeline: MediaPlaybackTimeline {
        playbackSnapshot.timeline
    }

    public func handleInterruption() {
        guard !isInterrupted else { return }
        isInterrupted = true
        photoAutoAdvanceScheduler.cancel()

        guard currentItem.kind == .video else { return }
        if playbackState == .preparing {
            videoRecoveryAfterInterruption = .prepareFromBeginning
            playbackSession.stop()
        } else {
            playbackSession.suspendForAppInterruption()
        }
    }

    /// Upgrades a short inactive interruption to a true background suspension.
    /// Jellyfin sessions are stopped here so an HLS transcode cannot continue
    /// consuming NAS resources while the app is locked or backgrounded.
    public func handleBackgroundTransition() {
        if !isInterrupted {
            isInterrupted = true
            photoAutoAdvanceScheduler.cancel()
        }

        guard currentItem.kind == .video else { return }
        let wasPreparing = playbackState == .preparing
        guard playbackSession.endForBackground() else { return }
        videoRecoveryAfterInterruption = wasPreparing
            ? .prepareFromBeginning
            : .resumeFromSavedPosition
    }

    public func resumeAfterInterruption() {
        guard isInterrupted else { return }
        isInterrupted = false

        if currentItem.kind == .photo {
            schedulePhotoAutoAdvance()
        } else if videoRecoveryAfterInterruption == .prepareFromBeginning {
            videoRecoveryAfterInterruption = .none
            playbackSession.prepare(item: currentItem, autoplay: false) { [weak self] in
                self?.currentItemDidFinish()
            }
        } else if videoRecoveryAfterInterruption == .resumeFromSavedPosition {
            videoRecoveryAfterInterruption = .none
            playbackSession.retry(item: currentItem, autoplay: false) { [weak self] in
                self?.currentItemDidFinish()
            }
        }
    }

    public func setPhotoAutoAdvanceSuspended(_ isSuspended: Bool) {
        guard currentItem.kind == .photo else { return }
        isPhotoAutoAdvanceSuspended = isSuspended
        if isSuspended {
            photoAutoAdvanceScheduler.cancel()
        } else if !isInterrupted {
            schedulePhotoAutoAdvance()
        }
    }

    /// Starts the slideshow interval after the first viewable photo quality is
    /// visible. A later high-resolution replacement must not restart the timer.
    public func setPhotoReady(_ isReady: Bool) {
        guard currentItem.kind == .photo,
              isCurrentPhotoReady != isReady
        else { return }

        isCurrentPhotoReady = isReady
        if isReady, !isPhotoAutoAdvanceSuspended, !isInterrupted {
            schedulePhotoAutoAdvance()
        } else {
            photoAutoAdvanceScheduler.cancel()
        }
    }

    @discardableResult
    public func regenerateThumbnail() async -> Bool {
        await regenerationStore.regenerateThumbnail(for: currentItem)
    }

    private func currentItemDidChange(origin: MediaViewerNavigationOrigin) {
        isAwaitingAutoplayContinuation = false
        isInterrupted = false
        videoRecoveryAfterInterruption = .none
        isPhotoAutoAdvanceSuspended = false
        isCurrentPhotoReady = false
        publishNavigation(origin: origin)
        publishCurrentItem()
        configureCurrentItem(autoplay: true)
    }

    private func configureCurrentItem(autoplay: Bool) {
        photoAutoAdvanceScheduler.cancel()

        guard session.beginCurrentItemAutoplayIfAllowed(limit: autoplayLimit) else {
            playbackSession.stop()
            dismissAfterPublishingCurrentItem()
            return
        }

        guard currentItem.kind == .video else {
            playbackSession.stop()
            schedulePhotoAutoAdvance()
            return
        }

        playbackSession.prepare(item: currentItem, autoplay: autoplay) { [weak self] in
            self?.currentItemDidFinish()
        }
    }

    func currentItemDidFinish() {
        if session.hasReachedAutoplayLimit(autoplayLimit), session.canGoNext {
            photoAutoAdvanceScheduler.cancel()
            isAwaitingAutoplayContinuation = true
            return
        }

        guard session.advanceAutomaticallyIfPossible() else {
            dismissAfterPublishingCurrentItem()
            return
        }
        currentItemDidChange(origin: .automatic)
    }

    private func schedulePhotoAutoAdvance() {
        guard isCurrentPhotoReady,
              !isPhotoAutoAdvancePaused,
              !isPhotoAutoAdvanceSuspended,
              !isInterrupted
        else { return }
        photoAutoAdvanceScheduler.schedule(afterSeconds: photoDurationSeconds) { [weak self] in
            self?.currentItemDidFinish()
        }
    }

    private func publishCurrentItem() {
        guard lastPublishedItemID != currentItem.id else { return }
        lastPublishedItemID = currentItem.id
        onCurrentItemChanged?(currentItem)
    }

    private func publishNavigation(origin: MediaViewerNavigationOrigin) {
        navigationSequence &+= 1
        navigationEvent = MediaViewerNavigationEvent(
            sequence: navigationSequence,
            itemID: currentItem.id,
            index: currentIndex,
            origin: origin
        )
    }

    private func dismissAfterPublishingCurrentItem() {
        publishCurrentItem()
        onShouldDismiss?()
    }

}

private enum VideoInterruptionRecovery {
    case none
    case prepareFromBeginning
    case resumeFromSavedPosition
}
