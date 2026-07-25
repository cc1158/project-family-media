import Foundation

public struct JellyfinServerInfo: Codable, Equatable, Sendable {
    public let ServerName: String
    public let Version: String
}

struct JellyfinLoginRequest: Encodable, Sendable {
    let Username: String
    let Pw: String
}

struct JellyfinAuthenticationResult: Decodable, Sendable {
    let AccessToken: String
    let User: JellyfinUser
}

struct JellyfinUser: Decodable, Sendable {
    let Id: String
    let Name: String
}

struct JellyfinItemsResponse: Decodable, Sendable {
    let Items: [JellyfinItem]
    let TotalRecordCount: Int
}

struct JellyfinItem: Decodable, Sendable {
    let Id: String
    let Name: String
    let `Type`: String?
    let IsFolder: Bool?
    let ImageTags: [String: String]?
    let DateCreated: String?
    let Size: Int64?
}

struct JellyfinPlaybackInfoRequest: Encodable, Sendable {
    let UserId: String
    let DeviceProfile: JellyfinDeviceProfile
    let MaxStreamingBitrate: Int
    let EnableDirectPlay: Bool
    let EnableDirectStream: Bool
    let EnableTranscoding: Bool
    let AllowVideoStreamCopy: Bool
    let AllowAudioStreamCopy: Bool
}

struct JellyfinDeviceProfile: Encodable, Sendable {
    let Name = "Jiaying Apple Stable"
    let MaxStreamingBitrate = 20_000_000
    let DirectPlayProfiles = [
        JellyfinDirectPlayProfile(Container: "mp4,m4v,mov", AudioCodec: "aac,ac3,eac3,mp3", VideoCodec: "h264", Type: "Video")
    ]
    let TranscodingProfiles = [
        JellyfinTranscodingProfile(Container: "ts", Type: "Video", VideoCodec: "h264", AudioCodec: "aac", Protocol: "hls", Context: "Streaming", MaxAudioChannels: "2", MinSegments: 1, SegmentLength: 6, BreakOnNonKeyFrames: true)
    ]
    let CodecProfiles = [
        JellyfinCodecProfile(Type: "Video", Codec: "h264", Conditions: [
            JellyfinProfileCondition(Condition: "LessThanEqual", Property: "VideoBitDepth", Value: "8", IsRequired: true)
        ])
    ]
    let SubtitleProfiles: [String] = []
}

struct JellyfinDirectPlayProfile: Encodable, Sendable {
    let Container: String
    let AudioCodec: String
    let VideoCodec: String
    let `Type`: String
}

struct JellyfinTranscodingProfile: Encodable, Sendable {
    let Container: String
    let `Type`: String
    let VideoCodec: String
    let AudioCodec: String
    let `Protocol`: String
    let Context: String
    let MaxAudioChannels: String
    let MinSegments: Int
    let SegmentLength: Int
    let BreakOnNonKeyFrames: Bool
}

struct JellyfinCodecProfile: Encodable, Sendable {
    let `Type`: String
    let Codec: String
    let Conditions: [JellyfinProfileCondition]
}

struct JellyfinProfileCondition: Encodable, Sendable {
    let Condition: String
    let Property: String
    let Value: String
    let IsRequired: Bool
}

struct JellyfinPlaybackInfoResponse: Decodable, Sendable {
    let MediaSources: [JellyfinMediaSource]
    let PlaySessionId: String?
}

struct JellyfinMediaSource: Decodable, Sendable {
    let Id: String?
    let SupportsDirectPlay: Bool?
    let SupportsDirectStream: Bool?
    let SupportsTranscoding: Bool?
    let TranscodingUrl: String?
}

struct JellyfinPlaybackReport: Encodable, Sendable {
    let ItemId: String
    let MediaSourceId: String?
    let PlaySessionId: String?
    let PositionTicks: Int64
    let IsPaused: Bool
    let PlayMethod: String
    let CanSeek: Bool
}

public enum JellyfinError: Error, Equatable, LocalizedError, Sendable {
    case notAuthenticated
    case invalidAddress
    case invalidCredentials
    case unauthorized
    case server(Int)
    case invalidResponse
    case credentialStorageFailed
    case playbackUnavailable

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "请先登录 Jellyfin。"
        case .invalidAddress: return "Jellyfin 地址格式不正确。"
        case .invalidCredentials: return "Jellyfin 用户名或密码不正确。"
        case .unauthorized: return "Jellyfin 登录已失效，请重新登录。"
        case .server(let code): return "Jellyfin 返回异常状态码：\(code)。"
        case .invalidResponse: return "Jellyfin 返回的数据无法解析。"
        case .credentialStorageFailed: return "无法安全保存 Jellyfin 登录信息。"
        case .playbackUnavailable: return "Jellyfin 无法为此视频提供兼容的播放格式。"
        }
    }
}
