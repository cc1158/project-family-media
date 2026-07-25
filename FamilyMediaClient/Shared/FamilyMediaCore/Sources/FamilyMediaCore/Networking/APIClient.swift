import Foundation

public enum APIClientError: Error, Equatable, LocalizedError, Sendable {
    case invalidResponse
    case unacceptableStatusCode(Int, String?)
    case decodingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "服务端返回了无法识别的响应。"
        case .unacceptableStatusCode(let statusCode, let code):
            if let code, !code.isEmpty {
                return "服务端返回异常状态码：\(statusCode)，错误：\(code)。"
            }
            return "服务端返回异常状态码：\(statusCode)。"
        case .decodingFailed(let message):
            return "服务端数据格式无法解析：\(message)"
        }
    }
}

public struct APIClient: Sendable {
    private let configuration: APIConfiguration
    private let httpClient: any HTTPClient
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let eventLogger: any ClientEventLogging

    public init(
        configuration: APIConfiguration,
        httpClient: any HTTPClient = MediaNetworkSession.shared,
        decoder: JSONDecoder = JSONDecoder.familyMedia,
        encoder: JSONEncoder = JSONEncoder(),
        eventLogger: any ClientEventLogging = ClientEventLog.shared
    ) {
        self.configuration = configuration
        self.httpClient = httpClient
        self.decoder = decoder
        self.encoder = encoder
        self.eventLogger = eventLogger
    }

    public func get<Response: Decodable & Sendable>(
        _ path: String,
        queryItems: [URLQueryItem] = [],
        as type: Response.Type = Response.self
    ) async throws -> Response {
        let request = try makeRequest(path: path, method: "GET", queryItems: queryItems)
        return try await send(request, as: Response.self)
    }

    public func post<Response: Decodable & Sendable>(
        _ path: String,
        as type: Response.Type = Response.self
    ) async throws -> Response {
        let request = try makeRequest(path: path, method: "POST")
        return try await send(request, as: Response.self)
    }

    public func post<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        _ path: String,
        body: Body,
        as type: Response.Type = Response.self
    ) async throws -> Response {
        var request = try makeRequest(path: path, method: "POST")
        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await send(request, as: Response.self)
    }

    private func send<Response: Decodable & Sendable>(
        _ request: URLRequest,
        as type: Response.Type = Response.self
    ) async throws -> Response {
        let operationID = UUID()
        eventLogger.record(
            category: .network,
            code: "network.family.request",
            operationID: operationID,
            outcome: .started,
            sourceID: .familyMedia
        )
        do {
            let (data, response) = try await httpClient.data(for: request)
            guard (200..<300).contains(response.statusCode) else {
                let errorCode = try? decoder.decode(APIErrorResponse.self, from: data).error
                throw APIClientError.unacceptableStatusCode(response.statusCode, errorCode)
            }
            let result = try decoder.decode(Response.self, from: data)
            eventLogger.record(
                category: .network,
                code: "network.family.request",
                operationID: operationID,
                outcome: .succeeded,
                sourceID: .familyMedia,
                httpStatusCode: response.statusCode
            )
            return result
        } catch is CancellationError {
            eventLogger.record(
                category: .network,
                code: "network.family.request",
                operationID: operationID,
                outcome: .cancelled,
                sourceID: .familyMedia
            )
            throw CancellationError()
        } catch let error as APIClientError {
            let statusCode: Int?
            if case .unacceptableStatusCode(let code, _) = error {
                statusCode = code
            } else {
                statusCode = nil
            }
            eventLogger.record(
                category: .network,
                code: "network.family.request",
                operationID: operationID,
                outcome: .failed,
                sourceID: .familyMedia,
                httpStatusCode: statusCode
            )
            throw error
        } catch {
            eventLogger.record(
                category: .network,
                code: "network.family.request",
                operationID: operationID,
                outcome: .failed,
                sourceID: .familyMedia
            )
            if error is DecodingError {
                throw APIClientError.decodingFailed(error.localizedDescription)
            }
            throw error
        }
    }

    private func makeRequest(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = []
    ) throws -> URLRequest {
        let normalizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path

        guard var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false) else {
            throw APIClientError.invalidResponse
        }

        components.percentEncodedPath = components.percentEncodedPath.appendingPathComponent(normalizedPath)

        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw APIClientError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}

private extension String {
    func appendingPathComponent(_ component: String) -> String {
        let basePath = hasSuffix("/") ? String(dropLast()) : self
        return "\(basePath)/\(component)"
    }
}
