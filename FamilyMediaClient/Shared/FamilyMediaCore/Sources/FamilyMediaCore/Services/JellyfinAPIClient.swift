import Foundation

final class JellyfinAPIClient: @unchecked Sendable {
    let configuration: JellyfinConfigurationStore
    private let sessions: any JellyfinSessionStoring
    private let httpClient: any HTTPClient
    private let identity: JellyfinClientIdentity
    private let onSessionInvalidated: @MainActor @Sendable () -> Void
    private let eventLogger: any ClientEventLogging

    init(
        configuration: JellyfinConfigurationStore,
        sessions: any JellyfinSessionStoring,
        httpClient: any HTTPClient,
        identity: JellyfinClientIdentity,
        eventLogger: any ClientEventLogging = ClientEventLog.shared,
        onSessionInvalidated: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        self.configuration = configuration
        self.sessions = sessions
        self.httpClient = httpClient
        self.identity = identity
        self.eventLogger = eventLogger
        self.onSessionInvalidated = onSessionInvalidated
    }

    var currentSession: JellyfinSession? {
        guard let session = sessions.load() else {
            configuration.clearSessionServerBinding()
            return nil
        }

        let currentServerURL = configuration.serverBaseURL
        if let sessionServerURL = configuration.persistedSessionServerURL {
            guard sessionServerURL == currentServerURL else {
                clearSession()
                return nil
            }
            return session
        }

        // Versions before server-bound sessions already persisted a stable device
        // identity during login. Preserve those upgrades, while treating a Keychain
        // item without any installation identity as residue from a removed app.
        guard configuration.hasPersistedDeviceID else {
            clearSession()
            return nil
        }
        configuration.bindSessionToCurrentServer()
        return session
    }
    var configurationRevision: UInt64 { configuration.configurationRevision }

    func saveSession(
        _ session: JellyfinSession,
        ifConfigurationRevision expectedRevision: UInt64
    ) throws {
        try Task.checkCancellation()
        guard configurationRevision == expectedRevision else {
            throw CancellationError()
        }
        try sessions.save(session)
        configuration.bindSessionToCurrentServer()
        guard configurationRevision == expectedRevision else {
            clearSession(ifMatching: session)
            throw CancellationError()
        }
    }
    func clearSession() {
        sessions.clear()
        configuration.clearSessionServerBinding()
    }

    func send<Response: Decodable & Sendable>(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        authenticated: Bool = true
    ) async throws -> Response {
        let operationID = UUID()
        eventLogger.record(
            category: .network,
            code: "network.jellyfin.request",
            operationID: operationID,
            outcome: .started,
            sourceID: .jellyfin
        )
        let requestRevision = configurationRevision
        guard let url = makeURL(path: path, query: queryItems) else {
            eventLogger.record(
                category: .network,
                code: "network.jellyfin.request",
                operationID: operationID,
                outcome: .failed,
                sourceID: .jellyfin
            )
            throw JellyfinError.invalidAddress
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let requestSession = authenticated ? currentSession : nil
        request.setValue(
            authorizationHeader(token: requestSession?.accessToken),
            forHTTPHeaderField: "Authorization"
        )
        do {
            let (data, response) = try await httpClient.data(for: request)
            try validateConfiguration(requestRevision)
            try validate(response.statusCode, authenticated: authenticated, requestSession: requestSession)
            guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
                throw JellyfinError.invalidResponse
            }
            eventLogger.record(
                category: .network,
                code: "network.jellyfin.request",
                operationID: operationID,
                outcome: .succeeded,
                sourceID: .jellyfin,
                httpStatusCode: response.statusCode
            )
            return decoded
        } catch is CancellationError {
            eventLogger.record(
                category: .network,
                code: "network.jellyfin.request",
                operationID: operationID,
                outcome: .cancelled,
                sourceID: .jellyfin
            )
            throw CancellationError()
        } catch {
            eventLogger.record(
                category: .network,
                code: "network.jellyfin.request",
                operationID: operationID,
                outcome: .failed,
                sourceID: .jellyfin,
                httpStatusCode: statusCode(for: error)
            )
            throw error
        }
    }

