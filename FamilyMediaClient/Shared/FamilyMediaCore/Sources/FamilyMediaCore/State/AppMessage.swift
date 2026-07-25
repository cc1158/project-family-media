import Foundation

public enum AppMessageStyle: Equatable, Sendable {
    case info
    case success
    case warning
    case error
}

public struct AppMessage: Equatable, Sendable {
    public let text: String
    public let style: AppMessageStyle

    public init(_ text: String, style: AppMessageStyle = .info) {
        self.text = text
        self.style = style
    }

    public static func success(_ text: String) -> AppMessage {
        AppMessage(text, style: .success)
    }

    public static func warning(_ text: String) -> AppMessage {
        AppMessage(text, style: .warning)
    }

    public static func info(_ text: String) -> AppMessage {
        AppMessage(text, style: .info)
    }

    public static func failure(_ text: String) -> AppMessage {
        AppMessage(text, style: .error)
    }
}

public enum AppErrorMapper {
    public static func message(for error: Error) -> String {
        if let compatibilityError = error as? FamilyMediaCompatibilityError {
            return compatibilityError.errorDescription ?? "NAS 上的家庭媒体服务需要更新。"
        }

        if let message = networkMessage(for: error) {
            return message
        }

        if let message = apiMessage(for: error) {
            return message
        }

        if let message = jellyfinMessage(for: error) {
            return message
        }

        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }

        return error.localizedDescription
    }

    private static func networkMessage(for error: Error) -> String? {
        guard let urlError = error as? URLError else {
            return nil
        }

        switch urlError.code {
        case .timedOut:
            return "连接等待时间过长，请确认 NAS 没有休眠，并检查家庭网络是否稳定。"
        case .cannotConnectToHost, .notConnectedToInternet, .networkConnectionLost, .dnsLookupFailed, .cannotFindHost:
            return "无法连接，请确认当前设备和 NAS 使用同一家庭网络、NAS 已开机，并检查位置和本地网络权限。"
        case .dataNotAllowed:
            return "系统当前不允许家映使用网络，请到系统设置中开启家映的本地网络权限。"
        case .appTransportSecurityRequiresSecureConnection:
            return "当前地址被系统安全策略阻止，请使用 HTTPS，或确认它是可直接访问的局域网地址。"
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
            return "无法建立安全连接，请检查 HTTPS 证书是否有效。"
        default:
            return "网络请求没有完成，请检查家庭网络后重新尝试。"
        }
    }

    private static func apiMessage(for error: Error) -> String? {
        guard let apiError = error as? APIClientError else { return nil }

        switch apiError {
        case .invalidResponse, .decodingFailed:
            return "家庭媒体服务返回了无法识别的内容，请确认 NAS 上的服务已更新。"
        case .unacceptableStatusCode(let statusCode, let code):
            switch code {
            case "media_not_found":
                return "这个文件可能已被移动或删除，请在设置中更新家庭内容。"
            case "regenerate_thumbnail_failed":
                return "封面生成失败，请确认 NAS 上的家庭媒体服务运行正常。"
            case "media_scan_in_progress":
                return "家庭媒体正在更新，请等待更新完成后再清理。"
            case "clear_generated_data_failed":
                return "无法清理家庭媒体数据，请检查 NAS 存储目录权限。"
            case "list_media_failed", "list_photos_failed", "list_videos_failed":
                return "无法读取家庭媒体，请确认 NAS 已开机，并在设置中检查连接。"
            default:
                break
            }

            switch statusCode {
            case 401, 403:
                return "家庭媒体服务拒绝了访问，请检查 NAS 服务配置。"
            case 404:
                return "没有找到家庭媒体服务，请检查地址和 NAS 上的服务版本。"
            case 429:
                return "请求过于频繁，请稍等片刻后重新尝试。"
            case 500...599:
                return "NAS 上的家庭媒体服务暂时出错，请稍后重新尝试。"
            default:
                return "家庭媒体服务暂时无法完成请求，请稍后重新尝试。"
            }
        }
    }

    private static func jellyfinMessage(for error: Error) -> String? {
        guard let jellyfinError = error as? JellyfinError else { return nil }

        switch jellyfinError {
        case .server:
            return "Jellyfin 服务暂时出错，请稍后重新尝试。"
        case .invalidResponse:
            return "Jellyfin 返回了无法识别的内容，请确认服务器已更新。"
        case .notAuthenticated, .invalidAddress, .invalidCredentials, .unauthorized,
             .credentialStorageFailed, .playbackUnavailable:
            return jellyfinError.errorDescription ?? "Jellyfin 操作没有完成，请稍后重试。"
        }
    }
}
