import Foundation

public struct APIErrorResponse: Codable, Equatable, Sendable {
    public let error: String

    public init(error: String) {
        self.error = error
    }
}
