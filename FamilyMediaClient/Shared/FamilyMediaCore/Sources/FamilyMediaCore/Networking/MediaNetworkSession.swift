import Foundation

/// Shared production transport for first-party API and Jellyfin JSON requests.
/// Authentication headers and server responses are intentionally never written
/// to the system URL cache.
public enum MediaNetworkSession {
    public static let shared: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 60
        configuration.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: configuration)
    }()
}
