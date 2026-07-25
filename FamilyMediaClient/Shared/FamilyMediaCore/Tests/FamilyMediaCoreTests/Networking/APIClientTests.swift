import Foundation
import Testing
@testable import FamilyMediaCore

struct APIClientTests {
    @Test func decodesPagedMediaList() async throws {
        let data = """
        {
          "items": [
            {
              "id": "video-1",
              "name": "birthday.mp4",
              "kind": "video",
              "size": 1024,
              "modified": "2026-05-19T10:00:00Z",
              "url": "http://192.168.1.20:8080/media/original/birthday.mp4",
              "thumbnailURL": "http://192.168.1.20:8080/media/thumbnails/birthday.jpg",
              "mediaPath": "birthday.mp4",
              "thumbnailStatus": "ready"
            },
            {
              "id": "photo-1",
              "name": "family.jpg",
              "kind": "photo",
              "size": 2048,
              "modified": "2026-05-19T10:01:00Z",
              "url": "http://192.168.1.20:8080/media/original/family.jpg",
              "thumbnailURL": "",
              "mediaPath": "family.jpg",
              "thumbnailStatus": "pending"
            }
          ],
          "nextCursor": "cursor-2",
          "hasMore": true
        }
        """.data(using: .utf8)!

        let client = APIClient(
            configuration: .localNetwork(host: "192.168.1.20"),
            httpClient: StubHTTPClient(statusCode: 200, data: data)
        )

        let response: MediaPage = try await client.get("/api/v1/media")

        #expect(response.items.count == 2)
        #expect(response.items[0].name == "birthday.mp4")
        #expect(response.items[0].thumbnailStatus == .ready)
        #expect(response.items[1].thumbnailURL == nil)
        #expect(response.nextCursor == "cursor-2")
        #expect(response.hasMore)
    }

