import Foundation
import Testing
@testable import FamilyMediaCore

@MainActor
struct MediaSourceAvailabilityStoreTests {
    @Test func initialStateBlocksSignedOutJellyfinBeforeNetworkRefreshStarts() {
        let familyService = FakeMediaService()
        let jellyfinService = FakeMediaService()
        let registry = MediaSourceRegistry(
            familyMedia: context(id: .familyMedia, service: familyService),
            jellyfin: context(
                id: .jellyfin,
                service: jellyfinService,
                readiness: { .authenticationRequired }
            )
        )

        let store = MediaSourceAvailabilityStore(registry: registry)

        #expect(store.familyMedia == .checking)
        #expect(store.familyMedia.canBrowse)
        #expect(store.jellyfin == .authenticationRequired)
        #expect(!store.jellyfin.canBrowse)
        #expect(familyService.healthCheckCount == 0)
        #expect(jellyfinService.healthCheckCount == 0)
    }

    @Test func refreshReportsHealthySourcesAndAuthenticationRequirement() async {
        let familyService = FakeMediaService()
        let jellyfinService = FakeMediaService()
        let registry = MediaSourceRegistry(
            familyMedia: context(id: .familyMedia, service: familyService),
            jellyfin: context(
                id: .jellyfin,
                service: jellyfinService,
                readiness: { .authenticationRequired }
            )
        )
        let store = MediaSourceAvailabilityStore(registry: registry)

        await store.refresh()

        #expect(store.familyMedia == .available("可用"))
        #expect(store.jellyfin == .authenticationRequired)
        #expect(familyService.didCheckHealth)
        #expect(!jellyfinService.didCheckHealth)
        #expect(!store.jellyfin.canBrowse)
    }

    @Test func refreshKeepsUnavailableSourceBrowsableForItsRetryScreen() async {
        let familyService = FakeMediaService()
        familyService.error = URLError(.cannotConnectToHost)
        let jellyfinService = FakeMediaService()
        let registry = MediaSourceRegistry(
            familyMedia: context(id: .familyMedia, service: familyService),
            jellyfin: context(id: .jellyfin, service: jellyfinService)
        )
        let store = MediaSourceAvailabilityStore(registry: registry)

        await store.refresh()

        guard case .unavailable(let message) = store.familyMedia else {
            Issue.record("家庭媒体应显示为暂时无法连接")
            return
        }
        #expect(message.contains("无法连接"))
        #expect(store.familyMedia.canBrowse)
        #expect(store.jellyfin == .available("可用"))
    }

    @Test func incompatibleFamilyServerRedirectsToSettingsInsteadOfBrowsing() async {
        let familyService = FakeMediaService()
        familyService.error = FamilyMediaCompatibilityError.serverUpdateRequired
        let jellyfinService = FakeMediaService()
        let registry = MediaSourceRegistry(
            familyMedia: context(id: .familyMedia, service: familyService),
            jellyfin: context(id: .jellyfin, service: jellyfinService)
        )
        let store = MediaSourceAvailabilityStore(registry: registry)

        await store.refresh()

        guard case .updateRequired(let message) = store.familyMedia else {
            Issue.record("旧服务端应显示需要更新")
            return
        }
        #expect(message.contains("请部署最新服务端"))
        #expect(!store.familyMedia.canBrowse)
        #expect(store.jellyfin.canBrowse)
    }

    @Test func foregroundRefreshIsThrottledAndRecoversAfterInterval() async {
        let familyService = FakeMediaService()
        let jellyfinService = FakeMediaService()
        var now = Date(timeIntervalSince1970: 1_000)
        let registry = MediaSourceRegistry(
            familyMedia: context(id: .familyMedia, service: familyService),
            jellyfin: context(id: .jellyfin, service: jellyfinService)
        )
        let store = MediaSourceAvailabilityStore(registry: registry, now: { now })

        await store.refresh()
        now.addTimeInterval(10)
        await store.refreshAfterForegroundIfNeeded(minimumInterval: 30)
        #expect(familyService.healthCheckCount == 1)
        #expect(jellyfinService.healthCheckCount == 1)

        now.addTimeInterval(21)
        await store.refreshAfterForegroundIfNeeded(minimumInterval: 30)
        #expect(familyService.healthCheckCount == 2)
        #expect(jellyfinService.healthCheckCount == 2)
    }

    @Test func overlappingRefreshRequestRunsAgainAfterCurrentCheckFinishes() async {
        let gate = FirstHealthCheckGate()
        let familyService = FakeMediaService()
        familyService.healthCheckHandler = {
            await gate.blockFirstRequest()
            return HealthStatus(status: "ok")
        }
        let jellyfinService = FakeMediaService()
        let registry = MediaSourceRegistry(
            familyMedia: context(id: .familyMedia, service: familyService),
            jellyfin: context(id: .jellyfin, service: jellyfinService)
        )
        let store = MediaSourceAvailabilityStore(registry: registry)

        let firstRefresh = Task { @MainActor in await store.refresh() }
        await gate.waitUntilBlocked()
        await store.refresh()
        await gate.release()
        await firstRefresh.value

        #expect(familyService.healthCheckCount == 2)
        #expect(jellyfinService.healthCheckCount == 2)
        #expect(store.familyMedia == .available("可用"))
        #expect(store.jellyfin == .available("可用"))
    }

