import Foundation
import Testing
@testable import FamilyMediaCore

struct ClientDiagnosticsReportTests {
    @Test func reportContainsUsefulStateWithoutCredentialsOrQueryTokens() {
        let report = ClientDiagnosticsReport(
            buildInfo: ClientBuildInfo(version: "0.2.0", build: "2"),
            deviceDescription: "iPhone · iOS 18.5",
            familyMediaAddress: "http://admin:secret@192.168.1.20:8080/path?token=family#private",
            familyMediaStatus: .available,
            jellyfinAddress: "https://nas.example.com/jellyfin?api_key=jellyfin-secret",
            jellyfinStatus: .unavailable,
            isJellyfinLoggedIn: true
        )

        #expect(report.text.contains("家映 0.2.0（2）"))
        #expect(report.text.contains("http://192.168.1.20:8080/path"))
        #expect(report.text.contains("https://nas.example.com/jellyfin"))
        #expect(report.text.contains("Jellyfin 登录：已登录"))
        #expect(!report.text.contains("admin"))
        #expect(!report.text.contains("secret"))
        #expect(!report.text.contains("token="))
        #expect(!report.text.contains("api_key"))
        #expect(!report.text.contains("private"))
    }

    @Test func invalidOrEmptyAddressesAreNotEchoed() {
        let report = ClientDiagnosticsReport(
            buildInfo: ClientBuildInfo(version: "1", build: "1"),
            deviceDescription: "Apple TV",
            familyMediaAddress: "not a URL?password=secret",
            familyMediaStatus: .unchecked,
            jellyfinAddress: "",
            jellyfinStatus: .unchecked,
            isJellyfinLoggedIn: false
        )

        #expect(report.familyMediaAddress == "未设置或格式无效")
        #expect(report.jellyfinAddress == "未设置或格式无效")
        #expect(!report.text.contains("secret"))
    }

    @Test func reportIncludesOnlyNewestThirtyStructuredEvents() {
        let events = (0..<31).map { index in
            ClientDiagnosticEvent(
                timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
                category: .browse,
                code: "browse.event.\(index)",
                operationID: UUID(),
                outcome: .info,
                sourceID: .familyMedia
            )
        }
        let report = ClientDiagnosticsReport(
            buildInfo: ClientBuildInfo(version: "1", build: "1"),
            deviceDescription: "iPhone",
            familyMediaAddress: "https://example.invalid",
            familyMediaStatus: .available,
            jellyfinAddress: "https://example.invalid/jellyfin",
            jellyfinStatus: .available,
            isJellyfinLoggedIn: true,
            recentEvents: events
        )

        #expect(report.recentEvents.count == 30)
        #expect(!report.text.contains("browse.event.0"))
        #expect(report.text.contains("browse.event.30"))
    }

}
