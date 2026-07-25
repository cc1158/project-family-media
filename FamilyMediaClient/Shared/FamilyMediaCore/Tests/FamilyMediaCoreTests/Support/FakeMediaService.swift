import Foundation
@testable import FamilyMediaCore

final class FakeMediaService: MediaServicing, @unchecked Sendable {
    var mediaResults: [Result<MediaPage, Error>] = []
    var pages: [MediaPage] = []
    var healthStatus = HealthStatus(status: "ok")
    var triggerResponse = ScanTriggerResponse(jobId: "scan-1", status: .running)
    var scanStatus = ScanStatus(jobId: "scan-1", status: .completed, scannedFiles: 10)
    var scanStatuses: [ScanStatus] = []
    var thumbnailRegenerationResponse = ThumbnailRegenerationResponse(id: "media-1", thumbnailStatus: .ready)
    var clearGeneratedDataResponse = GeneratedDataClearResponse(status: "cleared", clearedDirectories: 2)
    var error: Error?
    var healthCheckHandler: (@Sendable () async throws -> HealthStatus)?

    private(set) var mediaRequests: [(filter: MediaFilter, request: MediaPageRequest)] = []
    private(set) var didCheckHealth = false
    private(set) var healthCheckCount = 0
    private(set) var didTriggerScan = false
    private(set) var didFetchScanStatus = false
    private(set) var scanStatusFetchCount = 0
    private(set) var thumbnailRegenerationRequests: [(mediaID: String, request: ThumbnailRegenerationRequest)] = []
    private(set) var clearGeneratedDataRequests: [Bool] = []

    func fetchMedia(filter: MediaFilter, request: MediaPageRequest) async throws -> MediaPage {
        mediaRequests.append((filter, request))

        if !mediaResults.isEmpty {
            return try mediaResults.removeFirst().get()
        }

        if let error {
            throw error
        }

        if pages.isEmpty {
            return MediaPage(items: [])
        }

        return pages.removeFirst()
    }

    func checkHealth() async throws -> HealthStatus {
        didCheckHealth = true
        healthCheckCount += 1

        if let healthCheckHandler {
            return try await healthCheckHandler()
        }

        if let error {
            throw error
        }

        return healthStatus
    }

    func triggerScan() async throws -> ScanTriggerResponse {
        didTriggerScan = true

        if let error {
            throw error
        }

        return triggerResponse
    }

    func fetchScanStatus() async throws -> ScanStatus {
        didFetchScanStatus = true
        scanStatusFetchCount += 1

        if let error {
            throw error
        }

        if !scanStatuses.isEmpty {
            return scanStatuses.removeFirst()
        }

        return scanStatus
    }

    func regenerateThumbnail(
        mediaID: String,
        request: ThumbnailRegenerationRequest
    ) async throws -> ThumbnailRegenerationResponse {
        thumbnailRegenerationRequests.append((mediaID, request))

        if let error {
            throw error
        }

        return thumbnailRegenerationResponse
    }

    func clearGeneratedData(rescan: Bool) async throws -> GeneratedDataClearResponse {
        clearGeneratedDataRequests.append(rescan)
        if let error {
            throw error
        }
        return clearGeneratedDataResponse
    }
}

enum FakeError: Error, LocalizedError {
    case failed

    var errorDescription: String? {
        "测试错误"
    }
}

func makeMediaItem(id: String, kind: MediaKind = .photo) -> MediaItem {
    MediaItem(
        id: id,
        name: "\(id).jpg",
        kind: kind,
        size: 1024,
        modified: Date(timeIntervalSince1970: 1_779_120_000),
        url: URL(string: "http://localhost:8080/media/original/\(id).jpg")!,
        thumbnailURL: URL(string: "http://localhost:8080/media/thumbnails/\(id).jpg"),
        mediaPath: "\(id).jpg",
        thumbnailStatus: .ready
    )
}

func isolatedDefaults() -> UserDefaults {
    let suiteName = "FamilyMediaCoreTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
