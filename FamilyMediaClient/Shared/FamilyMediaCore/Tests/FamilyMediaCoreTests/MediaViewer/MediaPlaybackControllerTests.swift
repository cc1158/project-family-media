import AVFoundation
import Foundation
import Testing
@testable import FamilyMediaCore

@MainActor
struct MediaPlaybackControllerTests {
    @Test func mutedPlaybackPersistsAcrossPlayersWithoutClaimingAudioSession() {
        let audioSession = RecordingAudioSessionManager()
        let controller = MediaPlaybackController(
            audioSessionManager: audioSession,
            systemEventObserver: RecordingSystemEventObserver()
        )

        #expect(!controller.isMuted)
        controller.setMuted(true)
        controller.configureVideo(
            url: URL(fileURLWithPath: "/nonexistent/muted-first.mp4"),
            autoplay: true,
            onPlaybackEnded: {}
        )

        #expect(controller.isMuted)
        #expect(controller.player?.isMuted == true)
        #expect(audioSession.activationCount == 0)

        controller.configureVideo(
            url: URL(fileURLWithPath: "/nonexistent/muted-second.mp4"),
            autoplay: true,
            onPlaybackEnded: {}
        )

        #expect(controller.player?.isMuted == true)
        #expect(audioSession.activationCount == 0)
        controller.clear()
    }

    @Test func muteToggleDoesNotPausePlaybackOrReleaseActiveAudioSession() {
        let audioSession = RecordingAudioSessionManager()
        let controller = MediaPlaybackController(
            audioSessionManager: audioSession,
            systemEventObserver: RecordingSystemEventObserver()
        )
        controller.setMuted(true)
        controller.configureVideo(
            url: URL(fileURLWithPath: "/nonexistent/mute-toggle.mp4"),
            autoplay: true,
            onPlaybackEnded: {}
        )

        controller.setMuted(false)
        #expect(controller.player?.isMuted == false)
        #expect(audioSession.activationCount == 1)
        #expect(controller.isPlaying)

        controller.setMuted(true)
        #expect(controller.player?.isMuted == true)
        #expect(controller.isPlaying)
        #expect(audioSession.deactivationCount == 0)

        controller.clear()
        #expect(audioSession.deactivationCount == 1)
    }

    @Test func audioSessionStaysActiveAcrossVideoSwitchAndReleasesOnceOnClear() {
        let audioSession = RecordingAudioSessionManager()
        let systemEvents = RecordingSystemEventObserver()
        let controller = MediaPlaybackController(
            audioSessionManager: audioSession,
            systemEventObserver: systemEvents
        )
        let firstURL = URL(fileURLWithPath: "/nonexistent/first.mp4")
        let secondURL = URL(fileURLWithPath: "/nonexistent/second.mp4")

        controller.configureVideo(url: firstURL, autoplay: true, onPlaybackEnded: {})
        controller.configureVideo(url: secondURL, autoplay: true, onPlaybackEnded: {})

        #expect(audioSession.activationCount == 1)
        #expect(audioSession.deactivationCount == 0)

        controller.clear()
        controller.clear()

        #expect(audioSession.deactivationCount == 1)
        #expect(controller.player == nil)
        #expect(systemEvents.stopCount == 2)
    }

    @Test func appInterruptionReleasesAudioSessionAndManualPlayReactivatesIt() {
        let audioSession = RecordingAudioSessionManager()
        let controller = MediaPlaybackController(
            audioSessionManager: audioSession,
            systemEventObserver: RecordingSystemEventObserver()
        )

        controller.configureVideo(
            url: URL(fileURLWithPath: "/nonexistent/background.mp4"),
            autoplay: false,
            onPlaybackEnded: {}
        )

        #expect(audioSession.activationCount == 0)
        #expect(!controller.pauseAndDeactivateAudioSession())
        #expect(audioSession.deactivationCount == 0)

        controller.togglePlayback()
        #expect(audioSession.activationCount == 1)

        controller.clear()
        controller.clear()
        #expect(audioSession.deactivationCount == 1)
    }

    @Test func systemAudioEventPausesActivePlaybackOnlyOnceWithoutAutoResuming() {
        let systemEvents = RecordingSystemEventObserver()
        let controller = MediaPlaybackController(systemEventObserver: systemEvents)

        controller.configureVideo(
            url: URL(fileURLWithPath: "/nonexistent/interruption.mp4"),
            autoplay: true,
            onPlaybackEnded: {}
        )
        systemEvents.requestPause()
        systemEvents.requestPause()

        #expect(!controller.isPlaying)
        #expect(controller.player?.rate == 0)

        controller.clear()
    }

