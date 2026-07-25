import XCTest
@testable import FamilyMediaiOS

@MainActor
final class NetworkRecoveryObserverTests: XCTestCase {
    func testInitialPathAndDuplicateUpdatesDoNotRequestRecovery() async throws {
        let monitor = NetworkPathMonitorStub()
        let observer = NetworkRecoveryObserver(
            monitor: monitor,
            debounceDuration: .milliseconds(1)
        )
        let wifi = NetworkPathSnapshot(state: .satisfied, usesWiFi: true)

        monitor.emit(wifi)
        monitor.emit(wifi)
        try await Task.sleep(for: .milliseconds(10))

        XCTAssertEqual(observer.generation, 0)
        XCTAssertFalse(observer.consumePendingChange())
    }

    func testMeaningfulPathChangesAreDebouncedIntoOneRecovery() async throws {
        let monitor = NetworkPathMonitorStub()
        let observer = NetworkRecoveryObserver(
            monitor: monitor,
            debounceDuration: .milliseconds(5)
        )

        monitor.emit(NetworkPathSnapshot(state: .satisfied, usesWiFi: true))
        monitor.emit(NetworkPathSnapshot(state: .unsatisfied))
        monitor.emit(
            NetworkPathSnapshot(
                state: .satisfied,
                usesCellular: true,
                isExpensive: true
            )
        )

        try await waitUntil { observer.generation == 1 }
        XCTAssertEqual(observer.generation, 1)
        XCTAssertTrue(observer.consumePendingChange())
        XCTAssertFalse(observer.consumePendingChange())
    }

    func testLaterPathChangeProducesAnotherRecovery() async throws {
        let monitor = NetworkPathMonitorStub()
        let observer = NetworkRecoveryObserver(
            monitor: monitor,
            debounceDuration: .milliseconds(1)
        )

        monitor.emit(NetworkPathSnapshot(state: .satisfied, usesWiFi: true))
        monitor.emit(NetworkPathSnapshot(state: .unsatisfied))
        try await waitUntil { observer.generation == 1 }
        XCTAssertTrue(observer.consumePendingChange())

        monitor.emit(NetworkPathSnapshot(state: .satisfied, usesWiFi: true))
        try await waitUntil { observer.generation == 2 }
        XCTAssertTrue(observer.consumePendingChange())
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("等待网络恢复事件超时")
    }
}

private final class NetworkPathMonitorStub: NetworkPathMonitoring, @unchecked Sendable {
    private var handler: (@Sendable (NetworkPathSnapshot) -> Void)?

    func setUpdateHandler(
        _ handler: @escaping @Sendable (NetworkPathSnapshot) -> Void
    ) {
        self.handler = handler
    }

    func start() {}

    func cancel() {
        handler = nil
    }

    func emit(_ snapshot: NetworkPathSnapshot) {
        handler?(snapshot)
    }
}
