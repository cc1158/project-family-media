import Foundation
import Testing
@testable import FamilyMediaCore

struct JellyfinServiceTests {
    @Test func logsInWithMediaBrowserHeaderAndPersistsSession() async throws {
        let response = #"{"AccessToken":"token-1","User":{"Id":"user-1","Name":"妈妈"}}"#.data(using: .utf8)!
        let http = JellyfinRecordingHTTPClient(responses: [(200, response)])
        let sessions = InMemoryJellyfinSessionStore()
        let service = makeService(
            http: http,
            sessions: sessions,
            identity: JellyfinClientIdentity(
                clientName: "Jiaying",
                deviceName: "iPhone",
                version: "1.2.3"
            )
        )

        let session = try await service.login(username: "妈妈", password: "secret")

        #expect(session.userID == "user-1")
        #expect(sessions.load()?.accessToken == "token-1")
        #expect(http.requests.first?.url?.path == "/jellyfin/Users/AuthenticateByName")
        #expect(http.requests.first?.value(forHTTPHeaderField: "Authorization")?.contains("MediaBrowser Client=\"Jiaying\"") == true)
        #expect(http.requests.first?.value(forHTTPHeaderField: "Authorization")?.contains("Device=\"iPhone\"") == true)
        #expect(http.requests.first?.value(forHTTPHeaderField: "Authorization")?.contains("Version=\"1.2.3\"") == true)
        #expect(String(data: http.requests.first!.httpBody!, encoding: .utf8)?.contains("secret") == true)
    }

    @Test func loginBindsPersistedSessionToNormalizedServer() async throws {
        let authentication = #"{"AccessToken":"token-1","User":{"Id":"user-1","Name":"妈妈"}}"#.data(using: .utf8)!
        let configuration = JellyfinConfigurationStore(
            defaults: isolatedDefaults(),
            fallbackURL: URL(string: "https://nas.example.com/jellyfin/")!
        )
        let service = JellyfinService(
            configuration: configuration,
            sessions: InMemoryJellyfinSessionStore(),
            httpClient: JellyfinRecordingHTTPClient(responses: [(200, authentication)])
        )

        _ = try await service.login(username: "妈妈", password: "secret")

        #expect(configuration.persistedSessionServerURL?.absoluteString == "https://nas.example.com/jellyfin")
    }

    @Test func legacySessionMigratesOnlyForExistingInstallationIdentity() {
        let configuration = existingInstallationConfiguration()
        let originalSession = JellyfinSession(
            accessToken: "legacy-token",
            userID: "user-1",
            username: "妈妈"
        )
        let sessions = InMemoryJellyfinSessionStore(originalSession)
        let service = JellyfinService(
            configuration: configuration,
            sessions: sessions,
            httpClient: JellyfinRecordingHTTPClient(responses: [])
        )

        #expect(configuration.persistedSessionServerURL == nil)
        #expect(service.currentSession == originalSession)
        #expect(configuration.persistedSessionServerURL == configuration.serverBaseURL)
    }

    @Test func orphanedKeychainSessionIsClearedAfterUserDefaultsRemoval() {
        let configuration = JellyfinConfigurationStore(
            defaults: isolatedDefaults(),
            fallbackURL: URL(string: "https://fallback.example.com/jellyfin")!
        )
        let sessions = InMemoryJellyfinSessionStore(
            JellyfinSession(accessToken: "orphaned-token", userID: "user-1", username: "妈妈")
        )
        let http = JellyfinRecordingHTTPClient(responses: [])
        let service = JellyfinService(
            configuration: configuration,
            sessions: sessions,
            httpClient: http
        )

        #expect(service.currentSession == nil)
        #expect(sessions.load() == nil)
        #expect(configuration.persistedSessionServerURL == nil)
        #expect(http.requests.isEmpty)
    }

