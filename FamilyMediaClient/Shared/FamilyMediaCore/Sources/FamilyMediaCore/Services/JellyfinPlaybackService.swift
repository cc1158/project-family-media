import Foundation

struct JellyfinPlaybackPolicy: Sendable {
    static let stableApple = JellyfinPlaybackPolicy(maxStreamingBitrate: 20_000_000)
    let maxStreamingBitrate: Int
    var deviceProfile: JellyfinDeviceProfile { JellyfinDeviceProfile() }
}

struct JellyfinPlaybackService: MediaPlaybackResolving, MediaPlaybackReporting {
    let api: JellyfinAPIClient
    let policy: JellyfinPlaybackPolicy

    func resolvePlayback(for item: MediaItem) async throws -> MediaPlaybackResolution {
        guard item.sourceID == .jellyfin, item.kind == .video else {
            return MediaPlaybackResolution(url: item.url, method: .directPlay)
        }
        guard let session = api.currentSession else { throw JellyfinError.notAuthenticated }
        let request = JellyfinPlaybackInfoRequest(
            UserId: session.userID,
            DeviceProfile: policy.deviceProfile,
            MaxStreamingBitrate: policy.maxStreamingBitrate,
            EnableDirectPlay: true,
            EnableDirectStream: true,
            EnableTranscoding: true,
            AllowVideoStreamCopy: true,
            AllowAudioStreamCopy: true
        )
        let response: JellyfinPlaybackInfoResponse = try await api.send(
            path: "Items/\(item.mediaPath)/PlaybackInfo",
            method: "POST",
            body: try JSONEncoder().encode(request)
        )
        guard let source = response.MediaSources.first else { throw JellyfinError.playbackUnavailable }
        if source.SupportsDirectPlay == true {
            guard let url = api.makeURL(path: "Videos/\(item.mediaPath)/stream", query: [
                URLQueryItem(name: "static", value: "true"),
                URLQueryItem(name: "mediaSourceId", value: source.Id),
                URLQueryItem(name: "api_key", value: session.accessToken)
            ]) else { throw JellyfinError.invalidAddress }
            return resolution(url: url, method: .directPlay, response: response, source: source)
        }
        guard source.SupportsTranscoding == true || source.SupportsDirectStream == true,
              let path = source.TranscodingUrl,
              let url = api.authenticatedPlaybackURL(from: path, token: session.accessToken)
        else { throw JellyfinError.playbackUnavailable }
        let method: MediaPlaybackMethod = source.SupportsDirectStream == true && source.SupportsTranscoding != true
            ? .directStream
            : .transcode
        return resolution(url: url, method: method, response: response, source: source)
    }

    func reportPlaybackStarted(item: MediaItem, resolution: MediaPlaybackResolution) async {
        await report(path: "Sessions/Playing", item: item, resolution: resolution, positionTicks: 0, isPaused: false)
    }

    func reportPlaybackProgress(item: MediaItem, resolution: MediaPlaybackResolution, positionTicks: Int64, isPaused: Bool) async {
        await report(path: "Sessions/Playing/Progress", item: item, resolution: resolution, positionTicks: positionTicks, isPaused: isPaused)
    }

    func reportPlaybackStopped(item: MediaItem, resolution: MediaPlaybackResolution, positionTicks: Int64) async {
        await report(path: "Sessions/Playing/Stopped", item: item, resolution: resolution, positionTicks: positionTicks, isPaused: false)
    }

    private func resolution(
        url: URL,
        method: MediaPlaybackMethod,
        response: JellyfinPlaybackInfoResponse,
        source: JellyfinMediaSource
    ) -> MediaPlaybackResolution {
        MediaPlaybackResolution(
            url: url,
            method: method,
            playSessionID: response.PlaySessionId,
            mediaSourceID: source.Id
        )
    }

    private func report(
        path: String,
        item: MediaItem,
        resolution: MediaPlaybackResolution,
        positionTicks: Int64,
        isPaused: Bool
    ) async {
        let body = JellyfinPlaybackReport(
            ItemId: item.mediaPath,
            MediaSourceId: resolution.mediaSourceID,
            PlaySessionId: resolution.playSessionID,
            PositionTicks: positionTicks,
            IsPaused: isPaused,
            PlayMethod: playMethod(resolution.method),
            CanSeek: true
        )
        guard let data = try? JSONEncoder().encode(body) else { return }
        try? await api.sendNoContent(path: path, body: data)
    }

    private func playMethod(_ method: MediaPlaybackMethod) -> String {
        switch method {
        case .directPlay: return "DirectPlay"
        case .directStream: return "DirectStream"
        case .transcode: return "Transcode"
        }
    }
}
