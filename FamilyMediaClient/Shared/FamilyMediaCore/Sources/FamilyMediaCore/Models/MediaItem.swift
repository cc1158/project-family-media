import Foundation

public enum MediaKind: String, Codable, Sendable {
    case video
    case photo
}

public enum ThumbnailStatus: String, Codable, Sendable {
    case pending
    case ready
    case failed
}

public enum MediaFilter: Equatable, Sendable {
    case all
    case photos
    case videos
}

public enum MediaSourceID: String, Codable, Sendable {
    case familyMedia
    case jellyfin
}

public struct MediaItem: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let kind: MediaKind
    public let size: Int64
    public let modified: Date
    public let capturedAt: Date?
    public let timelineDate: Date?
    public let url: URL
    public let thumbnailURL: URL?
    public let mediaPath: String
    public let thumbnailStatus: ThumbnailStatus
    public let sourceID: MediaSourceID
    public let containerID: String?
    public let isContainer: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case kind
        case size
        case modified
        case capturedAt
        case timelineDate
        case url
        case thumbnailURL
        case mediaPath
        case thumbnailStatus
        case sourceID
        case containerID
        case isContainer
    }

    public init(
        id: String,
        name: String,
        kind: MediaKind,
        size: Int64,
        modified: Date,
        capturedAt: Date? = nil,
        timelineDate: Date? = nil,
        url: URL,
        thumbnailURL: URL? = nil,
        mediaPath: String,
        thumbnailStatus: ThumbnailStatus,
        sourceID: MediaSourceID = .familyMedia,
        containerID: String? = nil,
        isContainer: Bool = false
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.size = size
        self.modified = modified
        self.capturedAt = capturedAt
        self.timelineDate = timelineDate
        self.url = url
        self.thumbnailURL = thumbnailURL
        self.mediaPath = mediaPath
        self.thumbnailStatus = thumbnailStatus
        self.sourceID = sourceID
        self.containerID = containerID
        self.isContainer = isContainer
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        kind = try container.decode(MediaKind.self, forKey: .kind)
        size = try container.decode(Int64.self, forKey: .size)
        modified = try container.decode(Date.self, forKey: .modified)
        capturedAt = try container.decodeIfPresent(Date.self, forKey: .capturedAt)
        timelineDate = try container.decodeIfPresent(Date.self, forKey: .timelineDate)
        url = try container.decode(URL.self, forKey: .url)
        mediaPath = try container.decode(String.self, forKey: .mediaPath)
        thumbnailStatus = try container.decode(ThumbnailStatus.self, forKey: .thumbnailStatus)
        sourceID = try container.decodeIfPresent(MediaSourceID.self, forKey: .sourceID) ?? .familyMedia
        containerID = try container.decodeIfPresent(String.self, forKey: .containerID)
        isContainer = try container.decodeIfPresent(Bool.self, forKey: .isContainer) ?? false

        if let thumbnail = try container.decodeIfPresent(String.self, forKey: .thumbnailURL), !thumbnail.isEmpty {
            thumbnailURL = URL(string: thumbnail)
        } else {
            thumbnailURL = nil
        }
    }

    public var displayTitle: String {
        name
    }

    public var readyThumbnailURL: URL? {
        thumbnailStatus == .ready ? thumbnailURL : nil
    }
}

public struct MediaPage: Codable, Equatable, Sendable {
    public let items: [MediaItem]
    public let nextCursor: String
    public let hasMore: Bool

    public init(items: [MediaItem], nextCursor: String = "", hasMore: Bool = false) {
        self.items = items
        self.nextCursor = nextCursor
        self.hasMore = hasMore
    }
}

public struct MediaPageRequest: Equatable, Sendable {
    public let limit: Int
    public let cursor: String?
    public let sort: MediaSortOption?

    public init(limit: Int = 50, cursor: String? = nil, sort: MediaSortOption? = nil) {
        self.limit = limit
        self.cursor = cursor
        self.sort = sort
    }

    public var queryItems: [URLQueryItem] {
        var items = [URLQueryItem(name: "limit", value: String(limit))]

        if let cursor, !cursor.isEmpty {
            items.append(URLQueryItem(name: "cursor", value: cursor))
        }

        if let sort {
            items.append(URLQueryItem(name: "sort", value: sort.rawValue))
        }

        return items
    }
}
