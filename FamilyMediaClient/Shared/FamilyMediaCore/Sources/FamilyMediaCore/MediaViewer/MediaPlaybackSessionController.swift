import AVKit
import Combine
import Foundation

@MainActor
public final class MediaPlaybackSessionController: ObservableObject {
    public private(set) var player: AVPlayer? { didSet { publishSnapshot() } }
    public private(set) var isMuted = false { didSet { publishSnapshot() } }
    public private(set) var state: MediaPlaybackState = .idle { didSet { publishSnapshot() } }
    public private(set) var positionSeconds: Double = 0 { didSet { publishSnapshot() } }
    public private(set) var durationSeconds: Double = 0 { didSet { publishSnapshot() } }
    public private(set) var bufferedSeconds: Double = 0 { didSet { publishSnapshot() } }
    @Published public private(set) var snapshot = MediaPlaybackSnapshot()

    public var isPlaying: Bool { snapshot.isPlaying }

    private let playbackController: MediaPlaybackController
    private let resolver: any MediaPlaybackResolving
    private let reporter: (any MediaPlaybackReporting)?
    private let eventLogger: any ClientEventLogging
    private let reportSequencer = MediaPlaybackReportSequencer()
    private let bufferingWatchdog: MediaBufferingWatchdog
    private var cancellables: Set<AnyCancellable> = []
    private var preparationTask: Task<Void, Never>?
    private var activeItem: MediaItem?
    private var activeResolution: MediaPlaybackResolution?
    private var lastPositionTicks: Int64 = 0
    private var didReportStart = false
    private var didReportStop = false
    private var didApplyInitialPosition = false
    private var retryContext = MediaPlaybackRetryContext()
    private var activeOperationID: UUID?
    private var lastLoggedActivity: MediaPlayerActivity?
    private var activityReportState = MediaPlaybackActivityReportState()

    public init(
        resolver: any MediaPlaybackResolving = DirectMediaPlaybackResolver(),
        reporter: (any MediaPlaybackReporting)? = nil,
        playbackController: MediaPlaybackController = MediaPlaybackController(),
        bufferingTimeoutScheduler: any DelayedActionScheduling = DelayedActionScheduler(),
        eventLogger: any ClientEventLogging = ClientEventLog.shared
    ) {
        self.resolver = resolver
        self.reporter = reporter
        self.playbackController = playbackController
        self.eventLogger = eventLogger
        bufferingWatchdog = MediaBufferingWatchdog(
            scheduler: bufferingTimeoutScheduler
        )

        playbackController.$player
            .sink { [weak self] in self?.player = $0 }
            .store(in: &cancellables)
        playbackController.$isMuted
            .sink { [weak self] in self?.isMuted = $0 }
            .store(in: &cancellables)

        playbackController.$activity
            .sink { [weak self] in self?.playerActivityDidChange($0) }
            .store(in: &cancellables)

        playbackController.$positionSeconds
            .sink { [weak self] seconds in
                self?.positionSeconds = seconds
                self?.lastPositionTicks = Int64(max(0, seconds) * 10_000_000)
            }
            .store(in: &cancellables)

        playbackController.$durationSeconds
            .sink { [weak self] in self?.durationSeconds = $0 }
            .store(in: &cancellables)

        playbackController.$bufferedSeconds
            .sink { [weak self] in self?.bufferedSeconds = $0 }
            .store(in: &cancellables)

    }

    public func prepare(
        item: MediaItem,
        autoplay: Bool,
        onPlaybackEnded: @escaping @MainActor () -> Void
    ) {
        retryContext.reset()
        beginPreparation(
            item: item,
            autoplay: autoplay,
            resumePositionSeconds: 0,
            onPlaybackEnded: onPlaybackEnded
        )
    }

    public func retry(
        item: MediaItem,
        autoplay: Bool,
        onPlaybackEnded: @escaping @MainActor () -> Void
    ) {
        beginPreparation(
            item: item,
            autoplay: autoplay,
            resumePositionSeconds: retryContext.resumePositionSeconds,
            onPlaybackEnded: onPlaybackEnded
        )
    }

    private func beginPreparation(
        item: MediaItem,
        autoplay: Bool,
        resumePositionSeconds: Double,
        onPlaybackEnded: @escaping @MainActor () -> Void
    ) {
        resetForPreparation(resumePositionSeconds: resumePositionSeconds)
        let operationID = UUID()
        activeOperationID = operationID
        eventLogger.record(
            category: .playback,
            code: "playback.prepare",
            operationID: operationID,
            outcome: .started,
            sourceID: item.sourceID
        )
        preparationTask = Task { [weak self] in
            await self?.resolveAndConfigurePlayback(
                item: item,
                autoplay: autoplay,
                resumePositionSeconds: resumePositionSeconds,
                operationID: operationID,
                onPlaybackEnded: onPlaybackEnded
            )
        }
    }

