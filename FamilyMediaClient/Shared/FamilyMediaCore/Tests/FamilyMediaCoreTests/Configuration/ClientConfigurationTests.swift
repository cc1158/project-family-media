import Foundation
import Testing
@testable import FamilyMediaCore

struct ClientConfigurationTests {
    @Test func bundledAddressFallsBackInsteadOfCrashingAndNormalizesValidInput() {
        #expect(
            ClientAppConfiguration.normalizedServerBaseURL(from: "not-a-url").absoluteString
                == ClientAppConfiguration.defaultServerBaseURL
        )
        #expect(
            ClientAppConfiguration.normalizedServerBaseURL(
                from: " HTTPS://NAS.EXAMPLE.COM:443/media/ "
            ).absoluteString == "https://nas.example.com/media"
        )
        #expect(
            ClientAppConfiguration.normalizedServerBaseURL(
                from: "https://user:secret@nas.example.com"
            ).absoluteString == ClientAppConfiguration.defaultServerBaseURL
        )
    }

    @Test func familyConfigurationRepairsLegacyAddressAndDropsCorruptValue() {
        let defaults = isolatedDefaults()
        let key = "test.family.address"
        let fallback = URL(string: "http://192.168.1.20:8080")!
        defaults.set(" HTTPS://NAS.EXAMPLE.COM:443/media/ ", forKey: key)
        let store = ServerConfigurationStore(defaults: defaults, key: key, fallbackURL: fallback)

        #expect(store.serverBaseURL.absoluteString == "https://nas.example.com/media")
        #expect(defaults.string(forKey: key) == "https://nas.example.com/media")

        defaults.set("ftp://nas.example.com/library", forKey: key)
        #expect(store.serverBaseURL == fallback)
        #expect(defaults.object(forKey: key) == nil)
    }

    @Test func jellyfinConfigurationRepairsAddressAndRegeneratesBlankDeviceID() {
        let defaults = isolatedDefaults()
        let urlKey = "test.jellyfin.address"
        let deviceKey = "test.jellyfin.device"
        defaults.set(" HTTP://NAS.EXAMPLE.COM:80/jellyfin/ ", forKey: urlKey)
        defaults.set("   ", forKey: deviceKey)
        let store = JellyfinConfigurationStore(
            defaults: defaults,
            urlKey: urlKey,
            deviceKey: deviceKey,
            fallbackURL: URL(string: "http://192.168.1.20:8096")!
        )

        #expect(store.serverBaseURL.absoluteString == "http://nas.example.com/jellyfin")
        #expect(defaults.string(forKey: urlKey) == "http://nas.example.com/jellyfin")
        #expect(!store.deviceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(defaults.string(forKey: deviceKey) == store.deviceID)
    }

    @Test func localNetworkConfigurationNeverCrashesForInvalidHostOrPort() {
        #expect(
            APIConfiguration.localNetwork(host: " 192.168.1.30 ", port: 9090)
                .baseURL.absoluteString == "http://192.168.1.30:9090"
        )
        #expect(
            APIConfiguration.localNetwork(host: "", port: -1).baseURL.absoluteString
                == ClientAppConfiguration.defaultServerBaseURL
        )
    }
}