    @Test func boundSessionIsClearedBeforeItCanReachDifferentServer() async {
        let configuration = existingInstallationConfiguration(
            serverURL: URL(string: "https://old.example.com/jellyfin")!
        )
        configuration.bindSessionToCurrentServer()
        configuration.serverBaseURL = URL(string: "https://new.example.com/jellyfin")!
        let sessions = InMemoryJellyfinSessionStore(
            JellyfinSession(accessToken: "old-token", userID: "user-1", username: "妈妈")
        )
        let http = JellyfinRecordingHTTPClient(responses: [])
        let service = JellyfinService(
            configuration: configuration,
            sessions: sessions,
            httpClient: http
        )

        await #expect(throws: JellyfinError.notAuthenticated) {
            _ = try await service.fetchMedia(filter: .all, request: MediaPageRequest())
        }
        #expect(sessions.load() == nil)
        #expect(configuration.persistedSessionServerURL == nil)
        #expect(http.requests.isEmpty)
    }

    @Test func loginCannotPersistSessionAfterServerAddressChanges() async {
        let response = #"{"AccessToken":"old-token","User":{"Id":"user-1","Name":"妈妈"}}"#.data(using: .utf8)!
        let sessions = InMemoryJellyfinSessionStore()
        let configuration = JellyfinConfigurationStore(
            defaults: isolatedDefaults(),
            fallbackURL: URL(string: "https://old.example.com/jellyfin")!
        )
        let http = JellyfinAddressChangingHTTPClient(
            configuration: configuration,
            replacementURL: URL(string: "https://new.example.com/jellyfin")!,
            responseData: response
        )
        let service = JellyfinService(
            configuration: configuration,
            sessions: sessions,
            httpClient: http
        )

        do {
            _ = try await service.login(username: "妈妈", password: "secret")
            Issue.record("旧 Jellyfin 地址的登录结果不应被保存")
        } catch {
            #expect(TaskCancellation.matches(error))
        }
        #expect(sessions.load() == nil)
    }

    @Test func mapsLibrariesFoldersAndPlaybackURLsWithPagination() async throws {
        let response = """
        {"Items":[
          {"Id":"folder-1","Name":"家庭视频","Type":"Folder","IsFolder":true,"ImageTags":{"Primary":"tag-1"}},
          {"Id":"video-1","Name":"生日.mp4","Type":"Video","IsFolder":false,"DateCreated":"2026-05-19T10:00:00.123Z"}
        ],"TotalRecordCount":3}
        """.data(using: .utf8)!
        let http = JellyfinRecordingHTTPClient(responses: [(200, response)])
        let sessions = InMemoryJellyfinSessionStore(JellyfinSession(accessToken: "token-1", userID: "user-1", username: "妈妈"))
        let service = makeService(http: http, sessions: sessions)

        let page = try await service.fetchMedia(containerID: "library-1", filter: .all, request: MediaPageRequest(limit: 2))

        #expect(page.items[0].id == "jellyfin:folder-1")
        #expect(page.items[0].isContainer)
        #expect(page.items[1].kind == .video)
        #expect(page.items[1].url.path == "/jellyfin/Videos/video-1/stream")
        #expect(page.items[1].url.query == "static=true")
        #expect(page.items[0].thumbnailURL?.query?.contains("api_key") == false)
        #expect(page.nextCursor == "2")
        #expect(page.hasMore)
        #expect(http.requests.first?.url?.query?.contains("ParentId=library-1") == true)
    }

    @Test func mapsJellyfinCollectionsAlbumsAndPlaylistsAsBrowsableContainers() async throws {
        let response = """
        {"Items":[
          {"Id":"boxset-1","Name":"电影合集","Type":"BoxSet","IsFolder":false},
          {"Id":"album-1","Name":"家庭相册","Type":"PhotoAlbum","IsFolder":false},
          {"Id":"playlist-1","Name":"周末播放单","Type":"Playlist","IsFolder":false}
        ],"TotalRecordCount":3}
        """.data(using: .utf8)!
        let http = JellyfinRecordingHTTPClient(responses: [(200, response)])
        let sessions = InMemoryJellyfinSessionStore(
            JellyfinSession(accessToken: "token-1", userID: "user-1", username: "妈妈")
        )
        let service = makeService(http: http, sessions: sessions)

        let page = try await service.fetchMedia(
            containerID: "library-1",
            filter: .all,
            request: MediaPageRequest(limit: 20)
        )

        #expect(page.items.map(\.id) == [
            "jellyfin:boxset-1",
            "jellyfin:album-1",
            "jellyfin:playlist-1"
        ])
        #expect(page.items.allSatisfy { $0.isContainer })
        #expect(page.items.allSatisfy { $0.url == URL(string: "https://nas.example.com/jellyfin") })
        #expect(page.items[2].containerID == "playlist:playlist-1")
        let includeTypes = URLComponents(
            url: http.requests[0].url!,
            resolvingAgainstBaseURL: false
        )?.queryItems?.first(where: { $0.name == "IncludeItemTypes" })?.value
        #expect(includeTypes?.contains("BoxSet") == true)
        #expect(includeTypes?.contains("PhotoAlbum") == true)
        #expect(includeTypes?.contains("Playlist") == true)
    }

    @Test func mapsSupportedSortRulesToJellyfinQueries() async throws {
        func queryValue(_ name: String, in items: [URLQueryItem]) -> String? {
            items.first(where: { $0.name == name })?.value
        }

        let response = #"{"Items":[],"TotalRecordCount":0}"#.data(using: .utf8)!
        let http = JellyfinRecordingHTTPClient(responses: Array(repeating: (200, response), count: 4))
        let sessions = InMemoryJellyfinSessionStore(
            JellyfinSession(accessToken: "token-1", userID: "user-1", username: "妈妈")
        )
        let service = makeService(http: http, sessions: sessions)
        let sorts: [MediaSortOption] = [
            .dateAddedNewest,
            .dateAddedOldest,
            .nameAscending,
            .nameDescending
        ]

        for sort in sorts {
            _ = try await service.fetchMedia(
                containerID: "library-1",
                filter: .all,
                request: MediaPageRequest(sort: sort)
            )
        }

        let queries = http.requests.map { request in
            URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        }
        #expect(queryValue("SortBy", in: queries[0]) == "DateCreated")
        #expect(queryValue("SortOrder", in: queries[0]) == "Descending")
        #expect(queryValue("SortBy", in: queries[1]) == "DateCreated")
        #expect(queryValue("SortOrder", in: queries[1]) == "Ascending")
        #expect(queryValue("SortBy", in: queries[2]) == "SortName")
        #expect(queryValue("SortOrder", in: queries[2]) == "Ascending")
        #expect(queryValue("SortBy", in: queries[3]) == "SortName")
        #expect(queryValue("SortOrder", in: queries[3]) == "Descending")
    }

    @Test func libraryRootKeepsNameAscendingRegardlessOfSavedSort() async throws {
        let response = #"{"Items":[],"TotalRecordCount":0}"#.data(using: .utf8)!
        let http = JellyfinRecordingHTTPClient(responses: [(200, response)])
        let sessions = InMemoryJellyfinSessionStore(
            JellyfinSession(accessToken: "token-1", userID: "user-1", username: "妈妈")
        )
        let service = makeService(http: http, sessions: sessions)

        _ = try await service.fetchMedia(
            filter: .all,
            request: MediaPageRequest(sort: .dateAddedNewest)
        )

        let query = URLComponents(
            url: http.requests[0].url!,
            resolvingAgainstBaseURL: false
        )?.queryItems ?? []
        #expect(query.first(where: { $0.name == "SortBy" })?.value == "SortName")
        #expect(query.first(where: { $0.name == "SortOrder" })?.value == "Ascending")
    }

    @Test func playlistContainerUsesDedicatedEndpointAndPreservesServerOrder() async throws {
        let response = """
        {"Items":[
          {"Id":"video-2","Name":"第二段","Type":"Video","IsFolder":false},
          {"Id":"video-1","Name":"第一段","Type":"Video","IsFolder":false}
        ],"TotalRecordCount":5}
        """.data(using: .utf8)!
        let http = JellyfinRecordingHTTPClient(responses: [(200, response)])
        let sessions = InMemoryJellyfinSessionStore(
            JellyfinSession(accessToken: "token-1", userID: "user-1", username: "妈妈")
        )
        let service = makeService(http: http, sessions: sessions)

        let page = try await service.fetchMedia(
            containerID: "playlist:playlist-1",
            filter: .all,
            request: MediaPageRequest(limit: 2, cursor: "1", sort: .nameDescending)
        )

        #expect(page.items.map(\.id) == ["jellyfin:video-2", "jellyfin:video-1"])
        #expect(page.nextCursor == "3")
        #expect(page.hasMore)
        let request = http.requests[0]
        #expect(request.url?.path == "/jellyfin/Playlists/playlist-1/Items")
        let queryItems = URLComponents(
            url: request.url!,
            resolvingAgainstBaseURL: false
        )?.queryItems ?? []
        #expect(queryItems.contains(URLQueryItem(name: "UserId", value: "user-1")))
        #expect(queryItems.contains(URLQueryItem(name: "StartIndex", value: "1")))
        #expect(queryItems.contains(URLQueryItem(name: "Limit", value: "2")))
        #expect(!queryItems.contains(where: { $0.name == "ParentId" }))
        #expect(!queryItems.contains(where: { $0.name == "SortBy" }))
        #expect(!queryItems.contains(where: { $0.name == "IncludeItemTypes" }))
    }

    @Test func mediaFiltersKeepCompatibleJellyfinContainerTypes() async throws {
        let emptyResponse = #"{"Items":[],"TotalRecordCount":0}"#.data(using: .utf8)!
        let http = JellyfinRecordingHTTPClient(responses: [
            (200, emptyResponse),
            (200, emptyResponse)
        ])
        let sessions = InMemoryJellyfinSessionStore(
            JellyfinSession(accessToken: "token-1", userID: "user-1", username: "妈妈")
        )
        let service = makeService(http: http, sessions: sessions)

        _ = try await service.fetchMedia(
            containerID: "library-1",
            filter: .videos,
            request: MediaPageRequest()
        )
        _ = try await service.fetchMedia(
            containerID: "library-1",
            filter: .photos,
            request: MediaPageRequest()
        )

        let includedTypes = http.requests.map { request in
            URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "IncludeItemTypes" })?
                .value ?? ""
        }
        #expect(includedTypes[0].contains("BoxSet"))
        #expect(!includedTypes[0].contains("Playlist"))
        #expect(!includedTypes[0].contains("PhotoAlbum"))
        #expect(includedTypes[1].contains("PhotoAlbum"))
        #expect(!includedTypes[1].contains("BoxSet"))
    }

    @Test func authorizesProtectedImagesWithoutPuttingTokenInURLOrCacheKey() {
        let sessions = InMemoryJellyfinSessionStore(
            JellyfinSession(accessToken: "private-token", userID: "user-1", username: "妈妈")
        )
        let service = makeService(
            http: JellyfinRecordingHTTPClient(responses: []),
            sessions: sessions
        )
        let url = URL(string: "https://nas.example.com/jellyfin/Items/photo-1/Images/Primary")!

        let protectedRequest = service.resourceRequest(for: url)

        #expect(protectedRequest.request.url == url)
        #expect(protectedRequest.request.url?.query == nil)
        #expect(protectedRequest.request.value(forHTTPHeaderField: "Authorization")?.contains("Token=\"private-token\"") == true)
        #expect(!protectedRequest.cachePartition.contains("private-token"))

        service.logout()
        let signedOutRequest = service.resourceRequest(for: url)
        #expect(signedOutRequest.request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(signedOutRequest.cachePartition == "public")
    }

    @Test @MainActor func protectedImageUnauthorizedClearsMatchingSession() async {
        let sessions = InMemoryJellyfinSessionStore(
            JellyfinSession(accessToken: "expired-token", userID: "user-1", username: "妈妈")
        )
        let sourceRefreshCenter = MediaSourceRefreshCenter()
        let service = JellyfinService(
            configuration: existingInstallationConfiguration(),
            sessions: sessions,
            httpClient: JellyfinRecordingHTTPClient(responses: []),
            onSessionInvalidated: {
                sourceRefreshCenter.publishRefresh(for: .jellyfin)
            }
        )
        let protectedRequest = service.resourceRequest(
            for: URL(string: "https://nas.example.com/jellyfin/Items/photo-1/Images/Primary")!
        )

        protectedRequest.handleUnauthorizedResponse()
        await Task.yield()

        #expect(sessions.load() == nil)
        #expect(sourceRefreshCenter.generation == 1)
        #expect(sourceRefreshCenter.affectedSourceID == .jellyfin)
    }

    @Test @MainActor func staleProtectedImageUnauthorizedDoesNotClearReplacementSession() async throws {
        let expiredSession = JellyfinSession(
            accessToken: "expired-token",
            userID: "user-1",
            username: "妈妈"
        )
        let replacementSession = JellyfinSession(
            accessToken: "replacement-token",
            userID: "user-1",
            username: "妈妈"
        )
        let sessions = InMemoryJellyfinSessionStore(expiredSession)
        let sourceRefreshCenter = MediaSourceRefreshCenter()
        let service = JellyfinService(
            configuration: existingInstallationConfiguration(),
            sessions: sessions,
            httpClient: JellyfinRecordingHTTPClient(responses: []),
            onSessionInvalidated: {
                sourceRefreshCenter.publishRefresh(for: .jellyfin)
            }
        )
        let staleRequest = service.resourceRequest(
            for: URL(string: "https://nas.example.com/jellyfin/Items/photo-1/Images/Primary")!
        )
        try sessions.save(replacementSession)

        staleRequest.handleUnauthorizedResponse()
        await Task.yield()

        #expect(sessions.load() == replacementSession)
        #expect(sourceRefreshCenter.generation == 0)
    }

    @Test @MainActor func clearsSessionAfterUnauthorizedResponse() async throws {
        let http = JellyfinRecordingHTTPClient(responses: [(401, Data())])
        let sessions = InMemoryJellyfinSessionStore(JellyfinSession(accessToken: "old", userID: "user-1", username: "妈妈"))
        let sourceRefreshCenter = MediaSourceRefreshCenter()
        let service = JellyfinService(
            configuration: existingInstallationConfiguration(),
            sessions: sessions,
            httpClient: http,
            onSessionInvalidated: {
                sourceRefreshCenter.publishRefresh()
            }
        )

        await #expect(throws: JellyfinError.unauthorized) {
            _ = try await service.fetchMedia(filter: .all, request: MediaPageRequest())
        }
        await Task.yield()
        #expect(sessions.load() == nil)
        #expect(sourceRefreshCenter.generation == 1)
    }

    @Test func healthCheckValidatesPersistedSessionAndClearsExpiredToken() async throws {
        let info = #"{"ServerName":"客厅 NAS","Version":"10.10.7"}"#.data(using: .utf8)!
        let http = JellyfinRecordingHTTPClient(responses: [(200, info), (401, Data())])
        let sessions = InMemoryJellyfinSessionStore(
            JellyfinSession(accessToken: "expired", userID: "user-1", username: "妈妈")
        )
        let service = makeService(http: http, sessions: sessions)

        await #expect(throws: JellyfinError.unauthorized) {
            _ = try await service.checkHealth()
        }

        #expect(sessions.load() == nil)
        #expect(http.requests.map { $0.url?.path } == [
            "/jellyfin/System/Info/Public",
            "/jellyfin/Users/user-1"
        ])
        #expect(http.requests[1].value(forHTTPHeaderField: "Authorization")?.contains("Token=\"expired\"") == true)
    }

    @Test @MainActor func staleUnauthorizedResponseDoesNotClearNewSession() async throws {
        let oldSession = JellyfinSession(accessToken: "old", userID: "user-1", username: "妈妈")
        let newSession = JellyfinSession(accessToken: "new", userID: "user-1", username: "妈妈")
        let sessions = InMemoryJellyfinSessionStore(oldSession)
        let http = SessionChangingHTTPClient(sessions: sessions, replacement: newSession)
        let sourceRefreshCenter = MediaSourceRefreshCenter()
        let service = JellyfinService(
            configuration: existingInstallationConfiguration(),
            sessions: sessions,
            httpClient: http,
            onSessionInvalidated: {
                sourceRefreshCenter.publishRefresh()
            }
        )

        await #expect(throws: JellyfinError.unauthorized) {
            _ = try await service.fetchMedia(filter: .all, request: MediaPageRequest())
        }

        #expect(sessions.load() == newSession)
        #expect(sourceRefreshCenter.generation == 0)
    }

    @Test func resolvesH264MP4AsDirectPlayAndSendsStableDeviceProfile() async throws {
        let response = #"{"MediaSources":[{"Id":"source-1","SupportsDirectPlay":true,"SupportsDirectStream":true,"SupportsTranscoding":true}],"PlaySessionId":"play-1"}"#.data(using: .utf8)!
        let http = JellyfinRecordingHTTPClient(responses: [(200, response)])
        let sessions = InMemoryJellyfinSessionStore(JellyfinSession(accessToken: "token-1", userID: "user-1", username: "妈妈"))
        let service = makeService(http: http, sessions: sessions)

        let resolution = try await service.resolvePlayback(for: jellyfinVideo())

        #expect(resolution.method == .directPlay)
        #expect(resolution.url.path == "/jellyfin/Videos/video-1/stream")
        #expect(resolution.playSessionID == "play-1")
        let body = String(data: http.requests[0].httpBody!, encoding: .utf8)!
        #expect(body.contains(#""MaxStreamingBitrate":20000000"#))
        #expect(body.contains(#""Container":"mp4,m4v,mov""#))
        #expect(body.contains(#""VideoCodec":"h264""#))
        #expect(body.contains(#""AudioCodec":"aac""#))
        #expect(http.requests[0].url?.path == "/jellyfin/Items/video-1/PlaybackInfo")
    }

    @Test func resolvesAVIAsAuthenticatedHLSUnderReverseProxyPath() async throws {
        let response = #"{"MediaSources":[{"Id":"source-avi","SupportsDirectPlay":false,"SupportsDirectStream":false,"SupportsTranscoding":true,"TranscodingUrl":"/Videos/video-1/master.m3u8?MediaSourceId=source-avi&VideoCodec=h264&AudioCodec=aac"}],"PlaySessionId":"play-avi"}"#.data(using: .utf8)!
        let http = JellyfinRecordingHTTPClient(responses: [(200, response)])
        let sessions = InMemoryJellyfinSessionStore(JellyfinSession(accessToken: "token-1", userID: "user-1", username: "妈妈"))
        let service = makeService(http: http, sessions: sessions)

        let resolution = try await service.resolvePlayback(for: jellyfinVideo())

        #expect(resolution.method == .transcode)
        #expect(resolution.url.path == "/jellyfin/Videos/video-1/master.m3u8")
        #expect(resolution.url.query?.contains("VideoCodec=h264") == true)
        #expect(resolution.url.query?.contains("AudioCodec=aac") == true)
        #expect(resolution.url.query?.contains("api_key=token-1") == true)
    }

    @Test func resolvesRelativeTranscodingURLWithoutDroppingReverseProxyPath() async throws {
        let response = #"{"MediaSources":[{"Id":"source-relative","SupportsDirectPlay":false,"SupportsDirectStream":false,"SupportsTranscoding":true,"TranscodingUrl":"Videos/video-1/master.m3u8?MediaSourceId=source-relative"}],"PlaySessionId":"play-relative"}"#.data(using: .utf8)!
        let http = JellyfinRecordingHTTPClient(responses: [(200, response)])
        let sessions = InMemoryJellyfinSessionStore(JellyfinSession(accessToken: "token-1", userID: "user-1", username: "妈妈"))
        let service = makeService(http: http, sessions: sessions)

        let resolution = try await service.resolvePlayback(for: jellyfinVideo())

        #expect(resolution.url.path == "/jellyfin/Videos/video-1/master.m3u8")
        #expect(resolution.url.query?.contains("MediaSourceId=source-relative") == true)
        #expect(resolution.url.query?.contains("api_key=token-1") == true)
    }

    @Test func rejectsExternalTranscodingURLToAvoidLeakingToken() async throws {
        let response = #"{"MediaSources":[{"Id":"source-external","SupportsDirectPlay":false,"SupportsDirectStream":false,"SupportsTranscoding":true,"TranscodingUrl":"https://example.net/master.m3u8"}],"PlaySessionId":"play-external"}"#.data(using: .utf8)!
        let http = JellyfinRecordingHTTPClient(responses: [(200, response)])
        let sessions = InMemoryJellyfinSessionStore(JellyfinSession(accessToken: "token-1", userID: "user-1", username: "妈妈"))
        let service = makeService(http: http, sessions: sessions)

        await #expect(throws: JellyfinError.playbackUnavailable) {
            _ = try await service.resolvePlayback(for: jellyfinVideo())
        }
    }

    @Test @MainActor func changingJellyfinAddressClearsPreviousServerSession() {
        let sessions = InMemoryJellyfinSessionStore(
            JellyfinSession(accessToken: "old-token", userID: "user-1", username: "妈妈")
        )
        let configuration = existingInstallationConfiguration()
        let service = JellyfinService(
            configuration: configuration,
            sessions: sessions,
            httpClient: JellyfinRecordingHTTPClient(responses: [])
        )
        let sourceRefreshCenter = MediaSourceRefreshCenter()
        let store = JellyfinSettingsStore(
            service: service,
            configuration: configuration,
            sourceRefreshCenter: sourceRefreshCenter
        )

        store.serverURLText = "https://other.example.com/jellyfin"

        #expect(store.saveAddress())
        #expect(store.session == nil)
        #expect(sessions.load() == nil)
        #expect(sourceRefreshCenter.generation == 1)
    }

    @Test @MainActor func cosmeticTrailingSlashDoesNotClearJellyfinSession() {
        let originalSession = JellyfinSession(accessToken: "token-1", userID: "user-1", username: "妈妈")
        let sessions = InMemoryJellyfinSessionStore(originalSession)
        let configuration = existingInstallationConfiguration()
        let service = JellyfinService(
            configuration: configuration,
            sessions: sessions,
            httpClient: JellyfinRecordingHTTPClient(responses: [])
        )
        let sourceRefreshCenter = MediaSourceRefreshCenter()
        let store = JellyfinSettingsStore(
            service: service,
            configuration: configuration,
            sourceRefreshCenter: sourceRefreshCenter
        )

        store.serverURLText = "https://nas.example.com/jellyfin/"

        #expect(store.saveAddress())
        #expect(store.session == originalSession)
        #expect(sessions.load() == originalSession)
        #expect(sourceRefreshCenter.generation == 0)
    }

    @Test @MainActor func settingsRefreshReflectsSessionClearedByUnauthorizedRequest() {
        let originalSession = JellyfinSession(
            accessToken: "token-1",
            userID: "user-1",
            username: "妈妈"
        )
        let sessions = InMemoryJellyfinSessionStore(originalSession)
        let configuration = existingInstallationConfiguration()
        let service = JellyfinService(
            configuration: configuration,
            sessions: sessions,
            httpClient: JellyfinRecordingHTTPClient(responses: [])
        )
        let sourceRefreshCenter = MediaSourceRefreshCenter()
        let store = JellyfinSettingsStore(
            service: service,
            configuration: configuration,
            sourceRefreshCenter: sourceRefreshCenter
        )

        sessions.clear()
        store.refreshSession()

        #expect(store.session == nil)
        #expect(store.message == .warning("Jellyfin 登录已失效，请重新登录"))
        #expect(sourceRefreshCenter.generation == 1)
    }

    @Test @MainActor func sourceRefreshAutomaticallySynchronizesExpiredSettingsSession() {
        let originalSession = JellyfinSession(
            accessToken: "token-1",
            userID: "user-1",
            username: "妈妈"
        )
        let sessions = InMemoryJellyfinSessionStore(originalSession)
        let configuration = existingInstallationConfiguration()
        let service = JellyfinService(
            configuration: configuration,
            sessions: sessions,
            httpClient: JellyfinRecordingHTTPClient(responses: [])
        )
        let sourceRefreshCenter = MediaSourceRefreshCenter()
        let store = JellyfinSettingsStore(
            service: service,
            configuration: configuration,
            sourceRefreshCenter: sourceRefreshCenter
        )

        sessions.clear()
        sourceRefreshCenter.publishRefresh()

        #expect(store.session == nil)
        #expect(store.message == .warning("Jellyfin 登录已失效，请重新登录"))
        #expect(sourceRefreshCenter.generation == 1)
    }

    @Test @MainActor func successfulLoginAndLogoutPublishSourceRefreshes() async {
        let authentication = #"{"AccessToken":"token-1","User":{"Id":"user-1","Name":"妈妈"}}"#.data(using: .utf8)!
        let info = #"{"ServerName":"客厅 NAS","Version":"10.10.7"}"#.data(using: .utf8)!
        let configuration = existingInstallationConfiguration()
        let service = JellyfinService(
            configuration: configuration,
            sessions: InMemoryJellyfinSessionStore(),
            httpClient: JellyfinRecordingHTTPClient(responses: [(200, authentication), (200, info)])
        )
        let sourceRefreshCenter = MediaSourceRefreshCenter()
        let store = JellyfinSettingsStore(
            service: service,
            configuration: configuration,
            sourceRefreshCenter: sourceRefreshCenter
        )
        store.username = "妈妈"
        store.password = "secret"

        await store.login()

        #expect(store.session?.username == "妈妈")
        #expect(sourceRefreshCenter.generation == 1)
        #expect(
            sourceRefreshCenter.affectedSourceID?.rawValue
                == MediaSourceID.jellyfin.rawValue
        )

        store.logout()
        #expect(sourceRefreshCenter.generation == 2)
        #expect(
            sourceRefreshCenter.affectedSourceID?.rawValue
                == MediaSourceID.jellyfin.rawValue
        )
    }

    @Test @MainActor func settingsConnectionCheckDetectsExpiredSession() async {
        let info = #"{"ServerName":"客厅 NAS","Version":"10.10.7"}"#.data(using: .utf8)!
        let http = JellyfinRecordingHTTPClient(responses: [(200, info), (401, Data())])
        let sessions = InMemoryJellyfinSessionStore(
            JellyfinSession(accessToken: "expired", userID: "user-1", username: "妈妈")
        )
        let configuration = existingInstallationConfiguration()
        let service = JellyfinService(
            configuration: configuration,
            sessions: sessions,
            httpClient: http
        )
        let store = JellyfinSettingsStore(service: service, configuration: configuration)

        await store.checkConnection()

        #expect(store.session == nil)
        #expect(store.serverInfo == nil)
        #expect(store.message == .warning("Jellyfin 登录已失效，请重新登录"))
        #expect(store.connectionStatus == .available)
    }

    @Test @MainActor func invalidLoginKeepsReachableStatusAndClearsPassword() async {
        let http = JellyfinRecordingHTTPClient(responses: [(401, Data())])
        let configuration = JellyfinConfigurationStore(
            defaults: isolatedDefaults(),
            fallbackURL: URL(string: "https://nas.example.com/jellyfin")!
        )
        let service = JellyfinService(
            configuration: configuration,
            sessions: InMemoryJellyfinSessionStore(),
            httpClient: http
        )
        let store = JellyfinSettingsStore(service: service, configuration: configuration)
        store.username = "妈妈"
        store.password = "wrong-secret"

        await store.login()

        #expect(store.session == nil)
        #expect(store.password.isEmpty)
        #expect(store.connectionStatus == .available)
        #expect(store.message == .failure("Jellyfin 用户名或密码不正确。"))
    }

    @Test @MainActor func leavingLoginUIClearsOnlySensitiveInput() {
        let sessions = InMemoryJellyfinSessionStore()
        let configuration = JellyfinConfigurationStore(
            defaults: isolatedDefaults(),
            fallbackURL: URL(string: "https://nas.example.com/jellyfin")!
        )
        let service = JellyfinService(
            configuration: configuration,
            sessions: sessions,
            httpClient: JellyfinRecordingHTTPClient(responses: [])
        )
        let store = JellyfinSettingsStore(service: service, configuration: configuration)
        store.username = "妈妈"
        store.password = "temporary-secret"

        store.clearSensitiveInput()

        #expect(store.password.isEmpty)
        #expect(store.username == "妈妈")
        #expect(store.serverURLText == "https://nas.example.com/jellyfin")
    }

    @Test func rejectsPlaybackInfoWithoutMediaSources() async throws {
        let response = #"{"MediaSources":[],"PlaySessionId":"play-1"}"#.data(using: .utf8)!
        let http = JellyfinRecordingHTTPClient(responses: [(200, response)])
        let sessions = InMemoryJellyfinSessionStore(JellyfinSession(accessToken: "token-1", userID: "user-1", username: "妈妈"))
        let service = makeService(http: http, sessions: sessions)

        await #expect(throws: JellyfinError.playbackUnavailable) {
            _ = try await service.resolvePlayback(for: jellyfinVideo())
        }
    }

    @Test func reportsPlaybackLifecycleWithSessionAndPosition() async throws {
        let http = JellyfinRecordingHTTPClient(responses: [(204, Data()), (204, Data()), (204, Data())])
        let sessions = InMemoryJellyfinSessionStore(JellyfinSession(accessToken: "token-1", userID: "user-1", username: "妈妈"))
        let service = makeService(http: http, sessions: sessions)
        let item = jellyfinVideo()
        let resolution = MediaPlaybackResolution(url: URL(string: "https://nas.example.com/jellyfin/master.m3u8")!, method: .transcode, playSessionID: "play-1", mediaSourceID: "source-1")

        await service.reportPlaybackStarted(item: item, resolution: resolution)
        await service.reportPlaybackProgress(item: item, resolution: resolution, positionTicks: 150_000_000, isPaused: true)
        await service.reportPlaybackStopped(item: item, resolution: resolution, positionTicks: 200_000_000)

        #expect(http.requests.map { $0.url!.path } == ["/jellyfin/Sessions/Playing", "/jellyfin/Sessions/Playing/Progress", "/jellyfin/Sessions/Playing/Stopped"])
        let progress = String(data: http.requests[1].httpBody!, encoding: .utf8)!
        #expect(progress.contains(#""PlaySessionId":"play-1""#))
        #expect(progress.contains(#""PositionTicks":150000000"#))
        #expect(progress.contains(#""IsPaused":true"#))
        #expect(progress.contains(#""PlayMethod":"Transcode""#))
    }

    private func makeService(
        http: JellyfinRecordingHTTPClient,
        sessions: InMemoryJellyfinSessionStore,
        identity: JellyfinClientIdentity = .default
    ) -> JellyfinService {
        JellyfinService(
            configuration: existingInstallationConfiguration(),
            sessions: sessions,
            httpClient: http,
            identity: identity
        )
    }

    private func existingInstallationConfiguration(
        serverURL: URL = URL(string: "https://nas.example.com/jellyfin")!
    ) -> JellyfinConfigurationStore {
        let configuration = JellyfinConfigurationStore(
            defaults: isolatedDefaults(),
            fallbackURL: serverURL
        )
        _ = configuration.deviceID
        return configuration
    }

    private func jellyfinVideo() -> MediaItem {
        MediaItem(
            id: "jellyfin:video-1", name: "问题视频.avi", kind: .video, size: 100,
            modified: .distantPast, url: URL(string: "https://nas.example.com/jellyfin/Videos/video-1/stream")!,
            mediaPath: "video-1", thumbnailStatus: .failed, sourceID: .jellyfin
        )
    }
}

