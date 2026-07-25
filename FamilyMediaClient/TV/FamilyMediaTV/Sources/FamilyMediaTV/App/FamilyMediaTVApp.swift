import FamilyMediaCore
import SwiftUI

@main
struct FamilyMediaTVApp: App {
    private let dependencies: AppDependencies

    init() {
#if DEBUG
        let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        if isUITesting {
            if let bundleID = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: bundleID)
            }
            UserDefaults.standard.set(
                !ProcessInfo.processInfo.arguments.contains("--ui-testing-show-onboarding"),
                forKey: ClientExperienceSettings.hasCompletedOnboardingKey
            )
            UserDefaults.standard.set(
                PlaybackSettings.photoDurationRange.upperBound,
                forKey: PlaybackSettings.photoDurationKey
            )
        }
        PlaybackSettings.repairPersistedValues()
        dependencies = isUITesting
            ? .uiTesting(
                jellyfinSignedOut: ProcessInfo.processInfo.arguments.contains(
                    "--ui-testing-jellyfin-signed-out"
                )
            )
            : .live()
#else
        PlaybackSettings.repairPersistedValues()
        dependencies = .live()
#endif
    }

    var body: some Scene {
        WindowGroup {
            HomeView(
                mediaService: dependencies.mediaService,
                configurationStore: dependencies.configurationStore,
                refreshCenter: dependencies.refreshCenter,
                sourceRefreshCenter: dependencies.sourceRefreshCenter,
                mediaSources: dependencies.mediaSources,
                jellyfinService: dependencies.jellyfinService,
                jellyfinConfigurationStore: dependencies.jellyfinConfigurationStore
            )
        }
    }
}
