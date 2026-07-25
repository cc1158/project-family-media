import Foundation
import Testing
@testable import FamilyMediaCore

@MainActor
struct MediaViewerCoordinatorTests {
    @Test func mutePreferencePersistsAcrossMixedMediaWithinViewerSession() {
        let first = makeMediaItem(id: "video-1", kind: .video)
        let photo = makeMediaItem(id: "photo", kind: .photo)
        let last = makeMediaItem(id: "video-2", kind: .video)
        let coordinator = MediaViewerCoordinator(
            items: [first, photo, last],
            initialItem: first,
            playbackResolver: DelayedPlaybackResolver()
        )

        #expect(!coordinator.isMuted)
        coordinator.setMuted(true)
        #expect(coordinator.isMuted)

        #expect(coordinator.goNext())
        #expect(coordinator.currentItem == photo)
        #expect(coordinator.isMuted)

        #expect(coordinator.goNext())
        #expect(coordinator.currentItem == last)
        #expect(coordinator.isMuted)
        coordinator.stop()
    }

    @Test func startAndManualNavigationPublishCurrentItem() {
        let first = makeMediaItem(id: "first")
        let second = makeMediaItem(id: "second")
        let coordinator = MediaViewerCoordinator(
            items: [first, second],
            initialItem: first,
            mediaService: FakeMediaService()
        )
        var currentIDs: [String] = []
        var didDismiss = false

        coordinator.start(
            autoplayLimit: 20,
            photoDurationSeconds: 60,
            onShouldDismiss: { didDismiss = true },
            onCurrentItemChanged: { currentIDs.append($0.id) }
        )

        let didGoNext = coordinator.goNext()
        let nextEvent = coordinator.navigationEvent
        let didGoPrevious = coordinator.goPrevious()
        let previousEvent = coordinator.navigationEvent

        #expect(didGoNext)
        #expect(didGoPrevious)
        #expect(nextEvent.sequence == 2)
        #expect(nextEvent.itemID == "second")
        #expect(nextEvent.index == 1)
        #expect(nextEvent.origin == .manual)
        #expect(previousEvent.sequence == 3)
        #expect(previousEvent.itemID == "first")
        #expect(previousEvent.index == 0)
        #expect(previousEvent.origin == .manual)
        #expect(currentIDs == ["first", "second", "first"])
        #expect(coordinator.currentItem == first)
        #expect(!didDismiss)
    }

    @Test func regenerateThumbnailUsesCurrentItem() async {
        let item = makeMediaItem(id: "photo-1")
        let service = FakeMediaService()
        let coordinator = MediaViewerCoordinator(
            items: [item],
            initialItem: item,
            mediaService: service
        )

        let didRegenerate = await coordinator.regenerateThumbnail()

        #expect(didRegenerate)
        #expect(service.thumbnailRegenerationRequests.map(\.mediaID) == ["photo-1"])
        #expect(coordinator.regenerationMessage == .success("封面已更新"))
    }

    @Test func reachingAutoplayLimitWaitsForConfirmation() {
        let video = makeMediaItem(id: "video-1", kind: .video)
        let photo = makeMediaItem(id: "photo-1", kind: .photo)
        let next = makeMediaItem(id: "photo-2", kind: .photo)
        let coordinator = MediaViewerCoordinator(
            items: [video, photo, next],
            initialItem: video,
            mediaService: FakeMediaService()
        )
        var currentIDs: [String] = []
        var didDismiss = false

        coordinator.start(
            autoplayLimit: 2,
            photoDurationSeconds: 60,
            onShouldDismiss: { didDismiss = true },
            onCurrentItemChanged: { currentIDs.append($0.id) }
        )

        coordinator.currentItemDidFinish()

        #expect(coordinator.navigationEvent.origin == .automatic)
        #expect(coordinator.navigationEvent.itemID == "photo-1")
        coordinator.currentItemDidFinish()

        #expect(currentIDs == ["video-1", "photo-1"])
        #expect(coordinator.currentItem == photo)
        #expect(!didDismiss)
        #expect(coordinator.isAwaitingAutoplayContinuation)
    }

    @Test func continuingAfterAutoplayLimitAdvancesAndStartsANewWindow() {
        let first = makeMediaItem(id: "first", kind: .photo)
        let second = makeMediaItem(id: "second", kind: .photo)
        let third = makeMediaItem(id: "third", kind: .photo)
        let coordinator = MediaViewerCoordinator(
            items: [first, second, third],
            initialItem: first,
            mediaService: FakeMediaService()
        )
        var currentIDs: [String] = []

        coordinator.start(
            autoplayLimit: 1,
            photoDurationSeconds: 60,
            onShouldDismiss: {},
            onCurrentItemChanged: { currentIDs.append($0.id) }
        )
        coordinator.currentItemDidFinish()

        #expect(coordinator.isAwaitingAutoplayContinuation)
        #expect(coordinator.currentItem == first)

        coordinator.continueAutoplay()

        #expect(!coordinator.isAwaitingAutoplayContinuation)
        #expect(coordinator.navigationEvent.origin == .automatic)
        #expect(coordinator.navigationEvent.itemID == "second")
        #expect(coordinator.currentItem == second)
        #expect(currentIDs == ["first", "second"])

        coordinator.currentItemDidFinish()
        #expect(coordinator.isAwaitingAutoplayContinuation)
        #expect(coordinator.currentItem == second)
    }

