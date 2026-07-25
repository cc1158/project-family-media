import Foundation

public struct HealthStatus: Codable, Equatable, Sendable {
    public let status: String
    public let apiVersion: Int?
    public let capabilities: [String]
    public let build: ServerBuildInfo?
    public let checks: [String: HealthCheck]
    public let scan: HealthScanSummary?

    public init(
        status: String,
        apiVersion: Int? = nil,
        capabilities: [String] = [],
        build: ServerBuildInfo? = nil,
        checks: [String: HealthCheck] = [:],
        scan: HealthScanSummary? = nil
    ) {
        self.status = status
        self.apiVersion = apiVersion
        self.capabilities = capabilities
        self.build = build
        self.checks = checks
        self.scan = scan
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(String.self, forKey: .status)
        apiVersion = try container.decodeIfPresent(Int.self, forKey: .apiVersion)
        capabilities = try container.decodeIfPresent([String].self, forKey: .capabilities) ?? []
        build = try container.decodeIfPresent(ServerBuildInfo.self, forKey: .build)
        checks = try container.decodeIfPresent([String: HealthCheck].self, forKey: .checks) ?? [:]
        scan = try container.decodeIfPresent(HealthScanSummary.self, forKey: .scan)
    }
}

public struct ServerBuildInfo: Codable, Equatable, Sendable {
    public let version: String
    public let commit: String
    public let builtAt: String
    public let source: String

    public init(version: String, commit: String, builtAt: String, source: String) {
        self.version = version
        self.commit = commit
        self.builtAt = builtAt
        self.source = source
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(String.self, forKey: .version) ?? "unknown"
        commit = try container.decodeIfPresent(String.self, forKey: .commit) ?? "unknown"
        builtAt = try container.decodeIfPresent(String.self, forKey: .builtAt) ?? "unknown"
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? "unknown"
    }
}

public struct HealthCheck: Codable, Equatable, Sendable {
    public let status: String
    public let message: String

    public init(status: String, message: String) {
        self.status = status
        self.message = message
    }
}

public struct HealthScanSummary: Codable, Equatable, Sendable {
    public let status: String
    public let jobId: String?
    public let finishedAt: Date?
    public let error: String
    public let thumbnailError: String

    private enum CodingKeys: String, CodingKey {
        case status
        case jobId
        case finishedAt
        case error
        case thumbnailError
    }

    public init(
        status: String,
        jobId: String? = nil,
        finishedAt: Date? = nil,
        error: String = "",
        thumbnailError: String = ""
    ) {
        self.status = status
        self.jobId = jobId
        self.finishedAt = finishedAt
        self.error = error
        self.thumbnailError = thumbnailError
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(String.self, forKey: .status)
        jobId = try container.decodeIfPresent(String.self, forKey: .jobId)
        finishedAt = try container.decodeIfPresent(Date.self, forKey: .finishedAt)
        error = try container.decodeIfPresent(String.self, forKey: .error) ?? ""
        thumbnailError = try container.decodeIfPresent(String.self, forKey: .thumbnailError) ?? ""
    }
}
