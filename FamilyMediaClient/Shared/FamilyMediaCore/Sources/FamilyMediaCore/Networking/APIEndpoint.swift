import Foundation

struct APIEndpoint: Equatable, Sendable {
    let path: String
    let queryItems: [URLQueryItem]

    init(path: String, queryItems: [URLQueryItem] = []) {
        self.path = path
        self.queryItems = queryItems
    }

    static func media(filter: MediaFilter, request: MediaPageRequest) -> APIEndpoint {
        APIEndpoint(path: filter.path, queryItems: request.queryItems)
    }

    static func browse(
        containerID: String?,
        filter: MediaFilter,
        request: MediaPageRequest
    ) -> APIEndpoint {
        var queryItems = request.queryItems
        if let kind = filter.kindQueryValue {
            queryItems.append(URLQueryItem(name: "kind", value: kind))
        }
        if let containerID, !containerID.isEmpty {
            queryItems.append(URLQueryItem(name: "containerID", value: containerID))
        }
        return APIEndpoint(path: "/api/v1/browse", queryItems: queryItems)
    }

    static let health = APIEndpoint(path: "/healthz")

    static func timelineIndex(request: MediaTimelineRequest) -> APIEndpoint {
        APIEndpoint(path: "/api/v1/timeline/index", queryItems: timelineQueryItems(request))
    }

    static func timelineMonth(
        key: String,
        request: MediaTimelineRequest,
        page: MediaPageRequest
    ) -> APIEndpoint {
        var items = page.queryItems.filter { $0.name != "sort" }
        items.append(contentsOf: timelineQueryItems(request))
        items.append(URLQueryItem(name: "scope", value: "recursive"))
        items.append(URLQueryItem(name: "bucket", value: key))
        return APIEndpoint(path: "/api/v1/browse", queryItems: items)
    }

    private static func timelineQueryItems(_ request: MediaTimelineRequest) -> [URLQueryItem] {
        var items = [
            URLQueryItem(name: "timeZone", value: request.timeZone),
            URLQueryItem(name: "sort", value: request.direction.rawValue)
        ]
        if let kind = request.filter.kindQueryValue {
            items.append(URLQueryItem(name: "kind", value: kind))
        }
        if let containerID = request.containerID, !containerID.isEmpty {
            items.append(URLQueryItem(name: "containerID", value: containerID))
        }
        return items
    }
    static let triggerScan = APIEndpoint(path: "/api/v1/admin/scan")
    static let scanStatus = APIEndpoint(path: "/api/v1/admin/scan/status")
    static let clearGeneratedData = APIEndpoint(path: "/api/v1/admin/data/clear")

    static func regenerateThumbnail(mediaID: String) -> APIEndpoint {
        APIEndpoint(path: "/api/v1/admin/media/\(mediaID.asPathSegment)/thumbnail/regenerate")
    }
}

private extension MediaFilter {
    var kindQueryValue: String? {
        switch self {
        case .all: nil
        case .photos: MediaKind.photo.rawValue
        case .videos: MediaKind.video.rawValue
        }
    }

    var path: String {
        switch self {
        case .all:
            return "/api/v1/media"
        case .photos:
            return "/api/v1/photos"
        case .videos:
            return "/api/v1/videos"
        }
    }
}

private extension String {
    var asPathSegment: String {
        let allowedCharacters = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
        return addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? self
    }
}
