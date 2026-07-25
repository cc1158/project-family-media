import Foundation

public enum MediaBrowseMode: String, CaseIterable, Codable, Sendable {
    case directory
    case month
    case year

    public var title: String {
        switch self {
        case .directory: "目录"
        case .month: "月份"
        case .year: "年份"
        }
    }
}

public enum MediaTimelineDirection: String, Codable, CaseIterable, Sendable {
    case newest = "captured_desc"
    case oldest = "captured_asc"

    public var title: String { self == .newest ? "最新在前" : "最早在前" }
}

public struct MediaTimelineIndex: Codable, Equatable, Sendable {
    public let dateSemantics: String
    public let timeZone: String
    public let years: [MediaTimelineYear]

    public init(dateSemantics: String, timeZone: String, years: [MediaTimelineYear]) {
        self.dateSemantics = dateSemantics
        self.timeZone = timeZone
        self.years = years
    }
}

public struct MediaTimelineYear: Codable, Equatable, Identifiable, Sendable {
    public let key: String
    public let count: Int
    public let coverThumbnailURLs: [URL]
    public let months: [MediaTimelineMonth]
    public var id: String { key }

    public init(key: String, count: Int, coverThumbnailURLs: [URL] = [], months: [MediaTimelineMonth]) {
        self.key = key
        self.count = count
        self.coverThumbnailURLs = coverThumbnailURLs
        self.months = months
    }
}

public struct MediaTimelineMonth: Codable, Equatable, Identifiable, Sendable {
    public let key: String
    public let count: Int
    public let coverThumbnailURLs: [URL]
    public var id: String { key }

    public init(key: String, count: Int, coverThumbnailURLs: [URL] = []) {
        self.key = key
        self.count = count
        self.coverThumbnailURLs = coverThumbnailURLs
    }

    public var title: String {
        let parts = key.split(separator: "-")
        guard parts.count == 2, let month = Int(parts[1]) else { return key }
        return "\(parts[0])年\(month)月"
    }
}

public struct MediaTimelineRequest: Equatable, Sendable {
    public let containerID: String?
    public let filter: MediaFilter
    public let timeZone: String
    public let direction: MediaTimelineDirection

    public init(containerID: String?, filter: MediaFilter, timeZone: String, direction: MediaTimelineDirection) {
        self.containerID = containerID
        self.filter = filter
        self.timeZone = timeZone
        self.direction = direction
    }
}
