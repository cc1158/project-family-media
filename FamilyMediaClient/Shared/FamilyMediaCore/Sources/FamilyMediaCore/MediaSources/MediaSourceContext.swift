import Foundation

public struct MediaResourceRequest: Sendable {
    public let request: URLRequest
    public let cachePartition: String
    private let unauthorizedResponseHandler: (@Sendable () -> Void)?

    public init(
        request: URLRequest,
        cachePartition: String = "public",
        unauthorizedResponseHandler: (@Sendable () -> Void)? = nil
    ) {
        self.request = request
        self.cachePartition = cachePartition
        self.unauthorizedResponseHandler = unauthorizedResponseHandler
    }

    public static func unauthenticated(url: URL) -> MediaResourceRequest {
        MediaResourceRequest(request: URLRequest(url: url))
    }

    public func handleUnauthorizedResponse() {
        unauthorizedResponseHandler?()
    }
}

public protocol MediaResourceRequestAuthorizing: Sendable {
    func resourceRequest(for url: URL) -> MediaResourceRequest
}

public enum MediaSourceReadiness: Equatable, Sendable {
    case ready
    case authenticationRequired
}

public enum MediaCatalogStructure: Equatable, Sendable {
    case folderTree
    case libraryRoot
}

public struct MediaSourceContext: Sendable {
    public let id: MediaSourceID
    public let catalog: any MediaCatalogServicing
    public let timeline: (any MediaTimelineServicing)?
    public let playbackResolver: any MediaPlaybackResolving
    public let playbackReporter: (any MediaPlaybackReporting)?
    public let admin: (any FamilyMediaAdminServicing)?
    public let healthChecker: (any MediaSourceHealthChecking)?
    public let resourceRequestAuthorizer: (any MediaResourceRequestAuthorizing)?
    public let sortingProfile: MediaSortingProfile
    public let catalogStructure: MediaCatalogStructure
    private let readinessProvider: @Sendable () -> MediaSourceReadiness

    public init(
        id: MediaSourceID,
        catalog: any MediaCatalogServicing,
        timeline: (any MediaTimelineServicing)? = nil,
        playbackResolver: any MediaPlaybackResolving,
        playbackReporter: (any MediaPlaybackReporting)? = nil,
        admin: (any FamilyMediaAdminServicing)? = nil,
        healthChecker: (any MediaSourceHealthChecking)? = nil,
        resourceRequestAuthorizer: (any MediaResourceRequestAuthorizing)? = nil,
        sortingProfile: MediaSortingProfile? = nil,
        catalogStructure: MediaCatalogStructure = .folderTree,
        readiness: @escaping @Sendable () -> MediaSourceReadiness = { .ready }
    ) {
        self.id = id
        self.catalog = catalog
        self.timeline = timeline
        self.playbackResolver = playbackResolver
        self.playbackReporter = playbackReporter
        self.admin = admin
        self.healthChecker = healthChecker
        self.resourceRequestAuthorizer = resourceRequestAuthorizer
        self.sortingProfile = sortingProfile ?? .standard(for: id)
        self.catalogStructure = catalogStructure
        self.readinessProvider = readiness
    }

    public var readiness: MediaSourceReadiness { readinessProvider() }
}

public struct MediaSourceRegistry: Sendable {
    public let familyMedia: MediaSourceContext
    public let jellyfin: MediaSourceContext

    public init(familyMedia: MediaSourceContext, jellyfin: MediaSourceContext) {
        self.familyMedia = familyMedia
        self.jellyfin = jellyfin
    }
}
