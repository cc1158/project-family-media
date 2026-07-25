import Foundation

public struct ClientAppConfiguration {
    public static let serverBaseURLInfoKey = "FAMILY_MEDIA_SERVER_BASE_URL"
    public static let defaultServerBaseURL = "http://nas.local:8080"

    public let serverBaseURL: URL

    public init(serverBaseURL: URL) {
        self.serverBaseURL = serverBaseURL
    }

    public static func load(bundle: Bundle = .main) -> ClientAppConfiguration {
        let value = bundle.object(forInfoDictionaryKey: serverBaseURLInfoKey) as? String
        return ClientAppConfiguration(serverBaseURL: normalizedServerBaseURL(from: value))
    }

    static func normalizedServerBaseURL(from value: String?) -> URL {
        if let value, let configuredURL = ServerAddressNormalizer.normalize(value) {
            return configuredURL
        }
        if let defaultURL = ServerAddressNormalizer.normalize(defaultServerBaseURL) {
            return defaultURL
        }
        // The bundled default is controlled by this module. Keep startup safe even
        // if a future edit accidentally makes that constant invalid.
        return URL(fileURLWithPath: "/")
    }
}

public enum ClientExperienceSettings {
    /// Keep this key stable so an app update does not repeatedly show first-run guidance.
    public static let hasCompletedOnboardingKey = "client_has_completed_onboarding"
}
