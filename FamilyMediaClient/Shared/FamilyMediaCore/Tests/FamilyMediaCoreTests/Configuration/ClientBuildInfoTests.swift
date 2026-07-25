import Testing
@testable import FamilyMediaCore

struct ClientBuildInfoTests {
    @Test func buildInfoProvidesStableDiagnosticText() {
        let info = ClientBuildInfo(version: "1.2.3", build: "45")

        #expect(info.displayText == "家映 1.2.3（45）")
    }

    @Test func jellyfinIdentityRejectsHeaderBreakingCharactersAndEmptyValues() {
        let identity = JellyfinClientIdentity(
            clientName: "Jiaying\nClient",
            deviceName: "\"iPhone\"",
            version: ""
        )

        #expect(identity.clientName == "Jiaying Client")
        #expect(identity.deviceName == "'iPhone'")
        #expect(identity.version == "unknown")
    }
}
