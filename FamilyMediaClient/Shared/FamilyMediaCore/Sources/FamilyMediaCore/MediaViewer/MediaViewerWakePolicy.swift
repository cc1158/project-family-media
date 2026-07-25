import Foundation

public enum MediaPhotoLoadState: Equatable, Sendable {
    case loading
    case ready
    case failed
}

public enum MediaViewerWakePolicy {
    public static func shouldPreventIdleSleep(
        mediaKind: MediaKind,
        playbackState: MediaPlaybackState,
        photoLoadState: MediaPhotoLoadState = .ready,
        isSceneActive: Bool
    ) -> Bool {
        guard isSceneActive else { return false }
        guard mediaKind == .video else {
            return photoLoadState != .failed
        }

        return switch playbackState {
        case .preparing, .playing, .buffering:
            true
        case .idle, .paused, .failed:
            false
        }
    }
}
