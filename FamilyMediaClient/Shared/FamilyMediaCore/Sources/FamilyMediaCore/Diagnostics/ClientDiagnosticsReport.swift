import Foundation

public enum ClientDiagnosticConnectionStatus: Equatable, Sendable {
    case unchecked
    case available
    case unavailable

    public var displayText: String {
        switch self {
        case .unchecked: "尚未检查"
        case .available: "可以访问"
        case .unavailable: "暂时无法访问"
        }
    }

}

public struct ClientDiagnosticsReport: Equatable, Sendable {
    public let buildInfo: ClientBuildInfo
    public let deviceDescription: String
    public let familyMediaAddress: String
    public let familyMediaStatus: ClientDiagnosticConnectionStatus
    public let jellyfinAddress: String
    public let jellyfinStatus: ClientDiagnosticConnectionStatus
    public let isJellyfinLoggedIn: Bool
    public let recentEvents: [ClientDiagnosticEvent]

    public init(
        buildInfo: ClientBuildInfo,
        deviceDescription: String,
        familyMediaAddress: String,
        familyMediaStatus: ClientDiagnosticConnectionStatus,
        jellyfinAddress: String,
        jellyfinStatus: ClientDiagnosticConnectionStatus,
        isJellyfinLoggedIn: Bool,
        recentEvents: [ClientDiagnosticEvent] = []
    ) {
        self.buildInfo = buildInfo
        self.deviceDescription = deviceDescription
        self.familyMediaAddress = Self.sanitizedAddress(familyMediaAddress)
        self.familyMediaStatus = familyMediaStatus
        self.jellyfinAddress = Self.sanitizedAddress(jellyfinAddress)
        self.jellyfinStatus = jellyfinStatus
        self.isJellyfinLoggedIn = isJellyfinLoggedIn
        self.recentEvents = Array(recentEvents.suffix(30))
    }

    public var text: String {
        let summary = """
        家映诊断信息
        版本：\(buildInfo.displayText)
        设备：\(deviceDescription)
        家庭媒体地址：\(familyMediaAddress)
        家庭媒体状态：\(familyMediaStatus.displayText)
        Jellyfin 地址：\(jellyfinAddress)
        Jellyfin 状态：\(jellyfinStatus.displayText)
        Jellyfin 登录：\(isJellyfinLoggedIn ? "已登录" : "未登录")
        """
        guard !recentEvents.isEmpty else { return summary }
        return summary + "\n最近事件：\n" + recentEvents
            .map(\.diagnosticText)
            .joined(separator: "\n")
    }

    private static func sanitizedAddress(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var components = URLComponents(string: trimmed),
              components.scheme != nil,
              components.host != nil
        else { return "未设置或格式无效" }

        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString ?? "未设置或格式无效"
    }
}
