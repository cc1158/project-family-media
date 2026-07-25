import AVKit
import Combine
import Foundation

public enum MediaPlayerActivity: Equatable, Sendable {
    case idle
    case paused
    case waiting
    case playing
}

@MainActor
public final class MediaPlaybackController: ObservableObject {
    @Published public private(set) var player: AVPlayer?
    @Published public private(set) var isPlaying = false
    @Published public private(set) var isMuted = false
    @Published public private(set) var activity: MediaPlayerActivity = .idle
    @Published public private(set) var positionSeconds: Double = 0
    @Published public private(set) var durationSeconds: Double = 0
    @Published public private(set) var bufferedSeconds: Double = 0

    private var playbackObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?
    private var timeJumpObserver: NSObjectProtocol?
    private var positionObserver: Any?
    private var reportObserver: Any?
    private var statusCancellable: AnyCancellable?
    private var timeControlCancellable: AnyCancellable?
    private var durationCancellable: AnyCancellable?
    private var loadedRangesCancellable: AnyCancellable?
    private var isSeeking = false
    private var seekGeneration = 0
    private var isAudioSessionActive = false
    private let audioSessionManager: any MediaAudioSessionManaging
    private let systemEventObserver: any MediaPlaybackSystemEventObserving

    public init(
        audioSessionManager: any MediaAudioSessionManaging = SystemMediaAudioSessionManager(),
        systemEventObserver: any MediaPlaybackSystemEventObserving = SystemMediaPlaybackEventObserver()
    ) {
        self.audioSessionManager = audioSessionManager
        self.systemEventObserver = systemEventObserver
    }

    deinit {
        MainActor.assumeIsolated {
            reset(deactivateAudioSession: true)
        }
    }

    public func configureVideo(
        url: URL,
        autoplay: Bool,
        onPlaybackEnded: @escaping @MainActor () -> Void,
        onReady: @escaping @MainActor () -> Void = {},
        onFailure: @escaping @MainActor (Error?) -> Void = { _ in },
        onProgress: @escaping @MainActor (Int64) -> Void = { _ in },
        onTimeJumped: @escaping @MainActor (Int64) -> Void = { _ in }
    ) {
        reset(deactivateAudioSession: false)
        if autoplay, !isMuted {
            activateAudioSessionIfNeeded()
        } else {
            deactivateAudioSessionIfNeeded()
        }

        let nextPlayer = AVPlayer(url: url)
        nextPlayer.automaticallyWaitsToMinimizeStalling = true
        nextPlayer.isMuted = isMuted
        player = nextPlayer
        observePlaybackEnd(for: nextPlayer, onPlaybackEnded: onPlaybackEnded)
        observeStatus(for: nextPlayer, onReady: onReady, onFailure: onFailure)
        observeTimeControlStatus(for: nextPlayer)
        observeTimeline(for: nextPlayer)
        observeProgress(for: nextPlayer, onProgress: onProgress)
        observeTimeJumps(for: nextPlayer, onTimeJumped: onTimeJumped)
        systemEventObserver.start { [weak self] in
            self?.pause()
        }

        if autoplay {
            nextPlayer.play()
            isPlaying = true
        }
    }

