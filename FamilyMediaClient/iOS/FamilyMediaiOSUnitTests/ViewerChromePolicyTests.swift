import FamilyMediaCore
import XCTest
@testable import FamilyMediaiOS

final class ViewerChromePolicyTests: XCTestCase {
    func testOnlyActiveUnobstructedViewingAutoHidesChrome() {
        XCTAssertTrue(
            ViewerChromePolicy.shouldAutoHide(
                mediaKind: .video,
                playbackState: .playing(.directPlay),
                isVoiceOverEnabled: false,
                isScrubbing: false,
                isOverlayPresented: false,
                isPhotoInspectionActive: false,
                isPhotoReady: false,
                isPhotoAutoAdvancePaused: false
            )
        )
        XCTAssertTrue(
            ViewerChromePolicy.shouldAutoHide(
                mediaKind: .photo,
                playbackState: .idle,
                isVoiceOverEnabled: false,
                isScrubbing: false,
                isOverlayPresented: false,
                isPhotoInspectionActive: false,
                isPhotoReady: true,
                isPhotoAutoAdvancePaused: false
            )
        )

        XCTAssertFalse(policy(playbackState: .paused(.directPlay)))
        XCTAssertFalse(policy(playbackState: .buffering(.transcode)))
        XCTAssertFalse(policy(isVoiceOverEnabled: true))
        XCTAssertFalse(policy(isScrubbing: true))
        XCTAssertFalse(policy(isOverlayPresented: true))
        XCTAssertFalse(
            ViewerChromePolicy.shouldAutoHide(
                mediaKind: .photo,
                playbackState: .idle,
                isVoiceOverEnabled: false,
                isScrubbing: false,
                isOverlayPresented: false,
                isPhotoInspectionActive: true,
                isPhotoReady: true,
                isPhotoAutoAdvancePaused: false
            )
        )
        XCTAssertFalse(
            ViewerChromePolicy.shouldAutoHide(
                mediaKind: .photo,
                playbackState: .idle,
                isVoiceOverEnabled: false,
                isScrubbing: false,
                isOverlayPresented: false,
                isPhotoInspectionActive: false,
                isPhotoReady: false,
                isPhotoAutoAdvancePaused: false
            )
        )
        XCTAssertFalse(
            ViewerChromePolicy.shouldAutoHide(
                mediaKind: .photo,
                playbackState: .idle,
                isVoiceOverEnabled: false,
                isScrubbing: false,
                isOverlayPresented: false,
                isPhotoInspectionActive: false,
                isPhotoReady: true,
                isPhotoAutoAdvancePaused: true
            )
        )
    }

    private func policy(
        playbackState: MediaPlaybackState = .playing(.directPlay),
        isVoiceOverEnabled: Bool = false,
        isScrubbing: Bool = false,
        isOverlayPresented: Bool = false
    ) -> Bool {
        ViewerChromePolicy.shouldAutoHide(
            mediaKind: .video,
            playbackState: playbackState,
            isVoiceOverEnabled: isVoiceOverEnabled,
            isScrubbing: isScrubbing,
            isOverlayPresented: isOverlayPresented,
            isPhotoInspectionActive: false,
            isPhotoReady: false,
            isPhotoAutoAdvancePaused: false
        )
    }
}
