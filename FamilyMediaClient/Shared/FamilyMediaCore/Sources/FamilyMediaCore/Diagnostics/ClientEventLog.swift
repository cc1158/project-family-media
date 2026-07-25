import Foundation
import OSLog

public enum ClientEventCategory: String, Equatable, Sendable {
    case network
    case browse
    case playback
}

public enum ClientEventOutcome: String, Equatable, Sendable {
    case started
    case succeeded
    case cancelled
    case failed
    case info
}

public enum ClientHTTPStatusClass: String, Equatable, Sendable {
    case informational = "1xx"
    case success = "2xx"
    case redirection = "3xx"
    case clientError = "4xx"
    case serverError = "5xx"
    case invalid

    init(statusCode: Int) {
        switch statusCode {
        case 100..<200: self = .informational
        case 200..<300: self = .success
        case 300..<400: self = .redirection
        case 400..<500: self = .clientError
        case 500..<600: self = .serverError
        default: self = .invalid
        }
    }
}

public struct ClientDiagnosticEvent: Equatable, Sendable {
    public let timestamp: Date
    public let category: ClientEventCategory
    public let code: String
    public let operationID: UUID
    public let outcome: ClientEventOutcome
    public let sourceID: MediaSourceID?
    public let playbackMethod: MediaPlaybackMethod?
    public let httpStatusClass: ClientHTTPStatusClass?

    public init(
        timestamp: Date = Date(),
        category: ClientEventCategory,
        code: String,
        operationID: UUID,
        outcome: ClientEventOutcome,
        sourceID: MediaSourceID? = nil,
        playbackMethod: MediaPlaybackMethod? = nil,
        httpStatusCode: Int? = nil
    ) {
        self.timestamp = timestamp
        self.category = category
        self.code = Self.sanitizedCode(code)
        self.operationID = operationID
        self.outcome = outcome
        self.sourceID = sourceID
        self.playbackMethod = playbackMethod
        self.httpStatusClass = httpStatusCode.map(ClientHTTPStatusClass.init)
    }

    public var diagnosticText: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        var parts = [
            formatter.string(from: timestamp),
            category.rawValue,
            code,
            String(operationID.uuidString.prefix(8)),
            outcome.rawValue
        ]
        if let sourceID { parts.append("source=\(sourceID.rawValue)") }
        if let playbackMethod { parts.append("method=\(playbackMethod.rawValue)") }
        if let httpStatusClass { parts.append("http=\(httpStatusClass.rawValue)") }
        return parts.joined(separator: " ")
    }

    private static func sanitizedCode(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789._-")
        let isValid = !value.isEmpty
            && value.count <= 64
            && value.unicodeScalars.allSatisfy(allowed.contains)
        return isValid ? value : "invalid_event_code"
    }
}

public protocol ClientEventLogging: Sendable {
    func record(
        category: ClientEventCategory,
        code: String,
        operationID: UUID,
        outcome: ClientEventOutcome,
        sourceID: MediaSourceID?,
        playbackMethod: MediaPlaybackMethod?,
        httpStatusCode: Int?
    )

    func recentEvents(limit: Int) -> [ClientDiagnosticEvent]
}

public extension ClientEventLogging {
    func record(
        category: ClientEventCategory,
        code: String,
        operationID: UUID,
        outcome: ClientEventOutcome,
        sourceID: MediaSourceID? = nil,
        playbackMethod: MediaPlaybackMethod? = nil,
        httpStatusCode: Int? = nil
    ) {
        record(
            category: category,
            code: code,
            operationID: operationID,
            outcome: outcome,
            sourceID: sourceID,
            playbackMethod: playbackMethod,
            httpStatusCode: httpStatusCode
        )
    }
}

public final class ClientEventLog: ClientEventLogging, @unchecked Sendable {
    public static let shared = ClientEventLog()

    private static let subsystem = "com.senhu.familymedia.client"
    private static let networkLogger = Logger(subsystem: subsystem, category: "network")
    private static let browseLogger = Logger(subsystem: subsystem, category: "browse")
    private static let playbackLogger = Logger(subsystem: subsystem, category: "playback")

    private let lock = NSLock()
    private let capacity: Int
    private var events: [ClientDiagnosticEvent] = []

    public init(capacity: Int = 100) {
        self.capacity = max(1, capacity)
    }

    public func record(
        category: ClientEventCategory,
        code: String,
        operationID: UUID,
        outcome: ClientEventOutcome,
        sourceID: MediaSourceID?,
        playbackMethod: MediaPlaybackMethod?,
        httpStatusCode: Int?
    ) {
        let event = ClientDiagnosticEvent(
            category: category,
            code: code,
            operationID: operationID,
            outcome: outcome,
            sourceID: sourceID,
            playbackMethod: playbackMethod,
            httpStatusCode: httpStatusCode
        )
        lock.lock()
        events.append(event)
        if events.count > capacity {
            events.removeFirst(events.count - capacity)
        }
        lock.unlock()

        let text = event.diagnosticText
        switch category {
        case .network:
            Self.networkLogger.info("\(text, privacy: .public)")
        case .browse:
            Self.browseLogger.info("\(text, privacy: .public)")
        case .playback:
            Self.playbackLogger.info("\(text, privacy: .public)")
        }
    }

    public func recentEvents(limit: Int) -> [ClientDiagnosticEvent] {
        lock.lock()
        defer { lock.unlock() }
        return Array(events.suffix(max(0, limit)))
    }
}