    public func togglePlayback() {
        guard let player else { return }

        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            play()
        }
    }

    public func setMuted(_ muted: Bool) {
        guard isMuted != muted else { return }
        isMuted = muted
        player?.isMuted = muted

        // Do not deactivate an active session when muting a running player.
        // That can emit a route/interruption event which pauses playback.
        guard !muted, isPlaybackActive else { return }
        activateAudioSessionIfNeeded()
    }

    public func toggleMuted() {
        setMuted(!isMuted)
    }

    @discardableResult
    public func play() -> Bool {
        guard let player, !isPlaying else { return false }
        if !isMuted {
            activateAudioSessionIfNeeded()
        }
        player.play()
        isPlaying = true
        return true
    }

    @discardableResult
    public func pause() -> Bool {
        guard let player, isPlaying else { return false }
        player.pause()
        isPlaying = false
        return true
    }

    @discardableResult
    public func pauseAndDeactivateAudioSession() -> Bool {
        let didPause = pause()
        deactivateAudioSessionIfNeeded()
        return didPause
    }

    public func clear() {
        reset(deactivateAudioSession: true)
    }

    private func reset(deactivateAudioSession: Bool) {
        systemEventObserver.stop()
        removePlaybackObserver()
        removeStatusObserver()
        removeProgressObserver()
        player?.pause()
        player = nil
        isPlaying = false
        activity = .idle
        positionSeconds = 0
        durationSeconds = 0
        bufferedSeconds = 0
        isSeeking = false
        seekGeneration &+= 1
        if deactivateAudioSession {
            deactivateAudioSessionIfNeeded()
        }
    }

    private func activateAudioSessionIfNeeded() {
        guard !isAudioSessionActive else { return }
        audioSessionManager.activateForVideoPlayback()
        isAudioSessionActive = true
    }

    private var isPlaybackActive: Bool {
        isPlaying || (player?.rate ?? 0) != 0
    }

    private func deactivateAudioSessionIfNeeded() {
        guard isAudioSessionActive else { return }
        audioSessionManager.deactivateAfterVideoPlayback()
        isAudioSessionActive = false
    }

    public func seek(
        to seconds: Double,
        onCompletion: @escaping @MainActor @Sendable (Bool) -> Void = { _ in }
    ) {
        guard let player else {
            onCompletion(false)
            return
        }
        let upperBound = durationSeconds > 0 ? durationSeconds : seconds
        let target = min(max(0, seconds), upperBound)
        seekGeneration &+= 1
        let generation = seekGeneration
        isSeeking = true
        positionSeconds = target
        let tolerance = CMTime(seconds: 0.5, preferredTimescale: 600)
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: tolerance,
            toleranceAfter: tolerance
        ) { [weak self] finished in
            Task { @MainActor [weak self] in
                guard let self, self.seekGeneration == generation else { return }
                self.isSeeking = false
                if finished {
                    self.positionSeconds = target
                }
                onCompletion(finished)
            }
        }
    }

    private func observePlaybackEnd(
        for player: AVPlayer,
        onPlaybackEnded: @escaping @MainActor () -> Void
    ) {
        playbackObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self, weak player] _ in
            Task { @MainActor [weak self, weak player] in
                guard let self, let player, self.player === player else { return }
                onPlaybackEnded()
            }
        }
    }

    private func removePlaybackObserver() {
        if let playbackObserver {
            NotificationCenter.default.removeObserver(playbackObserver)
            self.playbackObserver = nil
        }
        if let failureObserver {
            NotificationCenter.default.removeObserver(failureObserver)
            self.failureObserver = nil
        }
        if let timeJumpObserver {
            NotificationCenter.default.removeObserver(timeJumpObserver)
            self.timeJumpObserver = nil
        }
    }

    private func observeStatus(
        for player: AVPlayer,
        onReady: @escaping @MainActor () -> Void,
        onFailure: @escaping @MainActor (Error?) -> Void
    ) {
        guard let item = player.currentItem else { return }
        statusCancellable = item.publisher(for: \.status, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak player, weak item] status in
                guard let self, let player, self.player === player else { return }
                switch status {
                case .readyToPlay: onReady()
                case .failed:
                    self.isPlaying = false
                    onFailure(item?.error)
                default: break
                }
            }
        failureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self, weak player] notification in
            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            Task { @MainActor [weak self, weak player] in
                guard let self, let player, self.player === player else { return }
                self.isPlaying = false
                onFailure(error)
            }
        }
    }

    private func observeProgress(for player: AVPlayer, onProgress: @escaping @MainActor (Int64) -> Void) {
        reportObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 15, preferredTimescale: 600), queue: .main) { [weak self, weak player] time in
            guard time.isNumeric, time.seconds.isFinite else { return }
            let ticks = Int64(max(0, time.seconds) * 10_000_000)
            Task { @MainActor [weak self, weak player] in
                guard let self, let player, self.player === player else { return }
                onProgress(ticks)
            }
        }
    }

    private func observeTimeJumps(
        for player: AVPlayer,
        onTimeJumped: @escaping @MainActor (Int64) -> Void
    ) {
        guard let item = player.currentItem else { return }
        timeJumpObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemTimeJumped,
            object: item,
            queue: .main
        ) { [weak self, weak player] _ in
            Task { @MainActor [weak self, weak player] in
                guard let self,
                      let player,
                      self.player === player,
                      !self.isSeeking
                else { return }
                let seconds = player.currentTime().seconds
                guard seconds.isFinite else { return }
                self.positionSeconds = max(0, seconds)
                onTimeJumped(Int64(self.positionSeconds * 10_000_000))
            }
        }
    }

    private func removeStatusObserver() {
        statusCancellable?.cancel()
        statusCancellable = nil
        timeControlCancellable?.cancel()
        timeControlCancellable = nil
        durationCancellable?.cancel()
        durationCancellable = nil
        loadedRangesCancellable?.cancel()
        loadedRangesCancellable = nil
    }

    private func observeTimeControlStatus(for player: AVPlayer) {
        timeControlCancellable = player.publisher(for: \.timeControlStatus, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak player] status in
                guard let self, let player, self.player === player else { return }
                switch status {
                case .paused:
                    activity = .paused
                    isPlaying = false
                case .waitingToPlayAtSpecifiedRate:
                    activity = .waiting
                    isPlaying = player.rate != 0
                    if !isMuted, isPlaying {
                        activateAudioSessionIfNeeded()
                    }
                case .playing:
                    activity = .playing
                    isPlaying = true
                    if !isMuted {
                        activateAudioSessionIfNeeded()
                    }
                @unknown default:
                    activity = .paused
                    isPlaying = false
                }
            }
    }

    private func removeProgressObserver() {
        if let positionObserver, let player { player.removeTimeObserver(positionObserver) }
        if let reportObserver, let player { player.removeTimeObserver(reportObserver) }
        positionObserver = nil
        reportObserver = nil
    }

    private func observeTimeline(for player: AVPlayer) {
        guard let item = player.currentItem else { return }

        positionObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self, weak player] time in
            guard time.isNumeric, time.seconds.isFinite else { return }
            let seconds = max(0, time.seconds)
            Task { @MainActor [weak self, weak player] in
                guard let self, let player, self.player === player,
                      !self.isSeeking
                else { return }
                self.positionSeconds = seconds
            }
        }

        durationCancellable = item.publisher(for: \.duration, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak player] duration in
                guard let self, let player, self.player === player else { return }
                guard duration.isNumeric, duration.seconds.isFinite, duration.seconds > 0 else {
                    self.durationSeconds = 0
                    return
                }
                self.durationSeconds = duration.seconds
            }

        loadedRangesCancellable = item.publisher(for: \.loadedTimeRanges, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak player] ranges in
                guard let self, let player, self.player === player else { return }
                let bufferedEnd = ranges
                    .map(\.timeRangeValue)
                    .map { $0.start.seconds + $0.duration.seconds }
                    .filter(\.isFinite)
                    .max() ?? 0
                self.bufferedSeconds = max(0, bufferedEnd)
            }
    }
}