    @Test func cancelledRefreshDoesNotRestartQueuedCheckOutsideViewLifetime() async throws {
        let gate = FirstHealthCheckGate()
        let familyService = FakeMediaService()
        familyService.healthCheckHandler = {
            await gate.blockFirstRequest()
            return HealthStatus(status: "ok")
        }
        let jellyfinService = FakeMediaService()
        let registry = MediaSourceRegistry(
            familyMedia: context(id: .familyMedia, service: familyService),
            jellyfin: context(id: .jellyfin, service: jellyfinService)
        )
        let store = MediaSourceAvailabilityStore(registry: registry)

        let refreshTask = Task { @MainActor in await store.refresh() }
        await gate.waitUntilBlocked()
        await store.refresh()
        refreshTask.cancel()
        await gate.release()
        await refreshTask.value
        try await Task.sleep(for: .milliseconds(30))

        #expect(familyService.healthCheckCount == 1)
        #expect(jellyfinService.healthCheckCount == 1)
        #expect(!store.isRefreshing)
    }

    @Test func foregroundImmediatelyRetriesAnIncompleteCancelledRefresh() async {
        let familyService = FakeMediaService()
        familyService.error = CancellationError()
        let jellyfinService = FakeMediaService()
        let registry = MediaSourceRegistry(
            familyMedia: context(id: .familyMedia, service: familyService),
            jellyfin: context(id: .jellyfin, service: jellyfinService)
        )
        let store = MediaSourceAvailabilityStore(registry: registry)

        await store.refresh()
        #expect(store.familyMedia == .unchecked)
        #expect(familyService.healthCheckCount == 1)

        familyService.error = nil
        await store.refreshAfterForegroundIfNeeded(minimumInterval: 30)

        #expect(familyService.healthCheckCount == 2)
        #expect(jellyfinService.healthCheckCount == 2)
        #expect(store.familyMedia == .available("可用"))
    }

    @Test func expiredJellyfinSessionPublishesSourceStateChangeOnce() async {
        let readiness = ReadinessBox(.ready)
        let familyService = FakeMediaService()
        let jellyfinService = FakeMediaService()
        jellyfinService.healthCheckHandler = {
            readiness.value = .authenticationRequired
            throw JellyfinError.unauthorized
        }
        let sourceRefreshCenter = MediaSourceRefreshCenter()
        let registry = MediaSourceRegistry(
            familyMedia: context(id: .familyMedia, service: familyService),
            jellyfin: context(
                id: .jellyfin,
                service: jellyfinService,
                readiness: { readiness.value }
            )
        )
        let store = MediaSourceAvailabilityStore(
            registry: registry,
            sourceRefreshCenter: sourceRefreshCenter
        )

        await store.refresh()
        #expect(store.jellyfin == .authenticationRequired)
        #expect(sourceRefreshCenter.generation == 1)

        await store.refresh()
        #expect(sourceRefreshCenter.generation == 1)
    }

    private func context(
        id: MediaSourceID,
        service: FakeMediaService,
        readiness: @escaping @Sendable () -> MediaSourceReadiness = { .ready }
    ) -> MediaSourceContext {
        MediaSourceContext(
            id: id,
            catalog: service,
            playbackResolver: DirectMediaPlaybackResolver(),
            healthChecker: service,
            readiness: readiness
        )
    }
}

private final class ReadinessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: MediaSourceReadiness

    init(_ value: MediaSourceReadiness) {
        storedValue = value
    }

    var value: MediaSourceReadiness {
        get { lock.withLock { storedValue } }
        set { lock.withLock { storedValue = newValue } }
    }
}

private actor FirstHealthCheckGate {
    private var hasBlocked = false
    private var isReleased = false
    private var blockedContinuations: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuations: [CheckedContinuation<Void, Never>] = []

    func blockFirstRequest() async {
        guard !hasBlocked else { return }
        hasBlocked = true
        blockedContinuations.forEach { $0.resume() }
        blockedContinuations.removeAll()
        guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            releaseContinuations.append(continuation)
        }
    }

    func waitUntilBlocked() async {
        guard !hasBlocked else { return }
        await withCheckedContinuation { continuation in
            blockedContinuations.append(continuation)
        }
    }

    func release() {
        isReleased = true
        releaseContinuations.forEach { $0.resume() }
        releaseContinuations.removeAll()
    }
}
