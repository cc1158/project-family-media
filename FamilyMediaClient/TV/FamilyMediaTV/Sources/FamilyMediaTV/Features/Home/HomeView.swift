import FamilyMediaCore
import SwiftUI

struct HomeView: View {
    private enum HomeFocus: Hashable {
        case refresh
        case familyMedia
        case jellyfin
        case settings
    }

    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var focusedEntry: HomeFocus?
    @StateObject private var sourceAvailability: MediaSourceAvailabilityStore
    @StateObject private var sourceTaskController = ViewTaskController()
    @StateObject private var networkRecoveryObserver = NetworkRecoveryObserver()
    @ObservedObject private var sourceRefreshCenter: MediaSourceRefreshCenter
    @State private var isShowingOnboarding = false
    @State private var isVisible = false
    @State private var needsSourceRefresh = false
    @State private var navigationPath = NavigationPath()
    @State private var activeMediaSourceID: MediaSourceID?
    @AppStorage(ClientExperienceSettings.hasCompletedOnboardingKey)
    private var hasCompletedOnboarding = false
    let mediaService: any MediaServicing
    let configurationStore: ServerConfigurationStore
    let refreshCenter: MediaLibraryRefreshCenter
    let mediaSources: MediaSourceRegistry
    let jellyfinService: JellyfinService
    let jellyfinConfigurationStore: JellyfinConfigurationStore

    init(
        mediaService: any MediaServicing,
        configurationStore: ServerConfigurationStore,
        refreshCenter: MediaLibraryRefreshCenter,
        sourceRefreshCenter: MediaSourceRefreshCenter,
        mediaSources: MediaSourceRegistry,
        jellyfinService: JellyfinService,
        jellyfinConfigurationStore: JellyfinConfigurationStore
    ) {
        self.mediaService = mediaService
        self.configurationStore = configurationStore
        self.refreshCenter = refreshCenter
        _sourceRefreshCenter = ObservedObject(wrappedValue: sourceRefreshCenter)
        self.mediaSources = mediaSources
        self.jellyfinService = jellyfinService
        self.jellyfinConfigurationStore = jellyfinConfigurationStore
        _sourceAvailability = StateObject(
            wrappedValue: MediaSourceAvailabilityStore(
                registry: mediaSources,
                sourceRefreshCenter: sourceRefreshCenter
            )
        )
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                TVAppBackground()

                VStack(alignment: .leading, spacing: 48) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("家映")
                                .font(.largeTitle.bold())
                            Text("把家的时光，放在一起看")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            sourceTaskController.run {
                                await sourceAvailability.refresh()
                            }
                        } label: {
                            if sourceAvailability.isRefreshing {
                                ProgressView()
                            } else {
                                Label("重新检查", systemImage: "arrow.clockwise")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(sourceAvailability.isRefreshing)
                        .focused($focusedEntry, equals: .refresh)
                    }

                    HStack(spacing: 40) {
                        NavigationLink {
                            familyMediaDestination
                        } label: {
                            HomeEntryView(
                                title: "家庭媒体",
                                subtitle: "照片、视频与家庭回忆",
                                systemImage: "house.fill",
                                accent: FamilyMediaTVTheme.accent,
                                availability: sourceAvailability.familyMedia
                            )
                        }
                        .buttonStyle(.card)
                        .accessibilityIdentifier("home.family")
                        .focused($focusedEntry, equals: .familyMedia)

                        NavigationLink {
                            jellyfinDestination
                        } label: {
                            HomeEntryView(
                                title: "Jellyfin",
                                subtitle: "电影、剧集与媒体库",
                                systemImage: "play.tv.fill",
                                accent: FamilyMediaTVTheme.purple,
                                availability: sourceAvailability.jellyfin
                            )
                        }
                        .buttonStyle(.card)
                        .accessibilityIdentifier("home.jellyfin")
                        .focused($focusedEntry, equals: .jellyfin)

                        NavigationLink {
                            SettingsView(
                                mediaService: mediaService,
                                configurationStore: configurationStore,
                                refreshCenter: refreshCenter,
                                sourceRefreshCenter: sourceRefreshCenter,
                                jellyfinService: jellyfinService,
                                jellyfinConfigurationStore: jellyfinConfigurationStore
                            )
                            .onAppear {
                                activeMediaSourceID = nil
                            }
                        } label: {
                            HomeEntryView(
                                title: "设置",
                                subtitle: "连接服务与调整播放体验",
                                systemImage: "gearshape.fill",
                                accent: Color(red: 0.24, green: 0.42, blue: 0.60)
                            )
                        }
                        .buttonStyle(.card)
                        .accessibilityIdentifier("home.settings")
                        .focused($focusedEntry, equals: .settings)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(80)
            }
        }
        .task {
            await sourceTaskController.runAndWait {
                if needsSourceRefresh {
                    needsSourceRefresh = false
                    await sourceAvailability.refresh()
                } else {
                    await sourceAvailability.refreshAfterForegroundIfNeeded()
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else {
                sourceTaskController.cancel()
                return
            }
            refreshAfterBecomingActive()
        }
        .onChange(of: networkRecoveryObserver.generation) {
            handleNetworkPathChange()
        }
        .onChange(of: sourceRefreshCenter.generation) {
            if sourceRefreshCenter.affectsNavigation(for: activeMediaSourceID) {
                navigationPath = NavigationPath()
                activeMediaSourceID = nil
            }
            guard scenePhase == .active, isVisible else {
                needsSourceRefresh = true
                sourceTaskController.cancel()
                return
            }
            sourceTaskController.run {
                await sourceAvailability.refresh()
            }
        }
        .onAppear {
            isVisible = true
            activeMediaSourceID = nil
            isShowingOnboarding = !hasCompletedOnboarding
            if hasCompletedOnboarding {
                focusedEntry = .familyMedia
            }
        }
        .onChange(of: hasCompletedOnboarding) { _, isCompleted in
            if !isCompleted {
                isShowingOnboarding = true
            }
        }
        .fullScreenCover(isPresented: $isShowingOnboarding) {
            TVWelcomeView {
                hasCompletedOnboarding = true
                isShowingOnboarding = false
                focusedEntry = .familyMedia
            }
            .interactiveDismissDisabled()
        }
        .onDisappear {
            isVisible = false
            sourceTaskController.cancel()
        }
    }

    @ViewBuilder
    private var familyMediaDestination: some View {
        if sourceAvailability.familyMedia.canBrowse {
            FamilyMediaHomeView(source: mediaSources.familyMedia, refreshCenter: refreshCenter)
                .onAppear {
                    activeMediaSourceID = .familyMedia
                }
        } else {
            SettingsView(
                mediaService: mediaService,
                configurationStore: configurationStore,
                refreshCenter: refreshCenter,
                sourceRefreshCenter: sourceRefreshCenter,
                jellyfinService: jellyfinService,
                jellyfinConfigurationStore: jellyfinConfigurationStore
            )
            .onAppear {
                activeMediaSourceID = nil
            }
        }
    }

    @ViewBuilder
    private var jellyfinDestination: some View {
        if sourceAvailability.jellyfin.canBrowse {
            MediaGridView(
                title: "Jellyfin 媒体库",
                filter: .all,
                source: mediaSources.jellyfin,
                refreshCenter: refreshCenter
            )
            .onAppear {
                activeMediaSourceID = .jellyfin
            }
        } else {
            SettingsView(
                mediaService: mediaService,
                configurationStore: configurationStore,
                refreshCenter: refreshCenter,
                sourceRefreshCenter: sourceRefreshCenter,
                jellyfinService: jellyfinService,
                jellyfinConfigurationStore: jellyfinConfigurationStore
            )
            .onAppear {
                activeMediaSourceID = nil
            }
        }
    }

    private func refreshAfterBecomingActive() {
        if networkRecoveryObserver.consumePendingChange() {
            refreshCenter.publishRefresh()
            guard isVisible else {
                needsSourceRefresh = true
                return
            }
            needsSourceRefresh = false
            sourceTaskController.run {
                await sourceAvailability.refresh()
            }
        } else {
            guard isVisible else { return }
            sourceTaskController.run {
                await sourceAvailability.refreshAfterForegroundIfNeeded()
            }
        }
    }

    private func handleNetworkPathChange() {
        guard scenePhase == .active else {
            sourceTaskController.cancel()
            return
        }
        guard networkRecoveryObserver.consumePendingChange() else { return }
        refreshCenter.publishRefresh()
        guard isVisible else {
            needsSourceRefresh = true
            return
        }
        needsSourceRefresh = false
        sourceTaskController.run {
            await sourceAvailability.refresh()
        }
    }
}

private struct FamilyMediaHomeView: View {
    let source: MediaSourceContext
    let refreshCenter: MediaLibraryRefreshCenter