    @Test func controllerDeinitReleasesAudioSessionAndSystemObservers() {
        let audioSession = RecordingAudioSessionManager()
        let systemEvents = RecordingSystemEventObserver()
        let weakController = autoreleasepool {
            let controller = MediaPlaybackController(
                audioSessionManager: audioSession,
                systemEventObserver: systemEvents
            )
            let weakController = WeakBox(controller)
            controller.configureVideo(
                url: URL(fileURLWithPath: "/nonexistent/deinit.mp4"),
                autoplay: true,
                onPlaybackEnded: {}
            )
            return weakController
        }

        #expect(weakController.value == nil)
        #expect(audioSession.deactivationCount == 1)
        #expect(systemEvents.stopCount == 1)
    }

    @Test func queuedCallbacksFromReplacedPlayerCannotAffectCurrentPlayback() async {
        let controller = MediaPlaybackController(
            audioSessionManager: RecordingAudioSessionManager(),
            systemEventObserver: RecordingSystemEventObserver()
        )
        var staleEndCount = 0
        var staleFailureCount = 0

        controller.configureVideo(
            url: URL(fileURLWithPath: "/nonexistent/replaced.mp4"),
            autoplay: false,
            onPlaybackEnded: { staleEndCount += 1 },
            onFailure: { _ in staleFailureCount += 1 }
        )
        let replacedItem = controller.player?.currentItem

        NotificationCenter.default.post(
            name: .AVPlayerItemDidPlayToEndTime,
            object: replacedItem
        )
        NotificationCenter.default.post(
            name: .AVPlayerItemFailedToPlayToEndTime,
            object: replacedItem,
            userInfo: [AVPlayerItemFailedToPlayToEndTimeErrorKey: URLError(.networkConnectionLost)]
        )

        controller.configureVideo(
            url: URL(fileURLWithPath: "/nonexistent/current.mp4"),
            autoplay: false,
            onPlaybackEnded: {}
        )
        await Task.yield()
        await Task.yield()

        #expect(staleEndCount == 0)
        #expect(staleFailureCount == 0)
        #expect(controller.player?.currentItem !== replacedItem)
        controller.clear()
    }

    @Test func nativePlayerTimeJumpPublishesImmediateProgressAndRejectsStaleItems() async {
        let controller = MediaPlaybackController(
            audioSessionManager: RecordingAudioSessionManager(),
            systemEventObserver: RecordingSystemEventObserver()
        )
        var reportedTicks: [Int64] = []

        controller.configureVideo(
            url: URL(fileURLWithPath: "/nonexistent/native-scrub.mp4"),
            autoplay: false,
            onPlaybackEnded: {},
            onTimeJumped: { reportedTicks.append($0) }
        )
        let replacedItem = controller.player?.currentItem
        NotificationCenter.default.post(
            name: .AVPlayerItemTimeJumped,
            object: replacedItem
        )
        await Task.yield()
        await Task.yield()

        #expect(reportedTicks == [0])

        controller.configureVideo(
            url: URL(fileURLWithPath: "/nonexistent/replacement.mp4"),
            autoplay: false,
            onPlaybackEnded: {},
            onTimeJumped: { reportedTicks.append($0) }
        )
        NotificationCenter.default.post(
            name: .AVPlayerItemTimeJumped,
            object: replacedItem
        )
        await Task.yield()
        await Task.yield()

        #expect(reportedTicks == [0])
        controller.clear()
    }
}

private final class WeakBox<Value: AnyObject> {
    weak var value: Value?

    init(_ value: Value) {
        self.value = value
    }
}

@MainActor
private final class RecordingAudioSessionManager: MediaAudioSessionManaging {
    private(set) var activationCount = 0
    private(set) var deactivationCount = 0

    func activateForVideoPlayback() {
        activationCount += 1
    }

    func deactivateAfterVideoPlayback() {
        deactivationCount += 1
    }
}

@MainActor
private final class RecordingSystemEventObserver: MediaPlaybackSystemEventObserving {
    private var onPauseRequested: (@MainActor () -> Void)?
    private(set) var stopCount = 0

    func start(onPauseRequested: @escaping @MainActor () -> Void) {
        self.onPauseRequested = onPauseRequested
    }

    func stop() {
        if onPauseRequested != nil {
            stopCount += 1
        }
        onPauseRequested = nil
    }

    func requestPause() {
        onPauseRequested?()
    }
}
