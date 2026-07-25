import Combine
import Foundation

public final class MediaLibraryRefreshCenter: ObservableObject {
    @MainActor
    @Published public private(set) var generation = 0

    public init() {}

    @MainActor
    public func publishRefresh() {
        generation += 1
    }
}