    var body: some View {
        ZStack {
            TVAppBackground()
            VStack(alignment: .leading, spacing: 40) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("家庭媒体").font(.largeTitle.bold())
                    Text("选择一种方式浏览家里的媒体")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 40) {
                    entry("全部媒体", "照片与视频", "square.grid.2x2.fill", .all, FamilyMediaTVTheme.accent)
                    entry("视频", "家庭影片与录像", "play.rectangle.fill", .videos, Color.blue)
                    entry("照片", "照片与珍贵时刻", "photo.on.rectangle.angled", .photos, FamilyMediaTVTheme.purple)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(80)
        }
    }

    private func entry(
        _ title: String,
        _ subtitle: String,
        _ image: String,
        _ filter: MediaFilter,
        _ accent: Color
    ) -> some View {
        NavigationLink {
            MediaGridView(
                title: title,
                filter: filter,
                source: source,
                refreshCenter: refreshCenter
            )
        } label: {
            HomeEntryView(title: title, subtitle: subtitle, systemImage: image, accent: accent)
        }
        .buttonStyle(.card)
        .accessibilityIdentifier(categoryAccessibilityIdentifier(for: filter))
    }

    private func categoryAccessibilityIdentifier(for filter: MediaFilter) -> String {
        switch filter {
        case .all: "home.category.all"
        case .videos: "home.category.videos"
        case .photos: "home.category.photos"
        }
    }
}
