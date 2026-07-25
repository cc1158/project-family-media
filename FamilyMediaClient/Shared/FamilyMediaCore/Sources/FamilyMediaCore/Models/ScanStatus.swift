import Foundation

public enum ScanState: String, Codable, Sendable {
    case idle
    case running
    case completed
    case failed
}

public struct ScanTriggerResponse: Codable, Equatable, Sendable {
    public let jobId: String
    public let status: ScanState

    public init(jobId: String, status: ScanState) {
        self.jobId = jobId
        self.status = status
    }
}

public struct GeneratedDataClearRequest: Codable, Equatable, Sendable {
    public let rescan: Bool

    public init(rescan: Bool) {
        self.rescan = rescan
    }
}

public struct GeneratedDataClearResponse: Codable, Equatable, Sendable {
    public let status: String
    public let clearedDirectories: Int
    public let scan: ScanTriggerResponse?

    public init(
        status: String,
        clearedDirectories: Int,
        scan: ScanTriggerResponse? = nil
    ) {
        self.status = status
        self.clearedDirectories = clearedDirectories
        self.scan = scan
    }
}

public struct ScanStatus: Codable, Equatable, Sendable {
    public let jobId: String
    public let status: ScanState
    public let startedAt: Date?
    public let finishedAt: Date?
    public let scannedFiles: Int?
    public let indexedFiles: Int?
    public let deletedFiles: Int?
    public let metadataExtracted: Int?
    public let metadataMissing: Int?
    public let metadataFailed: Int?
    public let metadataFallback: Int?
    public let thumbnailPending: Int?
    public let thumbnailGenerated: Int?
    public let thumbnailFailed: Int?
    public let thumbnailError: String
    public let error: String

    private enum CodingKeys: String, CodingKey {
        case jobId
        case status
        case startedAt
        case finishedAt
        case scannedFiles
        case indexedFiles
        case deletedFiles
        case metadataExtracted
        case metadataMissing
        case metadataFailed
        case metadataFallback
        case thumbnailPending
        case thumbnailGenerated
        case thumbnailFailed
        case thumbnailError
        case error
    }

    public init(
        jobId: String,
        status: ScanState,
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        scannedFiles: Int? = nil,
        indexedFiles: Int? = nil,
        deletedFiles: Int? = nil,
        metadataExtracted: Int? = nil,
        metadataMissing: Int? = nil,
        metadataFailed: Int? = nil,
        metadataFallback: Int? = nil,
        thumbnailPending: Int? = nil,
        thumbnailGenerated: Int? = nil,
        thumbnailFailed: Int? = nil,
        thumbnailError: String = "",
        error: String = ""
    ) {
        self.jobId = jobId
        self.status = status
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.scannedFiles = scannedFiles
        self.indexedFiles = indexedFiles
        self.deletedFiles = deletedFiles
        self.metadataExtracted = metadataExtracted
        self.metadataMissing = metadataMissing
        self.metadataFailed = metadataFailed
        self.metadataFallback = metadataFallback
        self.thumbnailPending = thumbnailPending
        self.thumbnailGenerated = thumbnailGenerated
        self.thumbnailFailed = thumbnailFailed
        self.thumbnailError = thumbnailError
        self.error = error
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jobId = try container.decode(String.self, forKey: .jobId)
        status = try container.decode(ScanState.self, forKey: .status)
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        finishedAt = try container.decodeIfPresent(Date.self, forKey: .finishedAt)
        scannedFiles = try container.decodeIfPresent(Int.self, forKey: .scannedFiles)
        indexedFiles = try container.decodeIfPresent(Int.self, forKey: .indexedFiles)
        deletedFiles = try container.decodeIfPresent(Int.self, forKey: .deletedFiles)
        metadataExtracted = try container.decodeIfPresent(Int.self, forKey: .metadataExtracted)
        metadataMissing = try container.decodeIfPresent(Int.self, forKey: .metadataMissing)
        metadataFailed = try container.decodeIfPresent(Int.self, forKey: .metadataFailed)
        metadataFallback = try container.decodeIfPresent(Int.self, forKey: .metadataFallback)
        thumbnailPending = try container.decodeIfPresent(Int.self, forKey: .thumbnailPending)
        thumbnailGenerated = try container.decodeIfPresent(Int.self, forKey: .thumbnailGenerated)
        thumbnailFailed = try container.decodeIfPresent(Int.self, forKey: .thumbnailFailed)
        thumbnailError = try container.decodeIfPresent(String.self, forKey: .thumbnailError) ?? ""
        error = try container.decodeIfPresent(String.self, forKey: .error) ?? ""
    }
}
