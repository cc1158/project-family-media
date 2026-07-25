import Foundation

public final class JellyfinService: MediaCatalogServicing, MediaSourceHealthChecking, MediaPlaybackResolving, MediaPlaybackReporting, MediaResourceRequestAuthorizing, @unchecked Sendable {
    private let api: JellyfinAPIClient
    private let catalog: JellyfinCatalogService
    private let playback: JellyfinPlaybackService

    public init(
        configuration: JellyfinConfigurationStore,
        sessions: any JellyfinSessionStoring = KeychainJellyfinSessionStore(),
        httpClient: any HTTPClient = MediaNetworkSession.shared,
        identity: JellyfinClientIdentity = .default,
        onSessionInvalidated: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        let api = JellyfinAPIClient(
            configuration: configuration,
            sessions: sessions,
            httpClient: httpClient,
            identity: identity,
            onSessionInvalidated: onSessionInvalidated
        )
        self.api = api
        catalog = JellyfinCatalogService(api: api)
        playback = JellyfinPlaybackService(api: api, policy: .stableApple)
    }

    public var currentSession: JellyfinSession? { api.currentSession }

    public func publicInfo() async throws -> JellyfinServerInfo {
        try await api.send(path: "System/Info/Public", authenticated: false)
    }

    public func inspectConnection() async throws -> JellyfinServerInfo {
        let info = try await publicInfo()
        if let session = currentSession {
            let _: JellyfinUser = try await api.send(path: "Users/\(session.userID)")
        }
        return info
    }

    public func checkHealth() async throws -> HealthStatus {
        let info = try await inspectConnection()
        return HealthStatus(status: "ok", checks: [
            "jellyfin": HealthCheck(status: "ok", message: "\(info.ServerName) · \(info.Version)")
        ])
    }

    @discardableResult
    public func login(username: String, password: String) async throws -> JellyfinSession {
        let configurationRevision = api.configurationRevision
        let body = try JSONEncoder().encode(JellyfinLoginRequest(Username: username, Pw: password))
        let result: JellyfinAuthenticationResult = try await api.send(
            path: "Users/AuthenticateByName",
            method: "POST",
            body: body,
            authenticated: false
        )
        let session = JellyfinSession(
            accessToken: result.AccessToken,
            userID: result.User.Id,
            username: result.User.Name
        )
        try api.saveSession(
            session,
            ifConfigurationRevision: configurationRevision
        )
        return session
    }

    public func logout() { api.clearSession() }

    public func resourceRequest(for url: URL) -> MediaResourceRequest {
        api.resourceRequest(for: url)
    }

    public func fetchMedia(filter: MediaFilter, request: MediaPageRequest) async throws -> MediaPage {
        try await catalog.fetchMedia(filter: filter, request: request)
    }

    public func fetchMedia(containerID: String?, filter: MediaFilter, request: MediaPageRequest) async throws -> MediaPage {
        try await catalog.fetchMedia(containerID: containerID, filter: filter, request: request)
    }

    public func resolvePlayback(for item: MediaItem) async throws -> MediaPlaybackResolution {
        try await playback.resolvePlayback(for: item)
    }

    public func reportPlaybackStarted(item: MediaItem, resolution: MediaPlaybackResolution) async {
        await playback.reportPlaybackStarted(item: item, resolution: resolution)
    }

    public func reportPlaybackProgress(
        item: MediaItem,
        resolution: MediaPlaybackResolution,
        positionTicks: Int64,
        isPaused: Bool
    ) async {
        await playback.reportPlaybackProgress(
            item: item,
            resolution: resolution,
            positionTicks: positionTicks,
            isPaused: isPaused
        )
    }

    public func reportPlaybackStopped(
        item: MediaItem,
        resolution: MediaPlaybackResolution,
        positionTicks: Int64
    ) async {
        await playback.reportPlaybackStopped(
            item: item,
            resolution: resolution,
            positionTicks: positionTicks
        )
    }
}
