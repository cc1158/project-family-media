import Foundation

public protocol ServerConfigurationProviding: Sendable {
    var serverBaseURL: URL { get }
    var configurationRevision: UInt64 { get }
}

public extension ServerConfigurationProviding {
    var configurationRevision: UInt64 { 0 }
}

public final class ServerConfigurationStore: ServerConfigurationProviding, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String
    private let fallbackURL: URL
    private let lock = NSLock()
    private var revision: UInt64 = 0

    public init(
        defaults: UserDefaults = .standard,
        key: String = "familyMedia.serverBaseURL",
        fallbackURL: URL
    ) {
        self.defaults = defaults
        self.key = key
        self.fallbackURL = ServerAddressNormalizer.normalize(fallbackURL.absoluteString) ?? fallbackURL
    }

    public var serverBaseURL: URL {
        get {
            lock.withLock {
                storedURL()
            }
        }
        set {
            lock.withLock {
                let previousURL = storedURL()
                let normalizedURL = ServerAddressNormalizer.normalize(newValue.absoluteString) ?? fallbackURL
                defaults.set(normalizedURL.absoluteString, forKey: key)
                if previousURL != normalizedURL {
                    revision &+= 1
                }
            }
        }
    }

    public var configurationRevision: UInt64 {
        lock.withLock { revision }
    }

    public func reset() {
        lock.withLock {
            let previousURL = storedURL()
            defaults.removeObject(forKey: key)
            if previousURL != fallbackURL {
                revision &+= 1
            }
        }
    }

    private func storedURL() -> URL {
        guard let value = defaults.string(forKey: key) else { return fallbackURL }
        guard let url = ServerAddressNormalizer.normalize(value) else {
            defaults.removeObject(forKey: key)
            return fallbackURL
        }
        if value != url.absoluteString {
            defaults.set(url.absoluteString, forKey: key)
        }
        return url
    }
}
