import Foundation

@MainActor
public final class SettingsStore: ObservableObject {
    private static let scanPollAttempts = 30

    @Published public var serverURLText: String
    @Published public private(set) var message: AppMessage?
    @Published public private(set) var healthStatus: HealthStatus?
    @Published public private(set) var scanStatus: ScanStatus?
    @Published public private(set) var completedScanCount = 0
    @Published public private(set) var isWorking = false
    @Published public private(set) var connectionStatus: ClientDiagnosticConnectionStatus = .unchecked

    private let mediaService: any MediaServicing
    private let configurationStore: ServerConfigurationStore
    private let refreshCenter: MediaLibraryRefreshCenter
    private let sourceRefreshCenter: MediaSourceRefreshCenter
    private let scanPollInterval: Duration
    private var hasPublishedCurrentScanCompletion = false

    public init(
        mediaService: any MediaServicing,
        configurationStore: ServerConfigurationStore,
        refreshCenter: MediaLibraryRefreshCenter = MediaLibraryRefreshCenter(),
        sourceRefreshCenter: MediaSourceRefreshCenter = MediaSourceRefreshCenter(),
        scanPollInterval: Duration = .seconds(2)
    ) {
        self.mediaService = mediaService
        self.configurationStore = configurationStore
        self.refreshCenter = refreshCenter
        self.sourceRefreshCenter = sourceRefreshCenter
        self.scanPollInterval = scanPollInterval
        self.serverURLText = configurationStore.serverBaseURL.absoluteString
    }

    @discardableResult
    public func saveServerURL() -> Bool {
        saveServerURL(publishRefresh: true)
    }

    private func saveServerURL(publishRefresh: Bool) -> Bool {
        guard let url = ServerAddressNormalizer.normalize(serverURLText) else {
            connectionStatus = .unavailable
            message = .warning("家庭媒体位置格式不正确")
            return false
        }

        let previousURL = ServerAddressNormalizer.normalize(
            configurationStore.serverBaseURL.absoluteString
        )
        let didChangeAddress = previousURL != url
        if didChangeAddress {
            healthStatus = nil
            scanStatus = nil
            hasPublishedCurrentScanCompletion = false
            connectionStatus = .unchecked
        }
        configurationStore.serverBaseURL = url
        serverURLText = url.absoluteString
        message = .success("家庭媒体位置已保存")
        if didChangeAddress, publishRefresh {
            sourceRefreshCenter.publishRefresh(for: .familyMedia)
        }
        return true
    }

    public func checkConnection() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        guard saveServerURL(publishRefresh: false) else { return }
        defer { sourceRefreshCenter.publishRefresh(for: .familyMedia) }
        do {
            let status = try await mediaService.checkHealth()
            healthStatus = status
            connectionStatus = .available
            message = status.status == "ok"
                ? .success("家庭媒体可用")
                : .warning("可以连接，但部分功能可能不可用")
        } catch let error where TaskCancellation.matches(error) {
            return
        } catch {
            connectionStatus = .unavailable
            message = .failure(AppErrorMapper.message(for: error))
        }
    }

    public func triggerScan() async {
        await run {
            guard saveServerURL() else { return }
            let response = try await mediaService.triggerScan()
            hasPublishedCurrentScanCompletion = false
            scanStatus = ScanStatus(jobId: response.jobId, status: response.status)
            message = .info("正在更新家庭媒体…")
            let result = try await pollScanStatus()
            applyScanStatus(result, pollingFinished: true)
        }
    }

    public func clearGeneratedData(rescan: Bool) async {
        await run {
            guard saveServerURL() else { return }
            let response = try await mediaService.clearGeneratedData(rescan: rescan)
            hasPublishedCurrentScanCompletion = false
            refreshCenter.publishRefresh()

            guard let scan = response.scan else {
                scanStatus = ScanStatus(jobId: "", status: .idle)
                message = .success("家庭媒体数据已清理，原始照片和视频未受影响")
                return
            }

            scanStatus = ScanStatus(jobId: scan.jobId, status: scan.status)
            message = .info("数据已清理，正在重新整理家庭媒体…")
            let result = try await pollScanStatus()
            applyScanStatus(result, pollingFinished: true)
        }
    }

    public func refreshScanStatus() async {
        await run {
            let status = try await mediaService.fetchScanStatus()
            scanStatus = status
            applyScanStatus(status, pollingFinished: false)
        }
    }

    public func resumeScanMonitoringIfNeeded() async {
        guard scanStatus?.status == .running else { return }
        await run {
            let result = try await pollScanStatus()
            applyScanStatus(result, pollingFinished: true)
        }
    }

    /// Reconnects the settings UI to the server-side scan job after this view,
    /// or the entire app, has been recreated. The scan itself belongs to the
    /// NAS and may continue while the client is suspended or terminated.
    public func refreshAndResumeScanMonitoring() async {
        await run {
            let initial = try await mediaService.fetchScanStatus()
            scanStatus = initial
            applyScanStatus(initial, pollingFinished: false)
            guard initial.status == .running else { return }

            let result = try await pollScanStatus(startingWith: initial)
            applyScanStatus(result, pollingFinished: true)
        }
    }

    private func run(_ operation: () async throws -> Void) async {
        guard !isWorking else { return }

        isWorking = true
        defer { isWorking = false }

        do {
            try await operation()
        } catch let error where TaskCancellation.matches(error) {
            return
        } catch {
            message = .failure(AppErrorMapper.message(for: error))
        }
    }

    private func pollScanStatus(startingWith initial: ScanStatus? = nil) async throws -> ScanStatus {
        var latest: ScanStatus
        if let initial {
            latest = initial
        } else {
            latest = try await mediaService.fetchScanStatus()
        }
        scanStatus = latest

        for _ in 0..<Self.scanPollAttempts where latest.status == .running {
            try await Task.sleep(for: scanPollInterval)
            latest = try await mediaService.fetchScanStatus()
            scanStatus = latest
        }

        return latest
    }

    private func applyScanStatus(
        _ status: ScanStatus,
        pollingFinished: Bool
    ) {
        switch status.status {
        case .idle:
            hasPublishedCurrentScanCompletion = false
            message = .info("尚未更新家庭媒体")
        case .running:
            hasPublishedCurrentScanCompletion = false
            message = pollingFinished
                ? .info("内容仍在后台更新，可稍后返回查看")
                : .info("正在更新家庭媒体…")
        case .completed:
            if !hasPublishedCurrentScanCompletion {
                hasPublishedCurrentScanCompletion = true
                completedScanCount += 1
                refreshCenter.publishRefresh()
            }
            message = .success("内容更新完成")
        case .failed:
            hasPublishedCurrentScanCompletion = false
            message = .failure(ScanStatusPresentation.failureGuidance)
        }
    }
}
