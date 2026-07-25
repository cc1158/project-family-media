import Foundation
import Security

public struct JellyfinSession: Codable, Equatable, Sendable {
    public let accessToken: String
    public let userID: String
    public let username: String

    public init(accessToken: String, userID: String, username: String) {
        self.accessToken = accessToken
        self.userID = userID
        self.username = username
    }
}

public protocol JellyfinSessionStoring: Sendable {
    func load() -> JellyfinSession?
    func save(_ session: JellyfinSession) throws
    func clear()
    @discardableResult
    func clear(ifMatching session: JellyfinSession) -> Bool
}

public final class KeychainJellyfinSessionStore: JellyfinSessionStoring, @unchecked Sendable {
    private let service: String
    private let account: String
    private let lock = NSLock()

    public init(service: String = "com.senhu.familymedia.jellyfin", account: String = "session") {
        self.service = service
        self.account = account
    }

    public func load() -> JellyfinSession? {
        lock.withLock { loadUnlocked() }
    }

    public func save(_ session: JellyfinSession) throws {
        try lock.withLock {
            try saveUnlocked(session)
        }
    }

    public func clear() {
        lock.withLock {
            _ = SecItemDelete(baseQuery as CFDictionary)
        }
    }

    @discardableResult
    public func clear(ifMatching session: JellyfinSession) -> Bool {
        lock.withLock {
            guard loadUnlocked() == session else { return false }
            return SecItemDelete(baseQuery as CFDictionary) == errSecSuccess
        }
    }

    private func loadUnlocked() -> JellyfinSession? {
        var result: CFTypeRef?
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(JellyfinSession.self, from: data)
    }

    private func saveUnlocked(_ session: JellyfinSession) throws {
        let data = try JSONEncoder().encode(session)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            attributes as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw JellyfinError.credentialStorageFailed
        }

        var query = baseQuery
        attributes.forEach { query[$0.key] = $0.value }
        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else {
            throw JellyfinError.credentialStorageFailed
        }
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}
