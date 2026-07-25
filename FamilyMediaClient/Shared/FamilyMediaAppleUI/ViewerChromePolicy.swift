import FamilyMediaCore

struct ViewerChromePolicy {
    static let autoHideSeconds = 4

    static func shouldAutoHide(
        mediaKind: MediaKind,
        playbackState: MediaPlaybackState,
        isVoiceOverEnabled: Bool,
        isScrubbing: Bool,
        isOverlayPresented: Bool,
        isPhotoInspectionActive: Bool,
        isPhotoReady: Bool,
        isPhotoAutoAdvancePaused: Bool
    ) -> Bool {
        guard !isVoiceOverEnabled,
              !isScrubbing,
              !isOverlayPresented
        else {
            return false
        }

        switch mediaKind {
        case .photo:
            return isPhotoReady
                && !isPhotoInspectionActive
                && !isPhotoAutoAdvancePaused
        case .video:
            if case .playing = playbackState {
                return true
            }
            return false
        }
    }
}
