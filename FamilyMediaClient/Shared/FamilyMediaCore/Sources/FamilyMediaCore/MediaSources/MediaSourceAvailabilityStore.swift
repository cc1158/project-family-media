import Foundation

public enum MediaSourceAvailability: Equatable, Sendable {
    case unchecked
    case checking
    case available(String)
    case authenticationRequired
    case updateRequired(String)
    case unavailable(String)

    public var canBrowse: Bool {
        switch self {
        case .authenticationRequired, .updateRequired:
            false
        case .unchecked, .checking, .available, .unavailable:
            true
        }
    }

    public var shortTitle: String {
        switch self {
        case .unchecked: "等待检查"
        case .checking: "正在检查"
        case .available(let detail): detail
        case .authenticationRequired: "需要登录"
        case .updateRequired: "需要更新服务端"
        case .unavailable: "暂时无法连接"
        }
    }

    public var systemImage: String {
        switch self {
        case .unchecked, .checking: "arrow.triangle.2.circlepath"
        case .available: "checkmark.circle.fill"
        case .authenticationRequired: "person.crop.circle.badge.exclamationmark"
        case .updateRequired: "arrow.down.circle.fill"
        case .unavailable: "wifi.exclamationmark"
        }
    }
}

@MainActor
public final class MediaSourceAvailabilityStore: ObservableObject {
    public static let foregroundRefreshInterval: TimeInterval = 30

    @Published public private(set) var familyMedia: MediaSourceAvailability = .unchecked
    @Published public private(set) var jellyfin: MediaSourceAvailability = .unchecked
    @Published public private(set) var isRefreshing = false

    private let registry: MediaSourceRegistry
    private let sourceRefreshCenter: MediaSourceRefreshCenter?
    private let now: () -> Date
    private var lastCompletedRefresh: Date?
    private var needsAnotherRefresh = false

    public init(
        registry: MediaSourceRegistry,
        sourceRefreshCenter: MediaSourceRefreshCenter? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.registry = registry
        self.sourceRefreshCenter = sourceRefreshCenter
        self.now = now
        familyMedia = Self.initialState(for: registry.familyMedia)
        jellyfin = Self.initialState(for: registry.jellyfin)
    }

    public func refresh() async {
        guard !isRefreshing else {
            needsAnotherRefresh = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        repeat {
            needsAnotherRefresh = false
            if await performRefresh() {
                lastCompletedRefresh = now()
            }
        } while needsAnotherRefresh && !Task.isCancelled
    }

    private func performRefresh() async -> Bool {
        let jellyfinWasReady = registry.jellyfin.readiness == .ready
        familyMedia = Self.initialState(for: registry.familyMedia)
        jellyfin = Self.initialState(for: registry.jellyfin)

        async let familyResult = Self.resolve(registry.familyMedia)
        async let jellyfinResult = Self.resolve(registry.jellyfin)
        let (resolvedFamily, resolvedJellyfin) = await (familyResult, jellyfinResult)
        familyMedia = resolvedFamily.availability
        jellyfin = resolvedJellyfin.availability

        guard resolvedFamily.didComplete,
              resolvedJellyfin.didComplete,
              !Task.isCancelled
        else { return false }

        if jellyfinWasReady,
           registry.jellyfin.readiness == .authenticationRequired {
            sourceRefreshCenter?.publishRefresh(for: .jellyfin)
        }
        return true
    }

    /// Rechecks sources after a meaningful period away without hammering a NAS
    /// during short Control Center, notification, or app-switch interruptions.
    public func refreshAfterForegroundIfNeeded(
        minimumInterval: TimeInterval = foregroundRefreshInterval
    ) async {
        guard let lastCompletedRefresh else {
            await refresh()
            return
        }
        guard now().timeIntervalSince(lastCompletedRefresh) >= minimumInterval else { return }
        await refresh()
    }

    public func availability(for sourceID: MediaSourceID) -> MediaSourceAvailability {
        switch sourceID {
        case .familyMedia: familyMedia
        case .jellyfin: jellyfin
        }
    }

    private nonisolated static func initialState(
        for context: MediaSourceContext
    ) -> MediaSourceAvailability {
        context.readiness == .authenticationRequired ? .authenticationRequired : .checking
    }

    private nonisolated static func resolve(_ context: MediaSourceContext) async -> SourceResolution {
        guard context.readiness == .ready else {
            return SourceResolution(availability: .authenticationRequired, didComplete: true)
        }
        guard let healthChecker = context.healthChecker else {
            return SourceResolution(availability: .available("可用"), didComplete: true)
        }

        do {
            let status = try await healthChecker.checkHealth()
            return SourceResolution(
                availability: status.status == "ok"
                    ? .available("可用")
                    : .available("服务可访问，部分能力异常"),
                didComplete: true
            )
        } catch let error where TaskCancellation.matches(error) {
            return SourceResolution(availability: .unchecked, didComplete: false)
        } catch let error as FamilyMediaCompatibilityError {
            return SourceResolution(
                availability: .updateRequired(AppErrorMapper.message(for: error)),
                didComplete: true
            )
        } catch {
            if context.readiness == .authenticationRequired {
                return SourceResolution(availability: .authenticationRequired, didComplete: true)
            }
            return SourceResolution(
                availability: .unavailable(AppErrorMapper.message(for: error)),
                didComplete: true
            )
        }
    }
}

private struct SourceResolution: Sendable {
    let availability: MediaSourceAvailability
    let didComplete: Bool
}
