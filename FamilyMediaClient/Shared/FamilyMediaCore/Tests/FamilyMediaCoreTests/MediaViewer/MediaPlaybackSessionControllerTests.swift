import Foundation
import Testing
@testable import FamilyMediaCore

@MainActor
struct MediaPlaybackSessionControllerTests {
    @Test func activityReportingIgnoresBufferingAndDeduplicatesStableStates() {
        var state = MediaPlaybackActivityReportState()
        state.begin(isPaused: false)

        #expect(state.transition(to: .waiting) == nil)
        #expect(state.transition(to: .playing) == nil)
        #expect(state.transition(to: .paused) == true)
        #expect(state.transition(to: .paused) == nil)
        #expect(state.transition(to: .waiting) == nil)
        #expect(state.transition(to: .playing) == false)
        #expect(state.transition(to: .playing) == nil)

        state.reset()
        #expect(state.transition(to: .paused) == true)
    }

    @Test func snapshotIsTheSingleConsistentPublishedPlaybackView() async throws {
        let item = makeMediaItem(id: "snapshot", kind: .video)
        let resolution = MediaPlaybackResolution(
            url: URL(fileURLWithPath: "/nonexistent/snapshot.mp4"),
            method: .directPlay
        )
        let controller = MediaPlaybackSessionController(
            resolver: ImmediatePlaybackResolver(resolution: resolution)
        )

        controller.prepare(item: item, autoplay: false, onPlaybackEnded: {})
        try await waitUntil { controller.snapshot.player != nil }
        controller.setMuted(true)
        controller.playerActivityDidChange(.playing)

        #expect(controller.snapshot.player === controller.player)
        #expect(controller.snapshot.state == .playing(.directPlay))
        #expect(controller.snapshot.isPlaying)
        #expect(controller.snapshot.isMuted)
        #expect(controller.isPlaying)

        controller.stop()
        #expect(controller.snapshot.state == .idle)
        #expect(controller.snapshot.player == nil)
    }

    @Test func stoppingResolvedPlaybackBeforeReadyReportsStopExactlyOnce() async throws {
        let item = makeMediaItem(id: "early-stop", kind: .video)
        let reporter = EarlyStopPlaybackReporter()
        let resolution = MediaPlaybackResolution(
            url: URL(fileURLWithPath: "/nonexistent/early-stop.mp4"),
            method: .transcode,
            playSessionID: "play-session",
            mediaSourceID: "media-source"
        )
        let controller = MediaPlaybackSessionController(
            resolver: ImmediatePlaybackResolver(resolution: resolution),
            reporter: reporter
        )

        controller.prepare(item: item, autoplay: false, onPlaybackEnded: {})
        try await waitUntil { controller.player != nil }

        controller.stop()
        controller.stop()
        try await waitUntil { await reporter.stoppedCount == 1 }

        let startedCount = await reporter.startedCount
        let stoppedCount = await reporter.stoppedCount
        let stoppedSessionID = await reporter.lastStoppedSessionID
        #expect(startedCount == 0)
        #expect(stoppedCount == 1)
        #expect(stoppedSessionID == "play-session")
        #expect(controller.player == nil)
        #expect(controller.state == .idle)
    }

    @Test func preparingReplacementStopsPreviousSessionExactlyOnce() async throws {
        let first = makeMediaItem(id: "first", kind: .video)
        let second = makeMediaItem(id: "second", kind: .video)
        let reporter = EarlyStopPlaybackReporter()
        let controller = MediaPlaybackSessionController(
            resolver: ItemPlaybackResolver(),
            reporter: reporter
        )

        controller.prepare(item: first, autoplay: false, onPlaybackEnded: {})
        try await waitUntil { controller.player != nil }

        controller.prepare(item: second, autoplay: false, onPlaybackEnded: {})
        try await waitUntil {
            let stoppedSessionIDs = await reporter.stoppedSessionIDs
            return controller.player != nil && stoppedSessionIDs == ["session-first"]
        }

        controller.stop()
        try await waitUntil {
            await reporter.stoppedSessionIDs == ["session-first", "session-second"]
        }
    }