    func sendNoContent(path: String, body: Data) async throws {
        let logsLifecycleBoundary = !path.hasSuffix("/Progress")
        let operationID = UUID()
        if logsLifecycleBoundary {
            logLifecycle(operationID: operationID, outcome: .started)
        }
        let requestRevision = configurationRevision
        guard let url = makeURL(path: path) else {
            if logsLifecycleBoundary {
                logLifecycle(operationID: operationID, outcome: .failed)
            }
            throw JellyfinError.invalidAddress
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let requestSession = currentSession
        request.setValue(
            authorizationHeader(token: requestSession?.accessToken),
            forHTTPHeaderField: "Authorization"
        )
        do {
            let (_, response) = try await httpClient.data(for: request)
            try validateConfiguration(requestRevision)
            try validate(response.statusCode, authenticated: true, requestSession: requestSession)
            if logsLifecycleBoundary {
                logLifecycle(
                    operationID: operationID,
                    outcome: .succeeded,
                    httpStatusCode: response.statusCode
                )
            }
        } catch is CancellationError {
            if logsLifecycleBoundary {
                logLifecycle(operationID: operationID, outcome: .cancelled)
            }
            throw CancellationError()
        } catch {
            if logsLifecycleBoundary {
                logLifecycle(
                    operationID: operationID,
                    outcome: .failed,
                    httpStatusCode: statusCode(for: error)
                )
            }
            throw error
        }
    }

    func makeURL(path: String, query: [URLQueryItem] = []) -> URL? {
        var components = URLComponents(url: configuration.serverBaseURL, resolvingAgainstBaseURL: false)
        let currentPath = components?.percentEncodedPath ?? ""
        let base = currentPath.hasSuffix("/") ? String(currentPath.dropLast()) : currentPath
        let normalizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        components?.percentEncodedPath = "\(base)/\(normalizedPath)"
        components?.queryItems = query.isEmpty ? nil : query
        return components?.url
    }

    func authenticatedPlaybackURL(from path: String, token: String) -> URL? {
        JellyfinPlaybackURLBuilder(baseURL: configuration.serverBaseURL)
            .authenticatedURL(from: path, token: token)
    }

    func resourceRequest(for url: URL) -> MediaResourceRequest {
        guard let session = currentSession else {
            return .unauthenticated(url: url)
        }
        var request = URLRequest(url: url)
        request.setValue(
            authorizationHeader(token: session.accessToken),
            forHTTPHeaderField: "Authorization"
        )
        var partitionHasher = Hasher()
        partitionHasher.combine(configuration.serverBaseURL)
        partitionHasher.combine(session.userID)
        partitionHasher.combine(session.accessToken)
        return MediaResourceRequest(
            request: request,
            cachePartition: "jellyfin-\(partitionHasher.finalize())",
            unauthorizedResponseHandler: { [weak self] in
                self?.invalidateSession(ifMatching: session)
            }
        )
    }

    private func validate(
        _ statusCode: Int,
        authenticated: Bool,
        requestSession: JellyfinSession?
    ) throws {
        if statusCode == 401 {
            if authenticated {
                if let requestSession {
                    invalidateSession(ifMatching: requestSession)
                }
                throw JellyfinError.unauthorized
            }
            throw JellyfinError.invalidCredentials
        }
        guard (200..<300).contains(statusCode) else { throw JellyfinError.server(statusCode) }
    }

    private func statusCode(for error: Error) -> Int? {
        switch error as? JellyfinError {
        case .server(let code): code
        case .unauthorized: 401
        default: nil
        }
    }

    private func logLifecycle(
        operationID: UUID,
        outcome: ClientEventOutcome,
        httpStatusCode: Int? = nil
    ) {
        eventLogger.record(
            category: .network,
            code: "network.jellyfin.lifecycle",
            operationID: operationID,
            outcome: outcome,
            sourceID: .jellyfin,
            httpStatusCode: httpStatusCode
        )
    }

    private func invalidateSession(ifMatching requestSession: JellyfinSession) {
        guard sessions.clear(ifMatching: requestSession) else { return }
        configuration.clearSessionServerBinding()
        Task { @MainActor in
            onSessionInvalidated()
        }
    }

    private func clearSession(ifMatching session: JellyfinSession) {
        guard sessions.clear(ifMatching: session) else { return }
        configuration.clearSessionServerBinding()
    }

    private func validateConfiguration(_ expectedRevision: UInt64) throws {
        try Task.checkCancellation()
        guard configurationRevision == expectedRevision else {
            throw CancellationError()
        }
    }

    private func authorizationHeader(token: String?) -> String {
        var value = "MediaBrowser Client=\"\(identity.clientName)\", Device=\"\(identity.deviceName)\", DeviceId=\"\(configuration.deviceID)\", Version=\"\(identity.version)\""
        if let token { value += ", Token=\"\(token)\"" }
        return value
    }
}
