import Foundation
import Network

enum NetworkPathConnectionState: Hashable, Sendable {
    case satisfied
    case requiresConnection
    case unsatisfied
}

struct NetworkPathSnapshot: Hashable, Sendable {
    let state: NetworkPathConnectionState
    let usesWiFi: Bool
    let usesWiredEthernet: Bool
    let usesCellular: Bool
    let isExpensive: Bool
    let isConstrained: Bool

    init(
        state: NetworkPathConnectionState,
        usesWiFi: Bool = false,
        usesWiredEthernet: Bool = false,
        usesCellular: Bool = false,
        isExpensive: Bool = false,
        isConstrained: Bool = false
    ) {
        self.state = state
        self.usesWiFi = usesWiFi
        self.usesWiredEthernet = usesWiredEthernet
        self.usesCellular = usesCellular
        self.isExpensive = isExpensive
        self.isConstrained = isConstrained
    }

    init(path: NWPath) {
        switch path.status {
        case .satisfied:
            state = .satisfied
        case .requiresConnection:
            state = .requiresConnection
        case .unsatisfied:
            state = .unsatisfied
        @unknown default:
            state = .unsatisfied
        }
        usesWiFi = path.usesInterfaceType(.wifi)
        usesWiredEthernet = path.usesInterfaceType(.wiredEthernet)
        usesCellular = path.usesInterfaceType(.cellular)
        isExpensive = path.isExpensive
        isConstrained = path.isConstrained
    }
}

protocol NetworkPathMonitoring: Sendable {
    func setUpdateHandler(
        _ handler: @escaping @Sendable (NetworkPathSnapshot) -> Void
    )
    func start()
    func cancel()
}

private final class SystemNetworkPathMonitor: NetworkPathMonitoring, @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "Jiaying.NetworkPathMonitor")

    func setUpdateHandler(
        _ handler: @escaping @Sendable (NetworkPathSnapshot) -> Void
    ) {
        monitor.pathUpdateHandler = { path in
            handler(NetworkPathSnapshot(path: path))
        }
    }

    func start() {
        monitor.start(queue: queue)
    }

    func cancel() {
        monitor.cancel()
    }
}

@MainActor
final class NetworkRecoveryObserver: ObservableObject {
    @Published private(set) var generation = 0

    private let monitor: any NetworkPathMonitoring
    private let debounceDuration: Duration
    private var lastSnapshot: NetworkPathSnapshot?
    private var handledGeneration = 0
    private var pendingChangeTask: Task<Void, Never>?

    init(
        monitor: any NetworkPathMonitoring = SystemNetworkPathMonitor(),
        debounceDuration: Duration = .milliseconds(750)
    ) {
        self.monitor = monitor
        self.debounceDuration = debounceDuration
        monitor.setUpdateHandler { [weak self] snapshot in
            Task { @MainActor [weak self] in
                self?.receive(snapshot)
            }
        }
        monitor.start()
    }

    deinit {
        pendingChangeTask?.cancel()
        monitor.cancel()
    }

    /// Returns true once for each debounced path change. Callers intentionally
    /// avoid consuming while inactive so a background change is handled on the
    /// next foreground transition.
    func consumePendingChange() -> Bool {
        guard handledGeneration != generation else { return false }
        handledGeneration = generation
        return true
    }

    private func receive(_ snapshot: NetworkPathSnapshot) {
        guard let lastSnapshot else {
            self.lastSnapshot = snapshot
            return
        }
        guard snapshot != lastSnapshot else { return }

        self.lastSnapshot = snapshot
        pendingChangeTask?.cancel()
        pendingChangeTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: debounceDuration)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            generation &+= 1
            pendingChangeTask = nil
        }
    }
}
