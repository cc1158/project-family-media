import Foundation

public enum FamilyMediaCompatibilityError: Error, Equatable, LocalizedError, Sendable {
    case serverUpdateRequired

    public var errorDescription: String? {
        "NAS 上的家庭媒体服务版本较旧，请部署最新服务端后重新检查。"
    }
}

public protocol MediaCatalogServicing: Sendable {
    func fetchMedia(filter: MediaFilter, request: MediaPageRequest) async throws -> MediaPage
    func fetchMedia(containerID: String?, filter: MediaFilter, request: MediaPageRequest) async throws -> MediaPage
}

public extension MediaCatalogServicing {
    func fetchMedia(containerID: String?, filter: MediaFilter, request: MediaPageRequest) async throws -> MediaPage {
        try await fetchMedia(filter: filter, request: request)
    }
}

public protocol MediaSourceHealthChecking: Sendable {
    func checkHealth() async throws -> HealthStatus
}

public protocol MediaTimelineServicing: Sendable {
    func supportsTimeline() async -> Bool
    func fetchTimelineIndex(request: MediaTimelineRequest) async throws -> MediaTimelineIndex
    func fetchTimelineMonth(
        key: String,
        request: MediaTimelineRequest,
        page: MediaPageRequest
    ) async throws -> MediaPage
}

public protocol FamilyMediaAdminServicing: Sendable {
    func triggerScan() async throws -> ScanTriggerResponse
    func fetchScanStatus() async throws -> ScanStatus
    func regenerateThumbnail(mediaID: String, request: ThumbnailRegenerationRequest) async throws -> ThumbnailRegenerationResponse
    func clearGeneratedData(rescan: Bool) async throws -> GeneratedDataClearResponse
}

public protocol MediaServicing: MediaCatalogServicing, MediaSourceHealthChecking, FamilyMediaAdminServicing {}

public struct MediaService: MediaServicing, MediaPlaybackResolving, MediaTimelineServicing {
    private static let minimumAPIVersion = 2
    private static let requiredCapabilities: Set<String> = [
        "folder_browse",
        "generated_data_clear",
        "browse_sort"
    ]
    private let configurationProvider: any ServerConfigurationProviding
    private let httpClient: any HTTPClient

    public init(
        configurationProvider: any ServerConfigurationProviding,
        httpClient: any HTTPClient = MediaNetworkSession.shared
    ) {
        self.configurationProvider = configurationProvider
        self.httpClient = httpClient
    }

    public func fetchMedia(filter: MediaFilter, request: MediaPageRequest = MediaPageRequest()) async throws -> MediaPage {
        try await fetchMedia(containerID: nil, filter: filter, request: request)
    }

    public func fetchMedia(
        containerID: String?,
        filter: MediaFilter,
        request: MediaPageRequest = MediaPageRequest()
    ) async throws -> MediaPage {
        let endpoint = APIEndpoint.browse(
            containerID: containerID,
            filter: filter,
            request: request
        )
        let revision = configurationProvider.configurationRevision
        let result: MediaPage = try await apiClient().get(
            endpoint.path,
            queryItems: endpoint.queryItems
        )
        try validateConfiguration(revision)
        return result
    }

    public func resolvePlayback(for item: MediaItem) async throws -> MediaPlaybackResolution {
        MediaPlaybackResolution(url: item.url, method: .directPlay)
    }

    public func supportsTimeline() async -> Bool {
        guard let status = try? await checkHealth() else { return false }
        let capabilities = Set(status.capabilities)
        return capabilities.contains("timeline_index") && capabilities.contains("timeline_browse")
    }

    public func fetchTimelineIndex(request: MediaTimelineRequest) async throws -> MediaTimelineIndex {
        let endpoint = APIEndpoint.timelineIndex(request: request)
        let revision = configurationProvider.configurationRevision
        let result: MediaTimelineIndex = try await apiClient().get(endpoint.path, queryItems: endpoint.queryItems)
        try validateConfiguration(revision)
        return result
    }

    public func fetchTimelineMonth(
        key: String,
        request: MediaTimelineRequest,
        page: MediaPageRequest
    ) async throws -> MediaPage {
        let endpoint = APIEndpoint.timelineMonth(key: key, request: request, page: page)
        let revision = configurationProvider.configurationRevision
        let result: MediaPage = try await apiClient().get(endpoint.path, queryItems: endpoint.queryItems)
        try validateConfiguration(revision)
        return result
    }

    public func checkHealth() async throws -> HealthStatus {
        let revision = configurationProvider.configurationRevision
        let result: HealthStatus = try await apiClient().get(APIEndpoint.health.path)
        try validateConfiguration(revision)
        guard let apiVersion = result.apiVersion,
              apiVersion >= Self.minimumAPIVersion,
              Self.requiredCapabilities.isSubset(of: Set(result.capabilities))
        else {
            throw FamilyMediaCompatibilityError.serverUpdateRequired
        }
        return result
    }

    public func triggerScan() async throws -> ScanTriggerResponse {
        let revision = configurationProvider.configurationRevision
        let result: ScanTriggerResponse = try await apiClient().post(APIEndpoint.triggerScan.path)
        try validateConfiguration(revision)
        return result
    }

    public func fetchScanStatus() async throws -> ScanStatus {
        let revision = configurationProvider.configurationRevision
        let result: ScanStatus = try await apiClient().get(APIEndpoint.scanStatus.path)
        try validateConfiguration(revision)
        return result
    }

    public func clearGeneratedData(rescan: Bool) async throws -> GeneratedDataClearResponse {
        let revision = configurationProvider.configurationRevision
        let result: GeneratedDataClearResponse = try await apiClient().post(
            APIEndpoint.clearGeneratedData.path,
            body: GeneratedDataClearRequest(rescan: rescan)
        )
        try validateConfiguration(revision)
        return result
    }

    public func regenerateThumbnail(
        mediaID: String,
        request: ThumbnailRegenerationRequest = ThumbnailRegenerationRequest()
    ) async throws -> ThumbnailRegenerationResponse {
        let endpoint = APIEndpoint.regenerateThumbnail(mediaID: mediaID)
        let revision = configurationProvider.configurationRevision
        let result: ThumbnailRegenerationResponse = try await apiClient().post(
            endpoint.path,
            body: request
        )
        try validateConfiguration(revision)
        return result
    }

    private func apiClient() -> APIClient {
        APIClient(
            configuration: APIConfiguration(baseURL: configurationProvider.serverBaseURL),
            httpClient: httpClient
        )
    }

    private func validateConfiguration(_ expectedRevision: UInt64) throws {
        try Task.checkCancellation()
        guard configurationProvider.configurationRevision == expectedRevision else {
            throw CancellationError()
        }
    }
}