    private func resetForPreparation(resumePositionSeconds: Double) {
        preparationTask?.cancel()
        preparationTask = nil
        stopActivePlayback()
        playbackController.clear()
        didApplyInitialPosition = false
        if resumePositionSeconds > 0 {
            positionSeconds = resumePositionSeconds
            durationSeconds = retryContext.durationSeconds
            lastPositionTicks = Int64(resumePositionSeconds * 10_000_000)
        }
        state = .preparing
    }

    private func resolveAndConfigurePlayback(
        item: MediaItem,
        autoplay: Bool,
        resumePositionSeconds: Double,
        operationID: UUID,
        onPlaybackEnded: @escaping @MainActor () -> Void
    ) async {
        do {
            let resolution = try await resolver.resolvePlayback(for: item)
            try Task.checkCancellation()
            configureResolvedPlayback(
                item: item,
                resolution: resolution,
                autoplay: autoplay,
                resumePositionSeconds: resumePositionSeconds,
                onPlaybackEnded: onPlaybackEnded
            )
            eventLogger.record(
                category: .playback,
                code: "playback.prepare",
                operationID: operationID,
                outcome: .succeeded,
                sourceID: item.sourceID,
                playbackMethod: resolution.method
            )
        } catch is CancellationError {
            eventLogger.record(
                category: .playback,
                code: "playback.prepare",
                operationID: operationID,
                outcome: .cancelled,
                sourceID: item.sourceID
            )
            return
        } catch {
            guard !Task.isCancelled else {
                eventLogger.record(
                    category: .playback,
                    code: "playback.prepare",
                    operationID: operationID,
                    outcome: .cancelled,
                    sourceID: item.sourceID
                )
                return
            }
            state = .failed(MediaPlaybackFailure(error: error))
            eventLogger.record(
                category: .playback,
                code: "playback.prepare",
                operationID: operationID,
                outcome: .failed,
                sourceID: item.sourceID
            )
        }
    }

    private func configureResolvedPlayback(
        item: MediaItem,
        resolution: MediaPlaybackResolution,
        autoplay: Bool,
        resumePositionSeconds: Double,
        onPlaybackEnded: @escaping @MainActor () -> Void
    ) {
        activeItem = item
        activeResolution = resolution
        didReportStart = false
        didReportStop = false
        state = .buffering(resolution.method)
        playbackController.configureVideo(
            url: resolution.url,
            autoplay: autoplay && resumePositionSeconds == 0,
            onPlaybackEnded: { [weak self] in
                self?.stopActivePlayback()
                onPlaybackEnded()
            },
            onReady: { [weak self] in
                self?.didBecomeReady(
                    resumePositionSeconds: resumePositionSeconds,
                    autoplay: autoplay
                )
            },
            onFailure: { [weak self] error in
                self?.playbackDidFail(error)
            },
            onProgress: { [weak self] ticks in self?.reportProgress(ticks: ticks) },
            onTimeJumped: { [weak self] ticks in self?.timeJumpDidOccur(ticks: ticks) }
        )
    }

    public func togglePlayback() {
        guard activeResolution != nil else { return }
        playbackController.togglePlayback()
    }

    public func setMuted(_ muted: Bool) {
        playbackController.setMuted(muted)
    }

    public func toggleMuted() {
        playbackController.toggleMuted()
    }

    public func pause() {
        guard activeResolution != nil else { return }
        playbackController.pause()
    }

    public func suspendForAppInterruption() {
        guard let method = activeResolution?.method else { return }
        playbackController.pauseAndDeactivateAudioSession()
        state = .paused(method)
    }

    /// Ends the active server playback session when the app enters the real
    /// background while retaining enough local state to request a fresh URL and
    /// continue near the previous position after returning.
    @discardableResult
    public func endForBackground() -> Bool {
        bufferingWatchdog.cancel()

        if state == .preparing {
            preparationTask?.cancel()
            preparationTask = nil
            playbackController.clear()
            state = .idle
            return true
        }

        guard let method = activeResolution?.method else { return false }
        retryContext.capture(
            positionSeconds: positionSeconds,
            durationSeconds: durationSeconds
        )
        let retainedPosition = retryContext.interruptedPositionSeconds
        let retainedDuration = retryContext.durationSeconds

        preparationTask?.cancel()
        preparationTask = nil
        stopActivePlayback()
        playbackController.clear()
        positionSeconds = retainedPosition
        durationSeconds = retainedDuration
        bufferedSeconds = 0
        lastPositionTicks = Int64(retainedPosition * 10_000_000)
        didApplyInitialPosition = false
        state = .paused(method)
        return true
    }

