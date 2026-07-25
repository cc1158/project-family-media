import Foundation

struct JellyfinCatalogService: MediaCatalogServicing {
    private static let sharedContainerTypes = [
        "CollectionFolder",
        "Folder"
    ]
    private static let videoContainerTypes = [
        "Series",
        "Season",
        "BoxSet"
    ]
    private static let photoContainerTypes = [
        "PhotoAlbum"
    ]
    private static let playlistContainerTypes = [
        "Playlist",
        "PlaylistsFolder"
    ]
    private static let supportedContainerTypes = Set(
        sharedContainerTypes
            + videoContainerTypes
            + photoContainerTypes
            + playlistContainerTypes
    )

    let api: JellyfinAPIClient

    func fetchMedia(filter: MediaFilter, request: MediaPageRequest) async throws -> MediaPage {
        try await fetchMedia(containerID: nil, filter: filter, request: request)
    }

    func fetchMedia(containerID: String?, filter: MediaFilter, request: MediaPageRequest) async throws -> MediaPage {
        guard let session = api.currentSession else { throw JellyfinError.notAuthenticated }
        let offset = Int(request.cursor ?? "0") ?? 0
        let container = containerID.map(JellyfinContainerReference.init)
        let path: String
        var query: [URLQueryItem] = []

        switch container {
        case nil:
            path = "Users/\(session.userID)/Views"
        case .playlist(let playlistID):
            path = "Playlists/\(playlistID)/Items"
            query = [URLQueryItem(name: "UserId", value: session.userID)]
        case .items(let itemID):
            path = "Users/\(session.userID)/Items"
            query = [
                URLQueryItem(name: "ParentId", value: itemID),
                URLQueryItem(name: "Recursive", value: "false"),
                URLQueryItem(name: "IncludeItemTypes", value: includedTypes(for: filter))
            ]
        }
        query += [
            URLQueryItem(name: "StartIndex", value: String(offset)),
            URLQueryItem(name: "Limit", value: String(request.limit))
        ]
        if container == nil {
            query += [
                URLQueryItem(name: "SortBy", value: "SortName"),
                URLQueryItem(name: "SortOrder", value: "Ascending")
            ]
        } else if !container.isPlaylist {
            query += jellyfinSortQuery(for: request.sort ?? .nameAscending)
        }
        let response: JellyfinItemsResponse = try await api.send(path: path, queryItems: query)
        let items = response.Items.compactMap(map)
        let next = offset + response.Items.count
        let hasMore = next < response.TotalRecordCount
        return MediaPage(items: items, nextCursor: hasMore ? String(next) : "", hasMore: hasMore)
    }

    private func jellyfinSortQuery(for sort: MediaSortOption) -> [URLQueryItem] {
        let field: String
        let order: String
        switch sort {
        case .nameAscending:
            field = "SortName"
            order = "Ascending"
        case .nameDescending:
            field = "SortName"
            order = "Descending"
        case .dateAddedOldest, .capturedOldest:
            field = "DateCreated"
            order = "Ascending"
        case .dateAddedNewest, .capturedNewest:
            field = "DateCreated"
            order = "Descending"
        }
        return [
            URLQueryItem(name: "SortBy", value: field),
            URLQueryItem(name: "SortOrder", value: order)
        ]
    }

    private func map(_ item: JellyfinItem) -> MediaItem? {
        let isContainer = item.IsFolder == true || Self.supportedContainerTypes.contains(item.Type ?? "")
        let kind: MediaKind
        switch item.Type {
        case "Photo": kind = .photo
        case "Movie", "Episode", "Video": kind = .video
        default:
            guard isContainer else { return nil }
            kind = .photo
        }
        guard let resourceURL = resourceURL(for: item, kind: kind, isContainer: isContainer) else { return nil }
        let imageURL = item.ImageTags?["Primary"].flatMap { tag in
            api.makeURL(path: "Items/\(item.Id)/Images/Primary", query: [
                URLQueryItem(name: "maxWidth", value: "600"),
                URLQueryItem(name: "quality", value: "85"),
                URLQueryItem(name: "tag", value: tag)
            ])
        }
        return MediaItem(
            id: "jellyfin:\(item.Id)", name: item.Name, kind: kind, size: item.Size ?? 0,
            modified: parseDate(item.DateCreated) ?? .distantPast, url: resourceURL,
            thumbnailURL: imageURL, mediaPath: item.Id,
            thumbnailStatus: imageURL == nil ? .failed : .ready,
            sourceID: .jellyfin,
            containerID: containerIdentifier(for: item),
            isContainer: isContainer
        )
    }

    private func containerIdentifier(for item: JellyfinItem) -> String {
        item.Type == "Playlist"
            ? JellyfinContainerReference.playlist(item.Id).identifier
            : item.Id
    }

    private func resourceURL(for item: JellyfinItem, kind: MediaKind, isContainer: Bool) -> URL? {
        if isContainer { return api.configuration.serverBaseURL }
        let path = kind == .video ? "Videos/\(item.Id)/stream" : "Items/\(item.Id)/Images/Primary"
        let query = kind == .video ? [URLQueryItem(name: "static", value: "true")] : []
        return api.makeURL(path: path, query: query)
    }

    private func includedTypes(for filter: MediaFilter) -> String {
        switch filter {
        case .all:
            return (
                Self.sharedContainerTypes
                    + Self.videoContainerTypes
                    + Self.photoContainerTypes
                    + Self.playlistContainerTypes
                    + ["Movie", "Episode", "Video", "Photo"]
            ).joined(separator: ",")
        case .photos:
            return (
                Self.sharedContainerTypes
                    + Self.photoContainerTypes
                    + ["Photo"]
            ).joined(separator: ",")
        case .videos:
            return (
                Self.sharedContainerTypes
                    + Self.videoContainerTypes
                    + ["Movie", "Episode", "Video"]
            ).joined(separator: ",")
        }
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

private enum JellyfinContainerReference {
    private static let playlistPrefix = "playlist:"

    case items(String)
    case playlist(String)

    init(_ identifier: String) {
        if identifier.hasPrefix(Self.playlistPrefix) {
            self = .playlist(String(identifier.dropFirst(Self.playlistPrefix.count)))
        } else {
            self = .items(identifier)
        }
    }

    var identifier: String {
        switch self {
        case .items(let itemID): itemID
        case .playlist(let playlistID): Self.playlistPrefix + playlistID
        }
    }
}

private extension Optional where Wrapped == JellyfinContainerReference {
    var isPlaylist: Bool {
        guard case .some(.playlist) = self else { return false }
        return true
    }
}
