import Foundation

public struct ThumbnailRegenerationRequest: Codable, Equatable, Sendable {
    public let timeOffsetSeconds: Int?

    public init(timeOffsetSeconds: Int? = nil) {
        self.timeOffsetSeconds = timeOffsetSeconds
    }
}

public struct ThumbnailRegenerationResponse: Codable, Equatable, Sendable {
    public let id: String
    public let thumbnailStatus: ThumbnailStatus

    public init(id: String, thumbnailStatus: ThumbnailStatus) {
        self.id = id
        self.thumbnailStatus = thumbnailStatus
    }
}
