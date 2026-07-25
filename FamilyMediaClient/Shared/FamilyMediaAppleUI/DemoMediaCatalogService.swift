#if DEBUG
import FamilyMediaCore
import Foundation

enum DemoMediaScenario: String, CaseIterable, Identifiable {
    case content
    case empty
    case failure

    var id: String { rawValue }

    var title: String {
        switch self {
        case .content: "正常内容"
        case .empty: "空媒体库"
        case .failure: "连接失败"
        }
    }
}

struct DemoMediaCatalogService: MediaCatalogServicing {
    let sourceID: MediaSourceID
    let scenario: DemoMediaScenario

    func fetchMedia(filter: MediaFilter, request: MediaPageRequest) async throws -> MediaPage {
        try await fetchMedia(containerID: nil, filter: filter, request: request)
    }

    func fetchMedia(
        containerID: String?,
        filter: MediaFilter,
        request: MediaPageRequest
    ) async throws -> MediaPage {
        try await Task.sleep(for: .milliseconds(650))
        switch scenario {
        case .empty:
            return MediaPage(items: [])
        case .failure:
            throw URLError(.cannotConnectToHost)
        case .content:
            break
        }

        let allItems = items(in: containerID).filter { item in
            item.isContainer || filter == .all ||
                (filter == .photos && item.kind == .photo) ||
                (filter == .videos && item.kind == .video)
        }
        let start = Int(request.cursor ?? "0") ?? 0
        let end = min(start + request.limit, allItems.count)
        let pageItems = start < end ? Array(allItems[start..<end]) : []
        return MediaPage(
            items: pageItems,
            nextCursor: end < allItems.count ? String(end) : "",
            hasMore: end < allItems.count
        )
    }

    private func items(in containerID: String?) -> [MediaItem] {
        switch (sourceID, containerID) {
        case (.jellyfin, nil):
            return [
                container("movies", "电影", art: "cinema"),
                container("shows", "剧集", art: "series"),
                container("animation", "动画", art: "animation"),
                container("documentary", "纪录片与家庭珍藏", art: "documentary"),
                container("playlists", "播放列表", art: nil)
            ]
        case (.jellyfin, "movies"):
            return [
                container("action", "动作冒险", art: "action"),
                container("classic", "经典电影", art: "classic"),
                video("movie-1", "漫长的告别：一个用于测试两行标题的电影名称", art: "sunset"),
                video("movie-2", "周末影院", art: "weekend"),
                video("movie-3", "山海之间", art: nil)
            ]
        case (.jellyfin, "shows"):
            return [
                container("show-1", "春日来信 · 第一季", art: "spring"),
                container("show-2", "城市故事", art: "city"),
                container("show-3", "一起长大", art: "family")
            ]
        case (.jellyfin, "animation"):
            return demoVideos(prefix: "animation", count: 12)
        case (.jellyfin, "action"):
            return demoVideos(prefix: "action", count: 58)
        case (.jellyfin, "classic"):
            return demoVideos(prefix: "classic", count: 18)
        case (.jellyfin, "playlists"):
            return []
        case (.jellyfin, "show-1"), (.jellyfin, "show-2"), (.jellyfin, "show-3"):
            return demoVideos(prefix: containerID ?? "episode", count: 10)
        case (.jellyfin, _):
            return demoVideos(prefix: containerID ?? "jellyfin", count: 8)
        case (.familyMedia, _):
            return familyItems
        }
    }

    private var familyItems: [MediaItem] {
        [
            photo("family-1", "海边的下午", art: "sea"),
            video("family-2", "外婆的生日", art: "birthday"),
            photo("family-3", "第一次露营", art: "camping"),
            video("family-4", "孩子的运动会完整版", art: "sports"),
            photo("family-5", "春天的花园", art: "garden"),
            photo("family-6", "没有缩略图的旧照片", art: nil),
            video("family-7", "春节团圆饭", art: "dinner"),
            photo("family-8", "一段很长很长的家庭照片标题，用来检查卡片是否整齐", art: "portrait"),
            video("family-9", "夏日旅行", art: "travel"),
            photo("family-10", "山顶合影", art: "mountain")
        ]
    }

    private func demoVideos(prefix: String, count: Int) -> [MediaItem] {
        (1...count).map { index in
            video(
                "\(prefix)-\(index)",
                index.isMultiple(of: 7)
                    ? "第 \(index) 集 · 这是一个用于测试自动换行的较长标题"
                    : "第 \(index) 集",
                art: index.isMultiple(of: 9) ? nil : "\(prefix)-\(index)"
            )
        }
    }