    @Test func returningAfterAutoplayLimitDismissesAtCurrentItem() {
        let first = makeMediaItem(id: "first", kind: .photo)
        let second = makeMediaItem(id: "second", kind: .photo)
        let coordinator = MediaViewerCoordinator(
            items: [first, second],
            initialItem: first,
            mediaService: FakeMediaService()
        )
        var publishedID: String?
        var dismissedID: String?

        coordinator.start(
            autoplayLimit: 1,
            photoDurationSeconds: 60,
            onShouldDismiss: { dismissedID = publishedID },
            onCurrentItemChanged: { publishedID = $0.id }
        )
        coordinator.currentItemDidFinish()
        coordinator.returnToLibraryAfterAutoplayLimit()

        #expect(dismissedID == "first")
        #expect(coordinator.currentItem == first)
        #expect(!coordinator.isAwaitingAutoplayContinuation)
    }

    @Test func dismissAtEndPublishesCurrentItemBeforeClosing() {
        let first = makeMediaItem(id: "first", kind: .video)
        let second = makeMediaItem(id: "second", kind: .video)
        let coordinator = MediaViewerCoordinator(
            items: [first, second],
            initialItem: first,
            mediaService: FakeMediaService()
        )
        var lastCurrentID: String?
        var dismissedCurrentID: String?

        coordinator.start(
            autoplayLimit: 20,
            photoDurationSeconds: 60,
            onShouldDismiss: { dismissedCurrentID = lastCurrentID },
            onCurrentItemChanged: { lastCurrentID = $0.id }
        )

        coordinator.currentItemDidFinish()
        coordinator.currentItemDidFinish()

        #expect(lastCurrentID == "second")
        #expect(dismissedCurrentID == "second")
    }

    @Test func manualNavigationResetsAutoplayLimit() {
        let first = makeMediaItem(id: "first", kind: .video)
        let second = makeMediaItem(id: "second", kind: .video)
        let coordinator = MediaViewerCoordinator(
            items: [first, second],
            initialItem: first,
            mediaService: FakeMediaService()
        )
        var didDismiss = false

        coordinator.start(
            autoplayLimit: 1,
            photoDurationSeconds: 60,
            onShouldDismiss: { didDismiss = true },
            onCurrentItemChanged: { _ in }
        )

        let didGoNext = coordinator.goNext()

        #expect(didGoNext)
        #expect(coordinator.currentItem == second)
        #expect(!didDismiss)
    }

    @Test func switchingVideoCancelsPreviousPlaybackResolution() async throws {
        let first = makeMediaItem(id: "first", kind: .video)
        let second = makeMediaItem(id: "second", kind: .video)
        let resolver = DelayedPlaybackResolver()
        let coordinator = MediaViewerCoordinator(
            items: [first, second],
            initialItem: first,
            playbackResolver: resolver
        )

        coordinator.start(
            autoplayLimit: 20,
            photoDurationSeconds: 60,
            onShouldDismiss: {},
            onCurrentItemChanged: { _ in }
        )
        #expect(coordinator.playbackState == .preparing)
        #expect(coordinator.goNext())

        try await waitUntil {
            coordinator.currentItem == second && coordinator.playbackState != .preparing
        }

        #expect(coordinator.currentItem == second)
        #expect(coordinator.playbackState != .preparing)
        coordinator.stop()
    }

