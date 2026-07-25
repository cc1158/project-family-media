import FamilyMediaCore
import Security
import XCTest

final class KeychainJellyfinSessionStoreTests: XCTestCase {
    func testSessionIsAddedUpdatedAndStoredAsThisDeviceOnly() throws {
        let service = "com.senhu.familymedia.tests.\(UUID().uuidString)"
        let account = "session"
        let store = KeychainJellyfinSessionStore(service: service, account: account)
        defer { store.clear() }

        let first = JellyfinSession(
            accessToken: "first-token",
            userID: "user-1",
            username: "妈妈"
        )
        let replacement = JellyfinSession(
            accessToken: "replacement-token",
            userID: "user-2",
            username: "爸爸"
        )

        try store.save(first)
        XCTAssertEqual(store.load(), first)

        try store.save(replacement)
        XCTAssertEqual(store.load(), replacement)

        XCTAssertFalse(store.clear(ifMatching: first))
        XCTAssertEqual(store.load(), replacement)

        var result: CFTypeRef?
        let status = SecItemCopyMatching(
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnAttributes as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ] as CFDictionary,
            &result
        )
        XCTAssertEqual(status, errSecSuccess)
        let attributes = result as? [String: Any]
        XCTAssertEqual(
            attributes?[kSecAttrAccessible as String] as? String,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
        )

        XCTAssertTrue(store.clear(ifMatching: replacement))
        XCTAssertNil(store.load())
    }

    func testConditionalClearCannotDeleteConcurrentReplacement() throws {
        let service = "com.senhu.familymedia.tests.\(UUID().uuidString)"
        let store = KeychainJellyfinSessionStore(service: service, account: "session")
        defer { store.clear() }
        let expired = JellyfinSession(
            accessToken: "expired-token",
            userID: "user-1",
            username: "妈妈"
        )
        let replacement = JellyfinSession(
            accessToken: "replacement-token",
            userID: "user-1",
            username: "妈妈"
        )

        for _ in 0..<25 {
            try store.save(expired)
            DispatchQueue.concurrentPerform(iterations: 2) { operation in
                if operation == 0 {
                    try? store.save(replacement)
                } else {
                    _ = store.clear(ifMatching: expired)
                }
            }
            XCTAssertEqual(store.load(), replacement)
        }
    }
}
