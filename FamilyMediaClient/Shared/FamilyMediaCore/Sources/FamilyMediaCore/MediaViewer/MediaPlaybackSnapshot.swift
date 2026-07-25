import AVKit
import Foundation

public struct MediaPlaybackSnapshot: Equatable {
    public let player: AVPlayer?
    public let state: MediaPlaybackState
    public let isMuted: Bool
    public let timeline: MediaPlaybackTimeline

    public init(
        player: AVPlayer? = nil,
        state: MediaPlaybackState = .idle,
        isMuted: Bool = false,
        timeline: MediaPlaybackTimeline = MediaPlaybackTimeline(
            positionSeconds: 0,
            durationSeconds: 0,
            bufferedSeconds: 0
        )
    ) {
        self.player = player
        self.state = state
        self.isMuted = isMuted
        self.timeline = timeline
    }

    public var isPlaying: Bool {
        if case .playing = state { return true }
        return false
    }

    public static func == (
        lhs: MediaPlaybackSnapshot,
        rhs: MediaPlaybackSnapshot
    ) -> Bool {
        lhs.player === rhs.player
            && lhs.state == rhs.state
            && lhs.isMuted == rhs.isMuted
            && lhs.timeline == rhs.timeline
    }
}
