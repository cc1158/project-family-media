import Foundation

public struct APIConfiguration: Sendable, Equatable {
    public let baseURL: URL

    public init(baseURL: URL) {
        self.baseURL = baseURL
    }

    public static func localNetwork(host: String, port: Int = 8080) -> APIConfiguration {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        var components = URLComponents()
        components.scheme = "http"
        components.host = normalizedHost
        components.port = (1...65_535).contains(port) ? port : nil

        if !normalizedHost.isEmpty,
           (1...65_535).contains(port),
           let candidate = components.url,
           let url = ServerAddressNormalizer.normalize(candidate.absoluteString) {
            return APIConfiguration(baseURL: url)
        }
        return APIConfiguration(
            baseURL: ClientAppConfiguration.normalizedServerBaseURL(from: nil)
        )
    }
}
