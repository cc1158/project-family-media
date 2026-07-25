import Foundation

@MainActor
public final class MediaTimelinePreferenceStore {
    private let defaults: UserDefaults
    private let modeKey: String
    private let directionKey: String

    public init(
        sourceID: MediaSourceID,
        filter: MediaFilter,
        defaults: UserDefaults = .standard
    ) {
        self.defaults = defaults
        let scope = "\(sourceID.rawValue).\(Self.filterKey(filter))"
        modeKey = "media.browseMode.\(scope)"
        directionKey = "media.timelineDirection.\(scope)"
    }

    public var mode: MediaBrowseMode {
        guard
            let rawValue = defaults.string(forKey: modeKey),
            let value = MediaBrowseMode(rawValue: rawValue)
        else { return .directory }
        return value
    }

    public var direction: MediaTimelineDirection {
        guard
            let rawValue = defaults.string(forKey: directionKey),
            let value = MediaTimelineDirection(rawValue: rawValue)
        else { return .newest }
        return value
    }

    public func save(mode: MediaBrowseMode) {
        defaults.set(mode.rawValue, forKey: modeKey)
    }

    public func save(direction: MediaTimelineDirection) {
        defaults.set(direction.rawValue, forKey: directionKey)
    }

    private static func filterKey(_ filter: MediaFilter) -> String {
        switch filter {
        case .all: "all"
        case .photos: "photos"
        case .videos: "videos"
        }
    }
}
