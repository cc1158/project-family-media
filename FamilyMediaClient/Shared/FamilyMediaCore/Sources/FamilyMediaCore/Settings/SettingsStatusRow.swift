import Foundation

public struct SettingsStatusRow: Equatable, Sendable {
    public let title: String
    public let value: String
    public let isHealthy: Bool

    public init(title: String, value: String, isHealthy: Bool = true) {
        self.title = title
        self.value = value
        self.isHealthy = isHealthy
    }
}
