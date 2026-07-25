import Foundation

public protocol JellyfinConfigurationProviding: Sendable {
    var serverBaseURL: URL { get }
    var deviceID: String { get }
}

public final class JellyfinConfigurationStore: JellyfinConfigurationProviding, @unchecked Sendable {
    private let defaults: UserDefaults
    private let urlKey: String
    private let deviceKey: String
    private let sessionServerKey: String
    private let fallbackURL: URL
    private let lock = NSLock()
    private var revision: UInt64 = 0

    public init(
        defaults: UserDefaults = .standard,
        urlKey: String = "familyMedia.jellyfinBaseURL",
        deviceKey: String = "familyMedia.jellyfinDeviceID",
        sessionServerKey: String = "familyMedia.jellyfinSessionServerURL",
        fallbackURL: URL = URL(string: "http://nas.local:8096")!
    ) {
        self.defaults = defaults
        self.urlKey = urlKey
        self.deviceKey = deviceKey
        self.sessionServerKey = sessionServerKey
        self.fallbackURL = ServerAddressNormalizer.normalize(fallbackURL.absoluteString) ?? fallbackURL
    }

    public var serverBaseURL: URL {
        get { lock.withLock { storedURL() } }
        set {
            lock.withLock {
                let previousURL = storedURL()
                let normalizedURL = ServerAddressNormalizer.normalize(newValue.absoluteString) ?? fallbackURL
                defaults.set(normalizedURL.absoluteString, forKey: urlKey)
                if previousURL != normalizedURL {
                    revision &+= 1
                }
            }
        }
    }

    var configurationRevision: UInt64 {
        lock.withLock { revision }
    }

    var persistedSessionServerURL: URL? {
        lock.withLock {
            guard let value = defaults.string(forKey: sessionServerKey),
                  let url = ServerAddressNormalizer.normalize(value)
            else {
                defaults.removeObject(forKey: sessionServerKey)
                return nil
            }
            if value != url.absoluteString {
                defaults.set(url.absoluteString, forKey: sessionServerKey)
            }
            return url
        }
    }

    var hasPersistedDeviceID: Bool {
        lock.withLock {
            guard let value = defaults.string(forKey: deviceKey) else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    func bindSessionToCurrentServer() {
        lock.withLock {
            defaults.set(storedURL().absoluteString, forKey: sessionServerKey)
        }
    }

    func clearSessionServerBinding() {
        lock.withLock {
            defaults.removeObject(forKey: sessionServerKey)
        }
    }

    public var deviceID: String {
        lock.withLock {
            if let value = defaults.string(forKey: deviceKey) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    if value != trimmed { defaults.set(trimmed, forKey: deviceKey) }
                    return trimmed
                }
            }
            let value = UUID().uuidString
            defaults.set(value, forKey: deviceKey)
            return value
        }
    }

    private func storedURL() -> URL {
        guard let value = defaults.string(forKey: urlKey) else { return fallbackURL }
        guard let url = ServerAddressNormalizer.normalize(value) else {
            defaults.removeObject(forKey: urlKey)
            return fallbackURL
        }
        if value != url.absoluteString {
            defaults.set(url.absoluteString, forKey: urlKey)
        }
        return url
    }
}
