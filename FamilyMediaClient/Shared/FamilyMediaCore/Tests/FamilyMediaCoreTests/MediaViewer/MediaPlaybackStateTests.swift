import Foundation
import Testing
@testable import FamilyMediaCore

struct MediaPlaybackStateTests {
    @Test func toggleIsOnlyAvailableAfterPlaybackHasResolved() {
        #expect(!MediaPlaybackState.idle.canTogglePlayback)
        #expect(!MediaPlaybackState.preparing.canTogglePlayback)
        #expect(!MediaPlaybackState.failed(MediaPlaybackFailure(message: "失败")).canTogglePlayback)
        #expect(MediaPlaybackState.playing(.directPlay).canTogglePlayback)
        #expect(MediaPlaybackState.paused(.directStream).canTogglePlayback)
        #expect(MediaPlaybackState.buffering(.transcode).canTogglePlayback)
    }

    @Test func presentationOnlyShowsTransientAndFailureStates() {
        #expect(!MediaPlaybackPresentation(state: .playing(.directPlay)).isVisible)
        #expect(!MediaPlaybackPresentation(state: .paused(.transcode)).isVisible)
        #expect(MediaPlaybackPresentation(state: .preparing).title == "正在准备播放")
        #expect(MediaPlaybackPresentation(state: .buffering(.directPlay)).title == "正在缓冲")
        #expect(MediaPlaybackPresentation(state: .buffering(.transcode)).title == "Jellyfin 正在转码")
        #expect(
            MediaPlaybackPresentation(
                state: .failed(MediaPlaybackFailure(message: "网络中断"))
            ).title == "网络中断"
        )
    }

    @Test func playbackFailuresExposeOnlyUsefulRecoveryActions() {
        #expect(MediaPlaybackFailure(error: JellyfinError.unauthorized).recovery == .signIn)
        #expect(MediaPlaybackFailure(error: JellyfinError.notAuthenticated).recovery == .signIn)
        #expect(MediaPlaybackFailure(error: JellyfinError.playbackUnavailable).recovery == .dismiss)
        #expect(MediaPlaybackFailure(error: URLError(.networkConnectionLost)).recovery == .retry)
        #expect(!MediaPlaybackFailure(error: JellyfinError.server(500)).message.contains("500"))
    }

    @Test func runtimePlaybackFailuresHideSystemTextAndPreserveNetworkGuidance() {
        let systemFailure = MediaPlaybackFailure(
            playbackError: NSError(domain: "AVFoundationErrorDomain", code: -1)
        )
        #expect(systemFailure.message.contains("播放意外中断"))
        #expect(systemFailure.recovery == .retry)

        let wrappedNetworkError = NSError(
            domain: "AVFoundationErrorDomain",
            code: -2,
            userInfo: [NSUnderlyingErrorKey: URLError(.networkConnectionLost)]
        )
        let networkFailure = MediaPlaybackFailure(playbackError: wrappedNetworkError)
        #expect(networkFailure.message.contains("无法连接"))
        #expect(networkFailure.recovery == .retry)
    }

    @Test func retryContextResumesNearTheFailureAndNeverLeaksAcrossPlayback() {
        var context = MediaPlaybackRetryContext()

        context.capture(positionSeconds: 42, durationSeconds: 120)
        #expect(context.interruptedPositionSeconds == 42)
        #expect(context.resumePositionSeconds == 40)
        #expect(context.durationSeconds == 120)

        context.reset()
        #expect(context == MediaPlaybackRetryContext())

        context.capture(positionSeconds: 3, durationSeconds: 120)
        #expect(context.resumePositionSeconds == 0)

        context.capture(positionSeconds: 150, durationSeconds: 120)
        #expect(context.interruptedPositionSeconds == 120)
        #expect(context.resumePositionSeconds == 118)
    }

    @Test func timelineClampsValuesAndFormatsShortAndLongDurations() {
        let short = MediaPlaybackTimeline(
            positionSeconds: 65.9,
            durationSeconds: 125,
            bufferedSeconds: 90
        )
        #expect(short.positionText == "1:05")
        #expect(short.durationText == "2:05")
        #expect(short.progress > 0.52 && short.progress < 0.53)

        let long = MediaPlaybackTimeline(
            positionSeconds: 65,
            durationSeconds: 3_661,
            bufferedSeconds: 8_000
        )
        #expect(long.positionText == "0:01:05")
        #expect(long.durationText == "1:01:01")
        #expect(long.bufferedSeconds == 3_661)
        #expect(long.bufferedProgress == 1)
    }

    @Test func timelineRejectsInvalidNumericValues() {
        let timeline = MediaPlaybackTimeline(
            positionSeconds: .nan,
            durationSeconds: .infinity,
            bufferedSeconds: -.infinity
        )
        #expect(timeline.positionSeconds == 0)
        #expect(timeline.durationSeconds == 0)
        #expect(timeline.bufferedSeconds == 0)
        #expect(!timeline.canSeek)
    }

    @Test func snapshotDerivesPlayingStateFromTheDomainState() {
        let playing = MediaPlaybackSnapshot(
            state: .playing(.directPlay),
            isMuted: true
        )
        let buffering = MediaPlaybackSnapshot(
            state: .buffering(.directPlay),
            isMuted: true
        )

        #expect(playing.isPlaying)
        #expect(playing.isMuted)
        #expect(!buffering.isPlaying)
    }
}