    @Test func failedPlaybackCanBeRetriedWithoutChangingCurrentItem() async throws {
        let item = makeMediaItem(id: "retry-video", kind: .video)
        let resolver = CountingFailingPlaybackResolver()
        let coordinator = MediaViewerCoordinator(
            items: [item],
            initialItem: item,
            playbackResolver: resolver
        )

        coordinator.start(
            autoplayLimit: 20,
            photoDurationSeconds: 60,
            onShouldDismiss: {},
            onCurrentItemChanged: { _ in }
        )
        try await waitUntil {
            await resolver.requestCount == 1 && coordinator.playbackState == .failed(
                MediaPlaybackFailure(message: "模拟播放失败", recovery: .retry)
            )
        }

        coordinator.retryPlayback()
        try await waitUntil {
            await resolver.requestCount == 2 && coordinator.playbackState == .failed(
                MediaPlaybackFailure(message: "模拟播放失败", recovery: .retry)
            )
        }

        let secondRequestCount = await resolver.requestCount
        #expect(secondRequestCount == 2)
        #expect(coordinator.currentItem == item)
        #expect(
            coordinator.playbackState == .failed(
                MediaPlaybackFailure(message: "模拟播放失败", recovery: .retry)
            )
        )
        coordinator.stop()
    }

    @Test func interruptionCancelsPreparationAndResumesWithoutAutoplayNavigation() async throws {
        let item = makeMediaItem(id: "interrupted-video", kind: .video)
        let resolver = InterruptibleCountingPlaybackResolver()
        let coordinator = MediaViewerCoordinator(
            items: [item],
            initialItem: item,
            playbackResolver: resolver
        )

        coordinator.start(
            autoplayLimit: 20,
            photoDurationSeconds: 60,
            onShouldDismiss: {},
            onCurrentItemChanged: { _ in }
        )
        try await waitUntil { await resolver.requestCount == 1 }

        coordinator.handleInterruption()
        #expect(coordinator.playbackState == .idle)

        coordinator.resumeAfterInterruption()
        try await waitUntil { await resolver.requestCount == 2 }

        let requestCount = await resolver.requestCount
        #expect(requestCount == 2)
        #expect(coordinator.currentItem == item)
        #expect(coordinator.playbackState == .preparing)
        coordinator.stop()
    }

    @Test func backgroundUpgradesPausedInterruptionAndRequestsFreshPlaybackURL() async throws {
        let item = makeMediaItem(id: "background-video", kind: .video)
        let resolver = ImmediateCountingPlaybackResolver()
        let coordinator = MediaViewerCoordinator(
            items: [item],
            initialItem: item,
            playbackResolver: resolver
        )

        coordinator.start(
            autoplayLimit: 20,
            photoDurationSeconds: 60,
            onShouldDismiss: {},
            onCurrentItemChanged: { _ in }
        )
        try await waitUntil { await resolver.requestCount == 1 && coordinator.player != nil }

        coordinator.handleInterruption()
        coordinator.handleBackgroundTransition()
        #expect(coordinator.player == nil)
        #expect(coordinator.playbackState == .paused(.transcode))

        coordinator.resumeAfterInterruption()
        try await waitUntil { await resolver.requestCount == 2 && coordinator.player != nil }

        #expect(coordinator.currentItem == item)
        #expect(coordinator.player != nil)
        #expect(!coordinator.isPlaying)
        if case .failed = coordinator.playbackState {
            Issue.record("回到前台后应使用新 URL 恢复为暂停状态")
        }
        coordinator.stop()
    }

    @Test func temporaryPhotoSuspensionStopsAutoAdvanceUntilItEnds() {
        let first = makeMediaItem(id: "photo-1")
        let second = makeMediaItem(id: "photo-2")
        let scheduler = ManualDelayedActionScheduler()
        let coordinator = MediaViewerCoordinator(
            items: [first, second],
            initialItem: first,
            photoAutoAdvanceScheduler: scheduler
        )

        coordinator.start(
            autoplayLimit: 20,
            photoDurationSeconds: 5,
            onShouldDismiss: {},
            onCurrentItemChanged: { _ in }
        )
        #expect(!scheduler.hasPendingAction)

        coordinator.setPhotoReady(true)
        #expect(scheduler.hasPendingAction)

        coordinator.setPhotoAutoAdvanceSuspended(true)
        #expect(!scheduler.hasPendingAction)
        scheduler.fire()
        #expect(coordinator.currentItem == first)

        coordinator.setPhotoAutoAdvanceSuspended(false)
        #expect(scheduler.hasPendingAction)
        scheduler.fire()
        #expect(coordinator.currentItem == second)
        #expect(!scheduler.hasPendingAction)
        coordinator.stop()
    }

    @Test func photoAutoAdvanceWaitsForSuccessfulLoadAndStopsAfterFailure() {
        let first = makeMediaItem(id: "photo-1")
        let second = makeMediaItem(id: "photo-2")
        let scheduler = ManualDelayedActionScheduler()
        let coordinator = MediaViewerCoordinator(
            items: [first, second],
            initialItem: first,
            photoAutoAdvanceScheduler: scheduler
        )

        coordinator.start(
            autoplayLimit: 20,
            photoDurationSeconds: 5,
            onShouldDismiss: {},
            onCurrentItemChanged: { _ in }
        )

        scheduler.fire()
        #expect(coordinator.currentItem == first)

        coordinator.setPhotoReady(true)
        #expect(scheduler.hasPendingAction)
        coordinator.setPhotoReady(false)
        #expect(!scheduler.hasPendingAction)
        scheduler.fire()
        #expect(coordinator.currentItem == first)

        coordinator.setPhotoReady(true)
        scheduler.fire()
        #expect(coordinator.currentItem == second)
        #expect(!scheduler.hasPendingAction)
        coordinator.stop()
    }

    @Test func pausingPhotoAutoAdvanceCancelsAndResumeRestartsTheFullInterval() {
        let first = makeMediaItem(id: "photo-1")
        let second = makeMediaItem(id: "photo-2")
        let scheduler = ManualDelayedActionScheduler()
        let coordinator = MediaViewerCoordinator(
            items: [first, second],
            initialItem: first,
            photoAutoAdvanceScheduler: scheduler
        )

        coordinator.start(
            autoplayLimit: 20,
            photoDurationSeconds: 5,
            onShouldDismiss: {},
            onCurrentItemChanged: { _ in }
        )
        coordinator.setPhotoReady(true)
        #expect(scheduler.hasPendingAction)

        coordinator.togglePhotoAutoAdvance()
        #expect(coordinator.isPhotoAutoAdvancePaused)
        #expect(!scheduler.hasPendingAction)
        scheduler.fire()
        #expect(coordinator.currentItem == first)

        coordinator.togglePhotoAutoAdvance()
        #expect(!coordinator.isPhotoAutoAdvancePaused)
        #expect(scheduler.hasPendingAction)
        scheduler.fire()
        #expect(coordinator.currentItem == second)
        coordinator.stop()
    }

    @Test func photoPausePersistsAcrossManualNavigationAndInterruption() {
        let first = makeMediaItem(id: "photo-1")
        let video = makeMediaItem(id: "video", kind: .video)
        let last = makeMediaItem(id: "photo-2")
        let scheduler = ManualDelayedActionScheduler()
        let coordinator = MediaViewerCoordinator(
            items: [first, video, last],
            initialItem: first,
            photoAutoAdvanceScheduler: scheduler
        )

        coordinator.start(
            autoplayLimit: 20,
            photoDurationSeconds: 5,
            onShouldDismiss: {},
            onCurrentItemChanged: { _ in }
        )
        coordinator.setPhotoReady(true)
        coordinator.togglePhotoAutoAdvance()
        #expect(coordinator.isPhotoAutoAdvancePaused)

        #expect(coordinator.goNext())
        #expect(coordinator.goNext())
        coordinator.setPhotoReady(true)
        coordinator.handleInterruption()
        coordinator.resumeAfterInterruption()

        #expect(coordinator.currentItem == last)
        #expect(coordinator.isPhotoAutoAdvancePaused)
        #expect(!scheduler.hasPendingAction)
        coordinator.stop()
        #expect(!coordinator.isPhotoAutoAdvancePaused)
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
        Issue.record("等待播放生命周期事件超时")
    }
}