private final class InMemoryJellyfinSessionStore: JellyfinSessionStoring, @unchecked Sendable {
    private var session: JellyfinSession?
    private let lock = NSLock()
    init(_ session: JellyfinSession? = nil) { self.session = session }
    func load() -> JellyfinSession? { lock.withLock { session } }
    func save(_ session: JellyfinSession) throws { lock.withLock { self.session = session } }
    func clear() { lock.withLock { session = nil } }
    func clear(ifMatching session: JellyfinSession) -> Bool {
        lock.withLock {
            guard self.session == session else { return false }
            self.session = nil
            return true
        }
    }
}

private final class JellyfinRecordingHTTPClient: HTTPClient, @unchecked Sendable {
    private var responses: [(Int, Data)]
    private(set) var requests: [URLRequest] = []
    init(responses: [(Int, Data)]) { self.responses = responses }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = responses.removeFirst()
        return (response.1, HTTPURLResponse(url: request.url!, statusCode: response.0, httpVersion: nil, headerFields: nil)!)
    }
}

private final class JellyfinAddressChangingHTTPClient: HTTPClient, @unchecked Sendable {
    private let configuration: JellyfinConfigurationStore
    private let replacementURL: URL
    private let responseData: Data

    init(
        configuration: JellyfinConfigurationStore,
        replacementURL: URL,
        responseData: Data
    ) {
        self.configuration = configuration
        self.replacementURL = replacementURL
        self.responseData = responseData
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        configuration.serverBaseURL = replacementURL
        return (
            responseData,
            HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }
}

private final class SessionChangingHTTPClient: HTTPClient, @unchecked Sendable {
    private let sessions: InMemoryJellyfinSessionStore
    private let replacement: JellyfinSession

    init(sessions: InMemoryJellyfinSessionStore, replacement: JellyfinSession) {
        self.sessions = sessions
        self.replacement = replacement
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try sessions.save(replacement)
        return (
            Data(),
            HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
        )
    }
}
