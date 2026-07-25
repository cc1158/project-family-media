import Foundation

public enum MediaPlaybackMethod: String, Equatable, Sendable {
    case directPlay
    case directStream
    case transcode
}

public struct MediaPlaybackResolution: Equatable, Sendable {
    public let url: URL
    public let method: MediaPlaybackMethod
    public let playSessionID: String?
    public let mediaSourceID: String?

    public init(url: URL, method: MediaPlaybackMethod, playSessionID: String? = nil, mediaSourceID: String? = nil) {
        self.url = url
        self.method = method
        self.playSessionID = playSessionID
        self.mediaSourceID = mediaSourceID
    }
}

public enum MediaPlaybackRecovery: Equatable, Sendable {
    case retry
    case signIn
    case dismiss
}

public struct MediaPlaybackFailure: Equatable, Sendable {
    public let message: String
    public let recovery: MediaPlaybackRecovery

    public init(message: String, recovery: MediaPlaybackRecovery = .retry) {
        self.message = message
        self.recovery = recovery
    }

    public init(error: Error) {
        switch error {
        case JellyfinError.notAuthenticated, JellyfinError.unauthorized:
            message = "Jellyfin 登录已失效，请重新登录。"
            recovery = .signIn
        case JellyfinError.playbackUnavailable:
            message = "Jellyfin 无法为这个视频提供可播放的格式。"
            recovery = .dismiss
        case JellyfinError.server:
            message = "Jellyfin 暂时无法准备这个视频，请稍后重新尝试。"
            recovery = .retry
        case JellyfinError.invalidResponse:
            message = "Jellyfin 返回了无法识别的播放信息，请检查服务器是否需要更新。"
            recovery = .retry
        default:
            message = AppErrorMapper.message(for: error)
            recovery = .retry
        }
    }

    public init(playbackError error: Error?) {
        recovery = .retry
        if let urlError = Self.underlyingURLError(in: error) {
            message = AppErrorMapper.message(for: urlError)
        } else {
            message = "播放意外中断，请确认 NAS 和家庭网络正常后重新尝试。"
        }
    }

    private static func underlyingURLError(in error: Error?) -> URLError? {
        guard let error else { return nil }
        if let urlError = error as? URLError {
            return urlError
        }
        let underlying = (error as NSError).userInfo[NSUnderlyingErrorKey] as? Error
        guard let underlying, (underlying as NSError) !== (error as NSError) else { return nil }
        return underlyingURLError(in: underlying)
    }
}

public enum MediaPlaybackState: Equatable, Sendable {
    case idle
    case preparing
    case playing(MediaPlaybackMethod)
    case paused(MediaPlaybackMethod)
    case buffering(MediaPlaybackMethod)
    case failed(MediaPlaybackFailure)

    public var canTogglePlayback: Bool {
        switch self {
        case .playing, .paused, .buffering:
            true
        case .idle, .preparing, .failed:
            false
        }
    }
}

public struct MediaPlaybackPresentation: Equatable, Sendable {
    public let title: String?
    public let isVisible: Bool

    public init(state: MediaPlaybackState) {
        switch state {
        case .preparing:
            title = "正在准备播放"
            isVisible = true
        case .buffering(.transcode):
            title = "Jellyfin 正在转码"
            isVisible = true
        case .buffering:
            title = "正在缓冲"
            isVisible = true
        case .failed(let failure):
            title = failure.message
            isVisible = true
        case .idle, .playing, .paused:
            title = nil
            isVisible = false
        }
    }
}

public struct MediaPlaybackTimeline: Equatable, Sendable {
    public let positionSeconds: Double
    public let durationSeconds: Double
    public let bufferedSeconds: Double

    public init(positionSeconds: Double, durationSeconds: Double, bufferedSeconds: Double) {
        let duration = Self.sanitized(durationSeconds)
        self.durationSeconds = duration
        self.positionSeconds = min(Self.sanitized(positionSeconds), duration > 0 ? duration : .greatestFiniteMagnitude)
        self.bufferedSeconds = min(Self.sanitized(bufferedSeconds), duration > 0 ? duration : .greatestFiniteMagnitude)
    }

    public var canSeek: Bool { durationSeconds > 0 }
    public var progress: Double { durationSeconds > 0 ? positionSeconds / durationSeconds : 0 }
    public var bufferedProgress: Double { durationSeconds > 0 ? bufferedSeconds / durationSeconds : 0 }
    public var positionText: String { Self.format(positionSeconds, showsHours: durationSeconds >= 3_600) }
    public var durationText: String { Self.format(durationSeconds, showsHours: durationSeconds >= 3_600) }

    private static func sanitized(_ value: Double) -> Double {
        value.isFinite ? max(0, value) : 0
    }

    private static func format(_ value: Double, showsHours: Bool) -> String {
        let totalSeconds = Int(value.rounded(.down))
        let seconds = totalSeconds % 60
        let minutes = (totalSeconds / 60) % 60
        if showsHours {
            return String(format: "%d:%02d:%02d", totalSeconds / 3_600, minutes, seconds)
        }
        return String(format: "%d:%02d", totalSeconds / 60, seconds)
    }
}

public protocol MediaPlaybackResolving: Sendable {
    func resolvePlayback(for item: MediaItem) async throws -> MediaPlaybackResolution
}

public protocol MediaPlaybackReporting: Sendable {
    func reportPlaybackStarted(item: MediaItem, resolution: MediaPlaybackResolution) async
    func reportPlaybackProgress(item: MediaItem, resolution: MediaPlaybackResolution, positionTicks: Int64, isPaused: Bool) async
    func reportPlaybackStopped(item: MediaItem, resolution: MediaPlaybackResolution, positionTicks: Int64) async
}

public struct DirectMediaPlaybackResolver: MediaPlaybackResolving {
    public init() {}

    public func resolvePlayback(for item: MediaItem) async throws -> MediaPlaybackResolution {
        MediaPlaybackResolution(url: item.url, method: .directPlay)
    }
}