    private func container(_ id: String, _ name: String, art: String?) -> MediaItem {
        item(id: id, name: name, kind: .photo, art: art, containerID: id, isContainer: true)
    }

    private func video(_ id: String, _ name: String, art: String?) -> MediaItem {
        item(id: id, name: name, kind: .video, art: art)
    }

    private func photo(_ id: String, _ name: String, art: String?) -> MediaItem {
        item(id: id, name: name, kind: .photo, art: art)
    }

    private func item(
        id: String,
        name: String,
        kind: MediaKind,
        art: String?,
        containerID: String? = nil,
        isContainer: Bool = false
    ) -> MediaItem {
        MediaItem(
            id: "demo:\(sourceID.rawValue):\(id)",
            name: name,
            kind: kind,
            size: 128_000_000,
            modified: Date(timeIntervalSince1970: 1_700_000_000),
            url: URL(fileURLWithPath: "/demo/\(id)"),
            thumbnailURL: art.flatMap(demoArtworkURL),
            mediaPath: id,
            thumbnailStatus: art == nil ? .failed : .ready,
            sourceID: sourceID,
            containerID: containerID,
            isContainer: isContainer
        )
    }

    private func demoArtworkURL(_ name: String) -> URL? {
        var components = URLComponents()
        components.scheme = "demo-art"
        components.host = name
        return components.url
    }
}

private struct DemoPlaybackResolver: MediaPlaybackResolving {
    func resolvePlayback(for item: MediaItem) async throws -> MediaPlaybackResolution {
        try await Task.sleep(for: .milliseconds(500))
        throw DemoPlaybackError()
    }
}

private struct DemoMediaTimelineService: MediaTimelineServicing {
    let catalog: DemoMediaCatalogService

    func supportsTimeline() async -> Bool { true }

    func fetchTimelineIndex(request: MediaTimelineRequest) async throws -> MediaTimelineIndex {
        switch catalog.scenario {
        case .failure:
            throw URLError(.cannotConnectToHost)
        case .empty:
            return MediaTimelineIndex(dateSemantics: "captured", timeZone: request.timeZone, years: [])
        case .content:
            return MediaTimelineIndex(
                dateSemantics: "captured",
                timeZone: request.timeZone,
                years: [
                    MediaTimelineYear(
                        key: "2024",
                        count: 6,
                        months: [
                            MediaTimelineMonth(key: "2024-08", count: 6)
                        ]
                    ),
                    MediaTimelineYear(
                        key: "2023",
                        count: 4,
                        months: [
                            MediaTimelineMonth(key: "2023-11", count: 4)
                        ]
                    )
                ]
            )
        }
    }

    func fetchTimelineMonth(
        key: String,
        request: MediaTimelineRequest,
        page: MediaPageRequest
    ) async throws -> MediaPage {
        let all = try await catalog.fetchMedia(
            containerID: request.containerID,
            filter: request.filter,
            request: MediaPageRequest(limit: 50)
        ).items.filter { !$0.isContainer }
        let split = min(6, all.count)
        let selected = key == "2024-08" ? Array(all.prefix(split)) : Array(all.dropFirst(split))
        return MediaPage(items: selected)
    }
}

private struct DemoPlaybackError: LocalizedError, Sendable {
    var errorDescription: String? {
        "演示模式没有真实视频，你可以在这里检查失败提示和重试按钮。"
    }
}

enum DemoMediaSources {
    static func registry(
        scenario: DemoMediaScenario,
        jellyfinReadiness: MediaSourceReadiness = .ready
    ) -> MediaSourceRegistry {
        let familyCatalog = DemoMediaCatalogService(sourceID: .familyMedia, scenario: scenario)
        return MediaSourceRegistry(
            familyMedia: MediaSourceContext(
                id: .familyMedia,
                catalog: familyCatalog,
                timeline: DemoMediaTimelineService(catalog: familyCatalog),
                playbackResolver: DemoPlaybackResolver()
            ),
            jellyfin: MediaSourceContext(
                id: .jellyfin,
                catalog: DemoMediaCatalogService(sourceID: .jellyfin, scenario: scenario),
                playbackResolver: DemoPlaybackResolver(),
                catalogStructure: .libraryRoot,
                readiness: { jellyfinReadiness }
            )
        )
    }
}
#endif
