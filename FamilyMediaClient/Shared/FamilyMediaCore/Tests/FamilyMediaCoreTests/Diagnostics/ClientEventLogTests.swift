import Foundation
import Testing
@testable import FamilyMediaCore

struct ClientEventLogTests {
    @Test func ringBufferKeepsNewestEventsInOrder() {
        let log = ClientEventLog(capacity: 2)
        let first = UUID()
        let second = UUID()
        let third = UUID()

        record(log, code: "browse.first", operationID: first)
        record(log, code: "browse.second", operationID: second)
        record(log, code: "browse.third", operationID: third)

        #expect(log.recentEvents(limit: 10).map(\.operationID) == [second, third])
        #expect(log.recentEvents(limit: 1).map(\.operationID) == [third])
    }

    @Test func eventCodeRejectsFreeFormSensitiveText() {
        let event = ClientDiagnosticEvent(
            category: .network,
            code: "https://nas.example/private/file.jpg?token=secret",
            operationID: UUID(),
            outcome: .failed,
            sourceID: .familyMedia,
            httpStatusCode: 503
        )

        #expect(event.code == "invalid_event_code")
        #expect(event.httpStatusClass == .serverError)
        #expect(!event.diagnosticText.contains("nas.example"))
        #expect(!event.diagnosticText.contains("secret"))
    }

    private func record(
        _ log: ClientEventLog,
        code: String,
        operationID: UUID
    ) {
        log.record(
            category: .browse,
            code: code,
            operationID: operationID,
            outcome: .info,
            sourceID: .familyMedia
        )
    }
}
