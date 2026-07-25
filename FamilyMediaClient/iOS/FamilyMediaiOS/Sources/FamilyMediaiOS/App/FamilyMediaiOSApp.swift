import FamilyMediaCore
import SwiftUI

@main
struct FamilyMediaiOSApp: App {
    private let dependencies: AppDependencies

    init() {
#if DEBUG
        UITestLaunchConfiguration.applyIfNeeded()
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-testing-demo") {
            dependencies = .uiTesting(
                jellyfinSignedOut: arguments.contains("--ui-testing-jellyfin-signed-out")
            )
        } else {
            dependencies = .live()
        }
#else
        dependencies = .live()
#endif
        PlaybackSettings.repairPersistedValues()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView(dependencies: dependencies)
        }
    }
}

#if DEBUG
private enum UITestLaunchConfiguration {
    static func applyIfNeeded(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        defaults: UserDefaults = .standard
    ) {
        guard arguments.contains("--ui-testing") else { return }

        if let bundleID = Bundle.main.bundleIdentifier {
            defaults.removePersistentDomain(forName: bundleID)
        }
        defaults.set(
            !arguments.contains("--ui-testing-show-onboarding"),
            forKey: ClientExperienceSettings.hasCompletedOnboardingKey
        )
        defaults.set(arguments.contains("--ui-testing-demo"), forKey: "debug_demo_mode")
        defaults.set(DemoMediaScenario.content.rawValue, forKey: "debug_demo_scenario")
    }
}
#endif