    @Test func prolongedBufferingBecomesRetryableFailureAndStopsSessionOnce() async throws {
        let item = makeMediaItem(id: "stalled", kind: .video)
        let reporter = EarlyStopPlaybackReporter()
        let scheduler = SessionTestScheduler()
        let resolution = MediaPlaybackResolution(
            url: URL(string: "https://media.example.invalid/stalled.m3u8")!,
            method: .transcode,
            playSessionID: "stalled-session",
            mediaSourceID: "stalled-source"
        )
        let controller = MediaPlaybackSessionController(
            resolver: ImmediatePlaybackResolver(resolution: resolution),
            reporter: reporter,
            bufferingTimeoutScheduler: scheduler
        )

        controller.prepare(item: item, autoplay: false, onPlaybackEnded: {})
        try await waitUntil { controller.player != nil }
        controller.playerActivityDidChange(.waiting)

        #expect(scheduler.scheduledSeconds == MediaBufferingWatchdog.defaultTimeoutSeconds)
        scheduler.fire()

        guard case .failed(let failure) = controller.state else {
            Issue.record("长时间缓冲应进入失败状态")
            return
        }
        #expect(failure.recovery == .retry)
        #expect(failure.message.contains("缓冲等待时间过长"))
        #expect(controller.player == nil)
        try await waitUntil { await reporter.stoppedCount == 1 }
        let stoppedCount = await reporter.stoppedCount
        #expect(stoppedCount == 1)

        controller.stop()
    }

    @Test func backgroundingStopsServerSessionAndRetainsResumePosition() async throws {
        let item = makeMediaItem(id: "backgrounded", kind: .video)
        let reporter = EarlyStopPlaybackReporter()
        let resolution = MediaPlaybackResolution(
            url: URL(string: "https://media.example.invalid/backgrounded.m3u8")!,
            method: .transcode,
            playSessionID: "background-session",
            mediaSourceID: "background-source"
        )
        let controller = MediaPlaybackSessionController(
            resolver: ImmediatePlaybackResolver(resolution: resolution),
            reporter: reporter
        )

        controller.prepare(item: item, autoplay: false, onPlaybackEnded: {})
        try await waitUntil { controller.player != nil }
        controller.seek(to: 42)

        #expect(controller.endForBackground())
        #expect(controller.player == nil)
        #expect(controller.positionSeconds == 42)
        #expect(controller.state == .paused(.transcode))
        try await waitUntil { await reporter.stoppedCount == 1 }
        #expect(await reporter.lastStoppedPositionTicks == 420_000_000)

        #expect(!controller.endForBackground())
        controller.stop()
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

@MainActor
private final class SessionTestScheduler: DelayedActionScheduling {
    private var action: (@MainActor () -> Void)?
    private(set) var scheduledSeconds: Int?

    func schedule(afterSeconds seconds: Int, action: @escaping @MainActor () -> Void) {
        self.scheduledSeconds = seconds
        self.action = action
    }

    func cancel() {
        action = nil
    }

    func fire() {
        let pending = action
        action = nil
        pending?()
    }
}

private struct ImmediatePlaybackResolver: MediaPlaybackResolving {
    let resolution: MediaPlaybackResolution

    func resolvePlayback(for item: MediaItem) async throws -> MediaPlaybackResolution {
        resolution
    }
}

private struct ItemPlaybackResolver: MediaPlaybackResolving {
    func resolvePlayback(for item: MediaItem) async throws -> MediaPlaybackResolution {
        MediaPlaybackResolution(
            url: URL(fileURLWithPath: "/nonexistent/\(item.id).mp4"),
            method: .transcode,
            playSessionID: "session-\(item.id)",
            mediaSourceID: "source-\(item.id)"
        )
    }
}

private actor EarlyStopPlaybackReporter: MediaPlaybackReporting {
    private(set) var startedCount = 0
    private(set) var stoppedCount = 0
    private(set) var stoppedSessionIDs: [String] = []
    private(set) var lastStoppedSessionID: String?
    private(set) var lastStoppedPositionTicks: Int64?

    func reportPlaybackStarted(item: MediaItem, resolution: MediaPlaybackResolution) async {
        startedCount += 1
    }

    func reportPlaybackProgress(
        item: MediaItem,
        resolution: MediaPlaybackResolution,
        positionTicks: Int64,
        isPaused: Bool
    ) async {}

    func reportPlaybackStopped(
        item: MediaItem,
        resolution: MediaPlaybackResolution,
        positionTicks: Int64
    ) async {
        stoppedCount += 1
        if let playSessionID = resolution.playSessionID {
            stoppedSessionIDs.append(playSessionID)
        }
        lastStoppedSessionID = resolution.playSessionID
        lastStoppedPositionTicks = positionTicks
    }
}
