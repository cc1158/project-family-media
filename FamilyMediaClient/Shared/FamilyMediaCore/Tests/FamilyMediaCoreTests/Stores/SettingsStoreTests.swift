import Foundation
import Testing
@testable import FamilyMediaCore

@MainActor
struct SettingsStoreTests {
    @Test func savesServerURL() {
        let defaults = isolatedDefaults()
        let fallbackURL = URL(string: "http://192.168.1.20:8080")!
        let configurationStore = ServerConfigurationStore(defaults: defaults, fallbackURL: fallbackURL)
        let sourceRefreshCenter = MediaSourceRefreshCenter()
        let store = SettingsStore(
            mediaService: FakeMediaService(),
            configurationStore: configurationStore,
            sourceRefreshCenter: sourceRefreshCenter
        )

        store.serverURLText = "http://192.168.1.30:9090"
        let saved = store.saveServerURL()

        #expect(saved)
        #expect(configurationStore.serverBaseURL.absoluteString == "http://192.168.1.30:9090")
        #expect(store.message == .success("家庭媒体位置已保存"))
        #expect(sourceRefreshCenter.generation == 1)
        #expect(
            sourceRefreshCenter.affectedSourceID?.rawValue
                == MediaSourceID.familyMedia.rawValue
        )

        #expect(store.saveServerURL())
        #expect(sourceRefreshCenter.generation == 1)
    }

    @Test func rejectsInvalidServerURL() {
        let configurationStore = ServerConfigurationStore(
            defaults: isolatedDefaults(),
            fallbackURL: URL(string: "http://192.168.1.20:8080")!
        )
        let store = SettingsStore(mediaService: FakeMediaService(), configurationStore: configurationStore)

        store.serverURLText = "not-a-url"
        let saved = store.saveServerURL()

        #expect(!saved)
        #expect(store.message == .warning("家庭媒体位置格式不正确"))
    }

    @Test func normalizesSafeHTTPServerAddress() {
        let configurationStore = ServerConfigurationStore(
            defaults: isolatedDefaults(),
            fallbackURL: URL(string: "http://192.168.1.20:8080")!
        )
        let store = SettingsStore(mediaService: FakeMediaService(), configurationStore: configurationStore)

        store.serverURLText = "  HTTPS://NAS.EXAMPLE.COM:443/media/  "

        #expect(store.saveServerURL())
        #expect(configurationStore.serverBaseURL.absoluteString == "https://nas.example.com/media")
        #expect(store.serverURLText == "https://nas.example.com/media")
    }

    @Test func rejectsUnsupportedOrCredentialBearingServerAddress() {
        let configurationStore = ServerConfigurationStore(
            defaults: isolatedDefaults(),
            fallbackURL: URL(string: "http://192.168.1.20:8080")!
        )
        let store = SettingsStore(mediaService: FakeMediaService(), configurationStore: configurationStore)

        store.serverURLText = "ftp://nas.example.com/media"
        #expect(!store.saveServerURL())

        store.serverURLText = "https://user:password@nas.example.com/media"
        #expect(!store.saveServerURL())
    }

    @Test func checksConnection() async {
        let service = FakeMediaService()
        service.healthStatus = HealthStatus(status: "degraded", checks: [
            "ffmpeg": HealthCheck(status: "warning", message: "not available")
        ])
        let sourceRefreshCenter = MediaSourceRefreshCenter()
        let store = SettingsStore(
            mediaService: service,
            configurationStore: ServerConfigurationStore(
                defaults: isolatedDefaults(),
                fallbackURL: URL(string: "http://192.168.1.20:8080")!
            ),
            sourceRefreshCenter: sourceRefreshCenter
        )

        await store.checkConnection()

        #expect(service.didCheckHealth)
        #expect(store.message == .warning("可以连接，但部分功能可能不可用"))
        #expect(store.healthStatus?.checks["ffmpeg"]?.status == "warning")
        #expect(store.connectionStatus == .available)
        #expect(sourceRefreshCenter.generation == 1)
    }

    @Test func triggersScanAndFetchesStatus() async {
        let service = FakeMediaService()
        service.triggerResponse = ScanTriggerResponse(jobId: "scan-1", status: .running)
        service.scanStatus = ScanStatus(jobId: "scan-1", status: .completed, scannedFiles: 20)
        let refreshCenter = MediaLibraryRefreshCenter()
        let store = SettingsStore(
            mediaService: service,
            configurationStore: ServerConfigurationStore(
                defaults: isolatedDefaults(),
                fallbackURL: URL(string: "http://192.168.1.20:8080")!
            ),
            refreshCenter: refreshCenter
        )

        await store.triggerScan()

        #expect(service.didTriggerScan)
        #expect(service.didFetchScanStatus)
        #expect(store.message == .success("内容更新完成"))
        #expect(store.scanStatus?.status == .completed)
        #expect(store.scanStatus?.scannedFiles == 20)
        #expect(store.completedScanCount == 1)
        #expect(refreshCenter.generation == 1)
    }

    @Test func laterStatusCheckPublishesCompletedScanExactlyOnce() async {
        let service = FakeMediaService()
        service.scanStatus = ScanStatus(jobId: "scan-detached", status: .running, scannedFiles: 8)
        let refreshCenter = MediaLibraryRefreshCenter()
        let store = SettingsStore(
            mediaService: service,
            configurationStore: ServerConfigurationStore(
                defaults: isolatedDefaults(),
                fallbackURL: URL(string: "http://192.168.1.20:8080")!
            ),
            refreshCenter: refreshCenter
        )

        await store.refreshScanStatus()
        #expect(store.message == .info("正在更新家庭媒体…"))
        #expect(refreshCenter.generation == 0)

        service.scanStatus = ScanStatus(
            jobId: "scan-detached",
            status: .completed,
            scannedFiles: 20
        )
        await store.refreshScanStatus()
        await store.refreshScanStatus()

        #expect(store.message == .success("内容更新完成"))
        #expect(store.scanStatus?.scannedFiles == 20)
        #expect(store.completedScanCount == 1)
        #expect(refreshCenter.generation == 1)
    }

    @Test func returningToSettingsResumesKnownRunningScan() async {
        let service = FakeMediaService()
        service.scanStatus = ScanStatus(jobId: "scan-resume", status: .running)
        let refreshCenter = MediaLibraryRefreshCenter()
        let store = SettingsStore(
            mediaService: service,
            configurationStore: ServerConfigurationStore(
                defaults: isolatedDefaults(),
                fallbackURL: URL(string: "http://192.168.1.20:8080")!
            ),
            refreshCenter: refreshCenter
        )

        await store.refreshScanStatus()
        service.scanStatus = ScanStatus(jobId: "scan-resume", status: .completed)
        await store.resumeScanMonitoringIfNeeded()

        #expect(store.scanStatus?.status == .completed)
        #expect(store.message == .success("内容更新完成"))
        #expect(refreshCenter.generation == 1)
    }

    @Test func recreatedClientDiscoversAndResumesServerSideRunningScan() async {
        let service = FakeMediaService()
        service.scanStatuses = [
            ScanStatus(jobId: "scan-after-relaunch", status: .running, scannedFiles: 8),
            ScanStatus(jobId: "scan-after-relaunch", status: .completed, scannedFiles: 20)
        ]
        let refreshCenter = MediaLibraryRefreshCenter()
        let store = SettingsStore(
            mediaService: service,
            configurationStore: ServerConfigurationStore(
                defaults: isolatedDefaults(),
                fallbackURL: URL(string: "http://192.168.1.20:8080")!
            ),
            refreshCenter: refreshCenter,
            scanPollInterval: .milliseconds(1)
        )

        await store.refreshAndResumeScanMonitoring()

        #expect(service.scanStatusFetchCount == 2)
        #expect(store.scanStatus?.status == .completed)
        #expect(store.scanStatus?.scannedFiles == 20)
        #expect(store.message == .success("内容更新完成"))
        #expect(store.completedScanCount == 1)
        #expect(refreshCenter.generation == 1)
    }

    @Test func repeatedPageAppearanceDoesNotRepublishHistoricalCompletion() async {
        let service = FakeMediaService()
        service.scanStatus = ScanStatus(
            jobId: "scan-completed-while-away",
            status: .completed,
            scannedFiles: 30
        )
        let refreshCenter = MediaLibraryRefreshCenter()
        let store = SettingsStore(
            mediaService: service,
            configurationStore: ServerConfigurationStore(
                defaults: isolatedDefaults(),
                fallbackURL: URL(string: "http://192.168.1.20:8080")!
            ),
            refreshCenter: refreshCenter
        )

        await store.refreshAndResumeScanMonitoring()
        await store.refreshAndResumeScanMonitoring()

        #expect(service.scanStatusFetchCount == 2)
        #expect(store.completedScanCount == 1)
        #expect(refreshCenter.generation == 1)
    }

    @Test func clearsGeneratedDataWithoutTouchingConfigurationAndRefreshesLibrary() async {
        let service = FakeMediaService()
        let refreshCenter = MediaLibraryRefreshCenter()
        let configuration = ServerConfigurationStore(
            defaults: isolatedDefaults(),
            fallbackURL: URL(string: "http://192.168.1.20:8080")!
        )
        let store = SettingsStore(
            mediaService: service,
            configurationStore: configuration,
            refreshCenter: refreshCenter
        )

        await store.clearGeneratedData(rescan: false)

        #expect(service.clearGeneratedDataRequests == [false])
        #expect(configuration.serverBaseURL.absoluteString == "http://192.168.1.20:8080")
        #expect(refreshCenter.generation == 1)
        #expect(store.scanStatus?.status == .idle)
        #expect(store.message == .success("家庭媒体数据已清理，原始照片和视频未受影响"))
    }

    @Test func clearsGeneratedDataAndTracksRequestedRescan() async {
        let service = FakeMediaService()
        service.clearGeneratedDataResponse = GeneratedDataClearResponse(
            status: "cleared",
            clearedDirectories: 2,
            scan: ScanTriggerResponse(jobId: "scan-new", status: .running)
        )
        service.scanStatus = ScanStatus(jobId: "scan-new", status: .completed, scannedFiles: 12)
        let refreshCenter = MediaLibraryRefreshCenter()
        let store = SettingsStore(
            mediaService: service,
            configurationStore: ServerConfigurationStore(
                defaults: isolatedDefaults(),
                fallbackURL: URL(string: "http://192.168.1.20:8080")!
            ),
            refreshCenter: refreshCenter
        )

        await store.clearGeneratedData(rescan: true)

        #expect(service.clearGeneratedDataRequests == [true])
        #expect(service.didFetchScanStatus)
        #expect(store.scanStatus?.status == .completed)
        #expect(store.message == .success("内容更新完成"))
        #expect(refreshCenter.generation == 2)
    }

    @Test func surfacesOperationFailure() async {
        let service = FakeMediaService()
        service.error = FakeError.failed
        let store = SettingsStore(
            mediaService: service,
            configurationStore: ServerConfigurationStore(
                defaults: isolatedDefaults(),
                fallbackURL: URL(string: "http://192.168.1.20:8080")!
            )
        )

        await store.checkConnection()

        #expect(store.message == .failure("测试错误"))
        #expect(store.connectionStatus == .unavailable)
    }

    @Test func cancelledConnectionCheckDoesNotShowNetworkFailure() async {
        let service = FakeMediaService()
        service.error = CancellationError()
        let store = SettingsStore(
            mediaService: service,
            configurationStore: ServerConfigurationStore(
                defaults: isolatedDefaults(),
                fallbackURL: URL(string: "http://192.168.1.20:8080")!
            )
        )

        await store.checkConnection()

        #expect(store.connectionStatus == .unchecked)
        #expect(store.message == .success("家庭媒体位置已保存"))
    }

    @Test func changingAddressClearsStaleConnectionResults() async {
        let service = FakeMediaService()
        let configuration = ServerConfigurationStore(
            defaults: isolatedDefaults(),
            fallbackURL: URL(string: "http://192.168.1.20:8080")!
        )
        let store = SettingsStore(mediaService: service, configurationStore: configuration)

        await store.checkConnection()
        #expect(store.connectionStatus == .available)
        #expect(store.healthStatus != nil)

        store.serverURLText = "http://192.168.1.30:8080"
        #expect(store.saveServerURL())

        #expect(store.connectionStatus == .unchecked)
        #expect(store.healthStatus == nil)
        #expect(store.scanStatus == nil)
    }
}