    @Test func throwsForNonSuccessfulStatusCode() async throws {
        let client = APIClient(
            configuration: .localNetwork(host: "192.168.1.20"),
            httpClient: StubHTTPClient(statusCode: 500, data: Data())
        )

        await #expect(throws: APIClientError.unacceptableStatusCode(500, nil)) {
            let _: MediaPage = try await client.get("/api/v1/media")
        }
    }

    @Test func decodingErrorPreservesUnderlyingMessage() async throws {
        let client = APIClient(
            configuration: .localNetwork(host: "192.168.1.20"),
            httpClient: StubHTTPClient(statusCode: 200, data: #"{"items":[]}"#.data(using: .utf8)!)
        )

        do {
            let _: MediaPage = try await client.get("/api/v1/media")
            Issue.record("Expected decoding failure")
        } catch let error as APIClientError {
            guard case .decodingFailed(let message) = error else {
                Issue.record("Expected decodingFailed, got \(error)")
                return
            }

            #expect(!message.isEmpty)
        }
    }

    @Test func mediaServiceUsesPagedBrowseEndpointAndContainerContext() async throws {
        let data = #"{"items":[],"nextCursor":"","hasMore":false}"#.data(using: .utf8)!
        let httpClient = RecordingHTTPClient(statusCode: 200, data: data)
        let store = ServerConfigurationStore(
            defaults: isolatedDefaults(),
            fallbackURL: URL(string: "http://192.168.1.20:8080")!
        )
        let service = MediaService(configurationProvider: store, httpClient: httpClient)

        _ = try await service.fetchMedia(filter: .all, request: MediaPageRequest(limit: 50))
        _ = try await service.fetchMedia(filter: .photos, request: MediaPageRequest(limit: 50, cursor: "abc"))
        _ = try await service.fetchMedia(
            containerID: "family-folder:path:a2lkcw",
            filter: .videos,
            request: MediaPageRequest(limit: 20, sort: .nameDescending)
        )

        #expect(httpClient.paths == ["/api/v1/browse", "/api/v1/browse", "/api/v1/browse"])
        #expect(httpClient.queries[0] == "limit=50")
        #expect(httpClient.queries[1] == "limit=50&cursor=abc&kind=photo")
        #expect(
            httpClient.queries[2]
                == "limit=20&sort=name_desc&kind=video&containerID=family-folder:path:a2lkcw"
        )
    }

    @Test func mediaServiceBuildsTimelineIndexAndMonthQueries() async throws {
        let defaults = isolatedDefaults()
        let configuration = ServerConfigurationStore(
            defaults: defaults,
            fallbackURL: URL(string: "http://192.168.1.20:8080")!
        )
        let request = MediaTimelineRequest(
            containerID: "family-folder:path:a2lkcw",
            filter: .photos,
            timeZone: "Asia/Shanghai",
            direction: .oldest
        )

        let indexHTTP = RecordingHTTPClient(
            statusCode: 200,
            data: #"{"dateSemantics":"captured","timeZone":"Asia/Shanghai","years":[]}"#.data(using: .utf8)!
        )
        let indexService = MediaService(configurationProvider: configuration, httpClient: indexHTTP)
        _ = try await indexService.fetchTimelineIndex(request: request)

        #expect(indexHTTP.paths == ["/api/v1/timeline/index"])
        #expect(indexHTTP.queries[0].contains("timeZone=Asia/Shanghai"))
        #expect(indexHTTP.queries[0].contains("sort=captured_asc"))
        #expect(indexHTTP.queries[0].contains("kind=photo"))

        let pageHTTP = RecordingHTTPClient(
            statusCode: 200,
            data: #"{"items":[],"nextCursor":"","hasMore":false}"#.data(using: .utf8)!
        )
        let pageService = MediaService(configurationProvider: configuration, httpClient: pageHTTP)
        _ = try await pageService.fetchTimelineMonth(
            key: "2026-07",
            request: request,
            page: MediaPageRequest(limit: 25, cursor: "next")
        )

        #expect(pageHTTP.paths == ["/api/v1/browse"])
        #expect(pageHTTP.queries[0].contains("scope=recursive"))
        #expect(pageHTTP.queries[0].contains("bucket=2026-07"))
        #expect(pageHTTP.queries[0].contains("limit=25"))
        #expect(pageHTTP.queries[0].contains("cursor=next"))
    }

    @Test func decodesScanStatus() async throws {
        let data = """
        {
          "jobId": "scan-1",
          "status": "completed",
          "startedAt": "2026-05-19T10:00:00Z",
          "finishedAt": "2026-05-19T10:00:10Z",
          "scannedFiles": 10,
          "indexedFiles": 9,
          "deletedFiles": 1,
          "metadataExtracted": 6,
          "metadataMissing": 2,
          "metadataFailed": 1,
          "metadataFallback": 3,
          "thumbnailPending": 2,
          "thumbnailGenerated": 7,
          "thumbnailFailed": 1,
          "thumbnailError": "kids/broken.mp4: ffmpeg not found",
          "error": ""
        }
        """.data(using: .utf8)!

        let client = APIClient(
            configuration: .localNetwork(host: "192.168.1.20"),
            httpClient: StubHTTPClient(statusCode: 200, data: data)
        )

        let status: ScanStatus = try await client.get("/api/v1/admin/scan/status")

        #expect(status.jobId == "scan-1")
        #expect(status.status == .completed)
        #expect(status.scannedFiles == 10)
        #expect(status.metadataExtracted == 6)
        #expect(status.metadataFallback == 3)
        #expect(status.thumbnailGenerated == 7)
        #expect(status.thumbnailError == "kids/broken.mp4: ffmpeg not found")
    }

    @Test func decodesScanStatusWithoutOptionalCounters() async throws {
        let data = """
        {
          "jobId": "scan-1",
          "status": "idle",
          "startedAt": null,
          "finishedAt": null,
          "error": ""
        }
        """.data(using: .utf8)!

        let client = APIClient(
            configuration: .localNetwork(host: "192.168.1.20"),
            httpClient: StubHTTPClient(statusCode: 200, data: data)
        )

        let status: ScanStatus = try await client.get("/api/v1/admin/scan/status")

        #expect(status.status == .idle)
        #expect(status.scannedFiles == nil)
        #expect(status.thumbnailGenerated == nil)
        #expect(status.thumbnailError == "")
    }

    @Test func decodesServerErrorCode() async throws {
        let client = APIClient(
            configuration: .localNetwork(host: "192.168.1.20"),
            httpClient: StubHTTPClient(statusCode: 400, data: #"{"error":"invalid_cursor"}"#.data(using: .utf8)!)
        )

        await #expect(throws: APIClientError.unacceptableStatusCode(400, "invalid_cursor")) {
            let _: MediaPage = try await client.get("/api/v1/media")
        }
    }

    @Test func mediaServiceRegeneratesThumbnailWithOptionalOffset() async throws {
        let data = #"{"id":"media-1","thumbnailStatus":"ready"}"#.data(using: .utf8)!
        let httpClient = RecordingHTTPClient(statusCode: 200, data: data)
        let service = MediaService(
            configurationProvider: ServerConfigurationStore(
                defaults: isolatedDefaults(),
                fallbackURL: URL(string: "http://192.168.1.20:8080")!
            ),
            httpClient: httpClient
        )

        let response = try await service.regenerateThumbnail(
            mediaID: "media-1",
            request: ThumbnailRegenerationRequest(timeOffsetSeconds: 12)
        )

        #expect(response.id == "media-1")
        #expect(response.thumbnailStatus == .ready)
        #expect(httpClient.paths == ["/api/v1/admin/media/media-1/thumbnail/regenerate"])
        #expect(httpClient.bodies.first == #"{"timeOffsetSeconds":12}"#)
    }

    @Test func mediaServiceClearsGeneratedDataWithOptionalRescan() async throws {
        let data = #"{"status":"cleared","clearedDirectories":2,"scan":{"jobId":"scan-new","status":"running"}}"#.data(using: .utf8)!
        let httpClient = RecordingHTTPClient(statusCode: 200, data: data)
        let service = MediaService(
            configurationProvider: ServerConfigurationStore(
                defaults: isolatedDefaults(),
                fallbackURL: URL(string: "http://192.168.1.20:8080")!
            ),
            httpClient: httpClient
        )

        let response = try await service.clearGeneratedData(rescan: true)

        #expect(response.status == "cleared")
        #expect(response.clearedDirectories == 2)
        #expect(response.scan?.jobId == "scan-new")
        #expect(httpClient.paths == ["/api/v1/admin/data/clear"])
        #expect(httpClient.bodies == [#"{"rescan":true}"#])
    }

    @Test func mediaServiceEncodesThumbnailRegenerationMediaIDAsPathSegment() async throws {
        let data = #"{"id":"folder/media 1","thumbnailStatus":"ready"}"#.data(using: .utf8)!
        let httpClient = RecordingHTTPClient(statusCode: 200, data: data)
        let service = MediaService(
            configurationProvider: ServerConfigurationStore(
                defaults: isolatedDefaults(),
                fallbackURL: URL(string: "http://192.168.1.20:8080")!
            ),
            httpClient: httpClient
        )

        _ = try await service.regenerateThumbnail(
            mediaID: "folder/media 1",
            request: ThumbnailRegenerationRequest()
        )

        #expect(httpClient.encodedPaths == ["/api/v1/admin/media/folder%2Fmedia%201/thumbnail/regenerate"])
    }


    @Test func serverConfigurationStorePersistsURL() {
        let defaults = isolatedDefaults()
        let fallbackURL = URL(string: "http://192.168.1.20:8080")!
        let store = ServerConfigurationStore(defaults: defaults, fallbackURL: fallbackURL)

        #expect(store.serverBaseURL == fallbackURL)

        let newURL = URL(string: "http://192.168.1.30:9090")!
        store.serverBaseURL = newURL

        #expect(store.serverBaseURL == newURL)
        #expect(store.configurationRevision == 1)

        store.serverBaseURL = newURL
        #expect(store.configurationRevision == 1)
    }

    @Test func mediaServiceRejectsResponseFromPreviousAddress() async {
        let configuration = ServerConfigurationStore(
            defaults: isolatedDefaults(),
            fallbackURL: URL(string: "http://192.168.1.20:8080")!
        )
        let httpClient = AddressChangingHTTPClient(
            configuration: configuration,
            replacementURL: URL(string: "http://192.168.1.30:8080")!,
            data: #"{"status":"ok"}"#.data(using: .utf8)!
        )
        let service = MediaService(
            configurationProvider: configuration,
            httpClient: httpClient
        )

        do {
            _ = try await service.checkHealth()
            Issue.record("旧地址的响应不应被接受")
        } catch {
            #expect(TaskCancellation.matches(error))
        }
    }

    @Test func productionNetworkSessionDoesNotUsePersistentURLCache() {
        let configuration = MediaNetworkSession.shared.configuration

        #expect(configuration.urlCache == nil)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
        #expect(configuration.timeoutIntervalForRequest == 15)
    }

    @Test func mediaServiceAcceptsCompatibleHealthContract() async throws {
        let data = #"{"status":"ok","apiVersion":2,"capabilities":["folder_browse","generated_data_clear","browse_sort"]}"#.data(using: .utf8)!
        let service = MediaService(
            configurationProvider: ServerConfigurationStore(
                defaults: isolatedDefaults(),
                fallbackURL: URL(string: "http://192.168.1.20:8080")!
            ),
            httpClient: StubHTTPClient(statusCode: 200, data: data)
        )

        let status = try await service.checkHealth()

        #expect(status.apiVersion == 2)
    }

    @Test func mediaServiceRejectsReachableLegacyServerBeforeBrowsing() async {
        let data = #"{"status":"ok"}"#.data(using: .utf8)!
        let service = MediaService(
            configurationProvider: ServerConfigurationStore(
                defaults: isolatedDefaults(),
                fallbackURL: URL(string: "http://192.168.1.20:8080")!
            ),
            httpClient: StubHTTPClient(statusCode: 200, data: data)
        )

        await #expect(throws: FamilyMediaCompatibilityError.serverUpdateRequired) {
            _ = try await service.checkHealth()
        }
    }
}