private struct DelayedPlaybackResolver: MediaPlaybackResolving {
    func resolvePlayback(for item: MediaItem) async throws -> MediaPlaybackResolution {
        try await Task.sleep(for: item.id == "first" ? .milliseconds(200) : .milliseconds(10))
        return MediaPlaybackResolution(url: item.url, method: .directPlay)
    }
}

private actor CountingFailingPlaybackResolver: MediaPlaybackResolving {
    private(set) var requestCount = 0

    func resolvePlayback(for item: MediaItem) async throws -> MediaPlaybackResolution {
        requestCount += 1
        throw RetryTestError()
    }
}

private actor InterruptibleCountingPlaybackResolver: MediaPlaybackResolving {
    private(set) var requestCount = 0

    func resolvePlayback(for item: MediaItem) async throws -> MediaPlaybackResolution {
        requestCount += 1
        try await Task.sleep(for: .seconds(1))
        return MediaPlaybackResolution(url: item.url, method: .directPlay)
    }
}

private actor ImmediateCountingPlaybackResolver: MediaPlaybackResolving {
    private(set) var requestCount = 0

    func resolvePlayback(for item: MediaItem) async throws -> MediaPlaybackResolution {
        requestCount += 1
        return MediaPlaybackResolution(
            url: URL(string: "https://media.example.invalid/\(item.id).m3u8")!,
            method: .transcode,
            playSessionID: "session-\(requestCount)",
            mediaSourceID: item.id
        )
    }
}


private struct RetryTestError: LocalizedError {
    var errorDescription: String? { "模拟播放失败" }
}

@MainActor
private final class ManualDelayedActionScheduler: DelayedActionScheduling {
    private var action: (@MainActor () -> Void)?

    var hasPendingAction: Bool { action != nil }

    func schedule(afterSeconds seconds: Int, action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    func cancel() {
        action = nil
    }

    func fire() {
        let pendingAction = action
        action = nil
        pendingAction?()
    }
}
