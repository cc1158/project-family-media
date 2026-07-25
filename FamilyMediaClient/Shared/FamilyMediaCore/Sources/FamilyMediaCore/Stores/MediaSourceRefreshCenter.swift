import Combine
import Foundation

/// Broadcasts changes that can alter whether a configured media source is ready
/// or reachable. It is intentionally separate from library-content refreshes.
public final class MediaSourceRefreshCenter: ObservableObject, @unchecked Sendable {
    @MainActor
    @Published public private(set) var generation = 0
    @MainActor
    public private(set) var affectedSourceID: MediaSourceID?

    public init() {}

    @MainActor
    public func publishRefresh(for sourceID: MediaSourceID? = nil) {
        affectedSourceID = sourceID
        generation &+= 1
    }

    @MainActor
    public func affectsNavigation(for activeSourceID: MediaSourceID?) -> Bool {
        guard let affectedSourceID else { return true }
        return affectedSourceID.rawValue == activeSourceID?.rawValue
    }
}