private final class AddressChangingHTTPClient: HTTPClient, @unchecked Sendable {
    private let configuration: ServerConfigurationStore
    private let replacementURL: URL
    private let data: Data

    init(
        configuration: ServerConfigurationStore,
        replacementURL: URL,
        data: Data
    ) {
        self.configuration = configuration
        self.replacementURL = replacementURL
        self.data = data
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        configuration.serverBaseURL = replacementURL
        return (
            data,
            HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }
}

private final class StubHTTPClient: HTTPClient, @unchecked Sendable {
    private let statusCode: Int
    private let data: Data

    init(statusCode: Int, data: Data) {
        self.statusCode = statusCode
        self.data = data
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}

private final class RecordingHTTPClient: HTTPClient, @unchecked Sendable {
    private let statusCode: Int
    private let data: Data
    private(set) var paths: [String] = []
    private(set) var encodedPaths: [String] = []
    private(set) var queries: [String] = []
    private(set) var bodies: [String] = []

    init(statusCode: Int, data: Data) {
        self.statusCode = statusCode
        self.data = data
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        paths.append(request.url!.path)
        encodedPaths.append(
            URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.percentEncodedPath
                ?? request.url!.path(percentEncoded: true)
        )
        queries.append(request.url!.query ?? "")
        if let httpBody = request.httpBody {
            bodies.append(String(data: httpBody, encoding: .utf8) ?? "")
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}
