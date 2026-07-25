import Foundation

public struct ClientBuildInfo: Equatable, Sendable {
    public let version: String
    public let build: String

    public init(version: String, build: String) {
        self.version = version.isEmpty ? "未知版本" : version
        self.build = build.isEmpty ? "未知" : build
    }

    public var displayText: String {
        "家映 \(version)（\(build)）"
    }

    public static func load(bundle: Bundle = .main) -> ClientBuildInfo {
        ClientBuildInfo(
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        )
    }
}

public struct JellyfinClientIdentity: Equatable, Sendable {
    public static let `default` = JellyfinClientIdentity(
        clientName: "Jiaying",
        deviceName: "Apple",
        version: "unknown"
    )

    public let clientName: String
    public let deviceName: String
    public let version: String

    public init(clientName: String, deviceName: String, version: String) {
        self.clientName = Self.sanitized(clientName, fallback: "Jiaying")
        self.deviceName = Self.sanitized(deviceName, fallback: "Apple")
        self.version = Self.sanitized(version, fallback: "unknown")
    }

    private static func sanitized(_ value: String, fallback: String) -> String {
        let sanitized = value
            .replacingOccurrences(of: "\"", with: "'")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? fallback : sanitized
    }
}