    public func seek(to seconds: Double) {
        guard activeResolution != nil else { return }
        let target = min(max(0, seconds), durationSeconds > 0 ? durationSeconds : seconds)
        lastPositionTicks = Int64(target * 10_000_000)
        playbackController.seek(to: target) { [weak self] finished in
            guard let self, finished else { return }
            reportProgress(isPaused: !playbackController.isPlaying)
        }
    }

    public func stop() {
        bufferingWatchdog.cancel()
        preparationTask?.cancel()
        preparationTask = nil
        stopActivePlayback()
        playbackController.clear()
        retryContext.reset()
        didApplyInitialPosition = false
        state = .idle
    }

    private func didBecomeReady(
        resumePositionSeconds: Double,
        autoplay: Bool
    ) {
        guard let item = activeItem, let resolution = activeResolution else { return }
        if resumePositionSeconds > 0, !didApplyInitialPosition {
            didApplyInitialPosition = true
            playbackController.seek(to: resumePositionSeconds) { [weak self] finished in
                guard let self,
                      activeItem?.id == item.id,
                      activeResolution == resolution
                else { return }
                if autoplay {
                    playbackController.play()
                }
                finishBecomingReady(
                    item: item,
                    resolution: resolution,
                    initialPositionSeconds: finished ? resumePositionSeconds : 0
                )
            }
            return
        }
        guard !didApplyInitialPosition else { return }
        didApplyInitialPosition = true
        finishBecomingReady(
            item: item,
            resolution: resolution,
            initialPositionSeconds: 0
        )
    }

    private func finishBecomingReady(
        item: MediaItem,
        resolution: MediaPlaybackResolution,
        initialPositionSeconds: Double
    ) {
        updateState(for: playbackController.activity, method: resolution.method)
        if !didReportStart, let reporter {
            didReportStart = true
            lastPositionTicks = Int64(max(0, initialPositionSeconds) * 10_000_000)
            activityReportState.begin(isPaused: !playbackController.isPlaying)
            reportSequencer.enqueueLifecycle {
                await reporter.reportPlaybackStarted(item: item, resolution: resolution)
            }
            if initialPositionSeconds > 0 {
                reportProgress(isPaused: !playbackController.isPlaying)
            }
        }
        retryContext.reset()
    }

    private func reportProgress(ticks: Int64) {
        lastPositionTicks = ticks
        reportProgress(isPaused: !playbackController.isPlaying)
    }

    private func timeJumpDidOccur(ticks: Int64) {
        lastPositionTicks = ticks
        reportProgress(isPaused: !playbackController.isPlaying)
    }

    private func reportProgress(isPaused: Bool) {
        guard didReportStart,
              let reporter,
              let item = activeItem,
              let resolution = activeResolution
        else { return }
        let ticks = lastPositionTicks
        reportSequencer.enqueueProgress {
            await reporter.reportPlaybackProgress(
                item: item,
                resolution: resolution,
                positionTicks: ticks,
                isPaused: isPaused
            )
        }
    }

    private func stopActivePlayback() {
        if let operationID = activeOperationID,
           let item = activeItem,
           let resolution = activeResolution {
            eventLogger.record(
                category: .playback,
                code: "playback.stop",
                operationID: operationID,
                outcome: .info,
                sourceID: item.sourceID,
                playbackMethod: resolution.method
            )
        }
        guard !didReportStop,
              let reporter,
              let item = activeItem,
              let resolution = activeResolution
        else {
            clearActivePlayback()
            return
        }
        didReportStop = true
        let ticks = lastPositionTicks
        reportSequencer.enqueueStop {
            await reporter.reportPlaybackStopped(
                item: item,
                resolution: resolution,
                positionTicks: ticks
            )
        }
        clearActivePlayback()
    }

    private func playbackDidFail(_ error: Error?) {
        playbackDidFail(
            MediaPlaybackFailure(playbackError: error)
        )
    }

