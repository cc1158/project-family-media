import Testing
@testable import FamilyMediaCore

struct MediaViewerWakePolicyTests {
    @Test func activePhotosAndActiveVideoWorkPreventIdleSleep() {
        #expect(policy(kind: .photo, state: .idle))
        #expect(policy(kind: .video, state: .preparing))
        #expect(policy(kind: .video, state: .buffering(.transcode)))
        #expect(policy(kind: .video, state: .playing(.directPlay)))
    }

    @Test func pausedFailedAndBackgroundVideoAllowIdleSleep() {
        #expect(!policy(kind: .video, state: .idle))
        #expect(!policy(kind: .video, state: .paused(.directPlay)))
        #expect(!policy(kind: .video, state: .failed(MediaPlaybackFailure(message: "失败"))))
        #expect(!policy(kind: .photo, state: .idle, isSceneActive: false))
        #expect(!policy(kind: .video, state: .playing(.transcode), isSceneActive: false))
    }

    @Test func loadingAndVisiblePhotosStayAwakeButFailureReleasesIdleSleep() {
        #expect(policy(kind: .photo, state: .idle, photoLoadState: .loading))
        #expect(policy(kind: .photo, state: .idle, photoLoadState: .ready))
        #expect(!policy(kind: .photo, state: .idle, photoLoadState: .failed))
    }

    private func policy(
        kind: MediaKind,
        state: MediaPlaybackState,
        photoLoadState: MediaPhotoLoadState = .ready,
        isSceneActive: Bool = true
    ) -> Bool {
        MediaViewerWakePolicy.shouldPreventIdleSleep(
            mediaKind: kind,
            playbackState: state,
            photoLoadState: photoLoadState,
            isSceneActive: isSceneActive
        )
    }
}
