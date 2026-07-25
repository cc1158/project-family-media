import FamilyMediaCore
import SwiftUI
import UIKit

struct RootTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var navigation = RootNavigationState()
    @State private var mediaNavigationPath = NavigationPath()
    @State private var detailNavigationPath = NavigationPath()
    @State private var isShowingOnboarding = false
    @StateObject private var sourceAvailability: MediaSourceAvailabilityStore
    @StateObject private var sourceTaskController = ViewTaskController()
    @StateObject private var networkRecoveryObserver = NetworkRecoveryObserver()
    @ObservedObject private var sourceRefreshCenter: MediaSourceRefreshCenter
    @AppStorage(ClientExperienceSettings.hasCompletedOnboardingKey)
    private var hasCompletedOnboarding = false
    private let dependencies: AppDependencies
    private let presentationMode: RootPresentationMode
#if DEBUG
    @AppStorage("debug_demo_mode") private var isDemoMode = false
    @AppStorage("debug_demo_scenario") private var demoScenario = DemoMediaScenario.content.rawValue
#endif

    init(
        dependencies: AppDependencies,
        userInterfaceIdiom: UIUserInterfaceIdiom = UIDevice.current.userInterfaceIdiom
    ) {
        self.dependencies = dependencies
        presentationMode = RootPresentationPolicy.mode(
            for: userInterfaceIdiom
        )
        _sourceRefreshCenter = ObservedObject(
            wrappedValue: dependencies.sourceRefreshCenter
        )
        _sourceAvailability = StateObject(
            wrappedValue: MediaSourceAvailabilityStore(
                registry: dependencies.mediaSources,
                sourceRefreshCenter: dependencies.sourceRefreshCenter
            )
        )
    }

    var body: some View {
        Group {
            switch presentationMode {
            case .phoneTabs:
                phoneLayout
            case .iPadSplit:
                iPadLayout
            }
        }
        .tint(FamilyMediaTheme.accent)
        .preferredColorScheme(.dark)
        .onChange(of: navigation.selectedSidebarDestination) { _, destination in
            guard presentationMode == .iPadSplit, let destination else { return }
            openSidebarDestination(destination)
        }
        .onChange(of: mediaSourceIdentity) {
            resetMediaNavigation()
        }
        .onChange(of: sourceRefreshCenter.generation) {
            if sourceRefreshCenter.affectsNavigation(for: navigation.activeMediaSourceID) {
                resetMediaNavigation()
            }
            guard scenePhase == .active, !demoModeEnabled else {
                sourceTaskController.cancel()
                return
            }
            sourceTaskController.run {
                await sourceAvailability.refresh()
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
        .onAppear {
            isShowingOnboarding = !hasCompletedOnboarding
        }
        .onChange(of: hasCompletedOnboarding) { _, isCompleted in
            if !isCompleted {
                isShowingOnboarding = true
            }
        }
        .fullScreenCover(
            isPresented: $isShowingOnboarding,
            onDismiss: finishOnboardingNavigation
        ) {
            WelcomeView(
                onConfigure: { completeOnboarding(openSettings: true) },
                onBrowse: { completeOnboarding(openSettings: false) }
            )
            .interactiveDismissDisabled()
        }
        .onDisappear(perform: sourceTaskController.cancel)
    }

    private var phoneLayout: some View {
        PhoneRootView(
            selectedTab: $navigation.selectedTab,
            mediaNavigationPath: $mediaNavigationPath,
            mediaHome: {
                mediaHome(onOpenSettings: {
                    navigation.selectedTab = .settings
                })
            },
            settings: {
                settingsView
            }
        )
    }

    private var iPadLayout: some View {
        IPadRootSplitView(
            selection: $navigation.selectedSidebarDestination,
            detailNavigationPath: $detailNavigationPath,
            detail: {
                sidebarDetail
            }
        )
    }

    @ViewBuilder
    private var sidebarDetail: some View {
        switch navigation.selectedSidebarDestination ?? .mediaHome {
        case .mediaHome:
            mediaHome(onOpenSettings: { selectSidebarDestination(.settings) })
        case .familyMedia where canBrowseFamilyMedia:
            FamilyMediaCategoriesView(
                source: activeMediaSources.familyMedia,
                refreshCenter: dependencies.refreshCenter
            )
            .onAppear { navigation.activeMediaSourceID = .familyMedia }
        case .jellyfin where canBrowseJellyfin:
            MediaLibraryView(
                title: "Jellyfin",
                filter: .all,
                source: activeMediaSources.jellyfin,
                refreshCenter: dependencies.refreshCenter
            )
            .onAppear { navigation.activeMediaSourceID = .jellyfin }
        case .familyMedia, .jellyfin, .settings:
            settingsView
                .onAppear { navigation.activeMediaSourceID = nil }
        }
    }

    private func mediaHome(onOpenSettings: @escaping () -> Void) -> some View {
        MediaSourcesView(
            mediaSources: activeMediaSources,
            refreshCenter: dependencies.refreshCenter,
            availabilityStore: sourceAvailability,
            isDemoMode: demoModeEnabled,
            demoJellyfinRequiresAuthentication: demoJellyfinRequiresAuthentication,
            onOpenSettings: onOpenSettings,
            onSourceNavigationChanged: { navigation.activeMediaSourceID = $0 }
        )
    }

    private var settingsView: some View {
        SettingsView(
            mediaService: dependencies.mediaService,
            configurationStore: dependencies.configurationStore,
            refreshCenter: dependencies.refreshCenter,
            sourceRefreshCenter: sourceRefreshCenter,
            jellyfinService: dependencies.jellyfinService,
            jellyfinConfigurationStore: dependencies.jellyfinConfigurationStore
        )
    }

    private var activeMediaSources: MediaSourceRegistry {
#if DEBUG
        isDemoMode
            ? DemoMediaSources.registry(
                scenario: DemoMediaScenario(rawValue: demoScenario) ?? .content,
                jellyfinReadiness: demoJellyfinRequiresAuthentication
                    ? .authenticationRequired
                    : .ready
            )
            : dependencies.mediaSources
#else
        dependencies.mediaSources
#endif
    }

    private var demoModeEnabled: Bool {
#if DEBUG
        isDemoMode
#else
        false
#endif
    }

    private var mediaSourceIdentity: String {
#if DEBUG
        isDemoMode
            ? "demo:\(demoScenario):signedOut=\(demoJellyfinRequiresAuthentication)"
            : "live"
#else
        "live"
#endif
    }

    private var demoJellyfinRequiresAuthentication: Bool {
#if DEBUG
        isDemoMode && ProcessInfo.processInfo.arguments.contains(
            "--ui-testing-jellyfin-signed-out"
        )
#else
        false
#endif
    }

    private var canBrowseFamilyMedia: Bool {
#if DEBUG
        demoModeEnabled || sourceAvailability.familyMedia.canBrowse
#else
        sourceAvailability.familyMedia.canBrowse
#endif
    }

    private var canBrowseJellyfin: Bool {
#if DEBUG
        if demoModeEnabled {
            return !demoJellyfinRequiresAuthentication
        }
#endif
        return sourceAvailability.jellyfin.canBrowse
    }

    private func completeOnboarding(openSettings: Bool) {
        navigation.prepareOnboardingDestination(openSettings: openSettings)
        hasCompletedOnboarding = true
        isShowingOnboarding = false
    }

    private func finishOnboardingNavigation() {
        navigation.applyOnboardingDestination()
    }

    private func selectSidebarDestination(_ destination: RootSidebarDestination) {
        navigation.selectedSidebarDestination = destination
    }

    private func openSidebarDestination(_ destination: RootSidebarDestination) {
        navigation.selectSidebarDestination(destination) { sourceID in
            canBrowse(sourceID)
        }
        detailNavigationPath = NavigationPath()
    }

    private func resetMediaNavigation() {
        mediaNavigationPath = NavigationPath()
        detailNavigationPath = NavigationPath()
        navigation.resetMediaNavigation(for: presentationMode)
    }

    private func canBrowse(_ sourceID: MediaSourceID) -> Bool {
        switch sourceID {
        case .familyMedia: canBrowseFamilyMedia
        case .jellyfin: canBrowseJellyfin
        }
    }

    private func refreshAfterBecomingActive() {
        guard !demoModeEnabled else { return }
        if networkRecoveryObserver.consumePendingChange() {
            dependencies.refreshCenter.publishRefresh()
            sourceTaskController.run {
                await sourceAvailability.refresh()
            }
        } else {
            sourceTaskController.run {
                await sourceAvailability.refreshAfterForegroundIfNeeded()
            }
        }
    }

    private func handleNetworkPathChange() {
        guard scenePhase == .active, !demoModeEnabled else {
            sourceTaskController.cancel()
            return
        }
        guard networkRecoveryObserver.consumePendingChange() else { return }
        dependencies.refreshCenter.publishRefresh()
        sourceTaskController.run {
            await sourceAvailability.refresh()
        }
    }
}