    private func playbackDidFail(_ failure: MediaPlaybackFailure) {
        bufferingWatchdog.cancel()
        retryContext.capture(
            positionSeconds: positionSeconds,
            durationSeconds: durationSeconds
        )
        if let operationID = activeOperationID, let item = activeItem {
            eventLogger.record(
                category: .playback,
                code: "playback.runtime",
                operationID: operationID,
                outcome: .failed,
                sourceID: item.sourceID,
                playbackMethod: activeResolution?.method
            )
        }
        state = .failed(failure)
        stopActivePlayback()
        playbackController.clear()
        positionSeconds = retryContext.interruptedPositionSeconds
        durationSeconds = retryContext.durationSeconds
        lastPositionTicks = Int64(positionSeconds * 10_000_000)
    }

    private func clearActivePlayback() {
        activeItem = nil
        activeResolution = nil
        lastPositionTicks = 0
        didReportStart = false
        activeOperationID = nil
        lastLoggedActivity = nil
        activityReportState.reset()
    }

    func playerActivityDidChange(_ activity: MediaPlayerActivity) {
        bufferingWatchdog.update(activity: activity) { [weak self] in
            self?.bufferingDidTimeout()
        }
        guard let method = activeResolution?.method else { return }
        logActivityIfNeeded(activity, method: method)
        updateState(for: activity, method: method)
        reportActivityTransitionIfNeeded(activity)
    }

    private func reportActivityTransitionIfNeeded(_ activity: MediaPlayerActivity) {
        guard didReportStart,
              let isPaused = activityReportState.transition(to: activity)
        else { return }
        reportProgress(isPaused: isPaused)
    }

    private func logActivityIfNeeded(
        _ activity: MediaPlayerActivity,
        method: MediaPlaybackMethod
    ) {
        guard
            activity != lastLoggedActivity,
            let operationID = activeOperationID,
            let sourceID = activeItem?.sourceID
        else { return }
        lastLoggedActivity = activity
        let code: String
        switch activity {
        case .idle: code = "playback.activity.idle"
        case .paused: code = "playback.activity.paused"
        case .waiting: code = "playback.activity.waiting"
        case .playing: code = "playback.activity.playing"
        }
        eventLogger.record(
            category: .playback,
            code: code,
            operationID: operationID,
            outcome: .info,
            sourceID: sourceID,
            playbackMethod: method
        )
    }

    private func bufferingDidTimeout() {
        guard activeResolution != nil else { return }
        playbackDidFail(
            MediaPlaybackFailure(
                message: "缓冲等待时间过长，请确认 NAS 和家庭网络正常后重新尝试。",
                recovery: .retry
            )
        )
    }

    private func updateState(for activity: MediaPlayerActivity, method: MediaPlaybackMethod) {
        switch activity {
        case .idle:
            break
        case .paused:
            state = .paused(method)
        case .waiting:
            state = .buffering(method)
        case .playing:
            state = .playing(method)
        }
    }

    private func publishSnapshot() {
        snapshot = MediaPlaybackSnapshot(
            player: player,
            state: state,
            isMuted: isMuted,
            timeline: MediaPlaybackTimeline(
                positionSeconds: positionSeconds,
                durationSeconds: durationSeconds,
                bufferedSeconds: bufferedSeconds
            )
        )
    }
}

struct MediaPlaybackActivityReportState: Equatable, Sendable {
    private var lastPauseState: Bool?

    mutating func begin(isPaused: Bool) {
        lastPauseState = isPaused
    }

    mutating func transition(to activity: MediaPlayerActivity) -> Bool? {
        let isPaused: Bool
        switch activity {
        case .paused:
            isPaused = true
        case .playing:
            isPaused = false
        case .idle, .waiting:
            return nil
        }
        guard lastPauseState != isPaused else { return nil }
        lastPauseState = isPaused
        return isPaused
    }

    mutating func reset() {
        lastPauseState = nil
    }
}

struct MediaPlaybackRetryContext: Equatable, Sendable {
    private(set) var interruptedPositionSeconds: Double = 0
    private(set) var resumePositionSeconds: Double = 0
    private(set) var durationSeconds: Double = 0

    mutating func capture(positionSeconds: Double, durationSeconds: Double) {
        let position = positionSeconds.isFinite ? max(0, positionSeconds) : 0
        let duration = durationSeconds.isFinite ? max(0, durationSeconds) : 0
        interruptedPositionSeconds = duration > 0 ? min(position, duration) : position
        self.durationSeconds = duration
        resumePositionSeconds = interruptedPositionSeconds >= 5
            ? max(0, interruptedPositionSeconds - 2)
            : 0
    }

    mutating func reset() {
        self = MediaPlaybackRetryContext()
    }
}
