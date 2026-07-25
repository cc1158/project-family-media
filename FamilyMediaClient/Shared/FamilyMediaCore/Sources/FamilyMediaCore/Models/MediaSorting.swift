import Foundation

public enum MediaSortOption: String, Codable, CaseIterable, Equatable, Sendable {
    case capturedNewest = "captured_desc"
    case capturedOldest = "captured_asc"
    case nameAscending = "name_asc"
    case nameDescending = "name_desc"
    case dateAddedNewest = "indexed_desc"
    case dateAddedOldest = "indexed_asc"

    public func title(for _: MediaSourceID) -> String {
        switch self {
        case .capturedNewest: "拍摄时间：最新"
        case .capturedOldest: "拍摄时间：最早"
        case .nameAscending: "名称：正序"
        case .nameDescending: "名称：倒序"
        case .dateAddedNewest: "最近加入"
        case .dateAddedOldest: "最早加入"
        }
    }

    public func compactTitle(for _: MediaSourceID) -> String {
        switch self {
        case .capturedNewest: "最近拍摄"
        case .capturedOldest: "最早拍摄"
        case .nameAscending: "名称正序"
        case .nameDescending: "名称倒序"
        case .dateAddedNewest: "最近加入"
        case .dateAddedOldest: "最早加入"
        }
    }

    public var directionSystemImage: String {
        switch self {
        case .capturedNewest, .nameDescending, .dateAddedNewest:
            "arrow.down"
        case .capturedOldest, .nameAscending, .dateAddedOldest:
            "arrow.up"
        }
    }
}

public struct MediaSortingProfile: Equatable, Sendable {
    public let options: [MediaSortOption]
    public let defaultOption: MediaSortOption
    private let hidesAtRoot: Bool
    private let excludedContainerPrefixes: [String]

    public init(
        options: [MediaSortOption],
        defaultOption: MediaSortOption,
        hidesAtRoot: Bool = false,
        excludedContainerPrefixes: [String] = []
    ) {
        precondition(options.contains(defaultOption), "Default sort must be supported")
        self.options = options
        self.defaultOption = defaultOption
        self.hidesAtRoot = hidesAtRoot
        self.excludedContainerPrefixes = excludedContainerPrefixes
    }

    public func isAvailable(containerID: String?) -> Bool {
        if hidesAtRoot, containerID == nil { return false }
        guard let containerID else { return true }
        return !excludedContainerPrefixes.contains { containerID.hasPrefix($0) }
    }

    public static let familyMedia = MediaSortingProfile(
        options: [.capturedNewest, .capturedOldest, .nameAscending, .nameDescending, .dateAddedNewest],
        defaultOption: .capturedNewest
    )

    public static let jellyfin = MediaSortingProfile(
        options: [.dateAddedNewest, .dateAddedOldest, .nameAscending, .nameDescending],
        defaultOption: .nameAscending,
        hidesAtRoot: true,
        excludedContainerPrefixes: ["playlist:"]
    )

    public static func standard(for sourceID: MediaSourceID) -> MediaSortingProfile {
        sourceID == .familyMedia ? .familyMedia : .jellyfin
    }
}

@MainActor
public final class MediaSortPreferenceStore {
    private let defaults: UserDefaults
    private let keyPrefix: String

    public init(defaults: UserDefaults = .standard, keyPrefix: String = "media.sort") {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    public func selectedSort(
        sourceID: MediaSourceID,
        filter: MediaFilter,
        profile: MediaSortingProfile
    ) -> MediaSortOption {
        guard
            let rawValue = defaults.string(forKey: key(sourceID: sourceID, filter: filter)),
            let value = MediaSortOption(rawValue: rawValue),
            profile.options.contains(value)
        else {
            return profile.defaultOption
        }
        return value
    }

    public func save(_ option: MediaSortOption, sourceID: MediaSourceID, filter: MediaFilter) {
        defaults.set(option.rawValue, forKey: key(sourceID: sourceID, filter: filter))
    }

    private func key(sourceID: MediaSourceID, filter: MediaFilter) -> String {
        "\(keyPrefix).\(sourceID.rawValue).\(filter.preferenceKey)"
    }
}

private extension MediaFilter {
    var preferenceKey: String {
        switch self {
        case .all: "all"
        case .photos: "photos"
        case .videos: "videos"
        }
    }
}
