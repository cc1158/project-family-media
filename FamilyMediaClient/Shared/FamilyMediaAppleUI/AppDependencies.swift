import FamilyMediaCore
import Foundation
import UIKit

/// Application-level service graph shared by the iOS/iPadOS and tvOS targets.
/// Platform views consume this graph but do not assemble source capabilities.
@MainActor
struct AppDependencies {
    let mediaService: any MediaServicing
    let configurationStore: ServerConfigurationStore
    let refreshCenter: MediaLibraryRefreshCenter
    let sourceRefreshCenter: MediaSourceRefreshCenter
    let jellyfinService: JellyfinService
    let jellyfinConfigurationStore: JellyfinConfigurationStore
    let mediaSources: MediaSourceRegistry

    static func live() -> AppDependencies {
        let config = ClientAppConfiguration.load()
        let configurationStore = ServerConfigurationStore(fallbackURL: config.serverBaseURL)
        let refreshCenter = MediaLibraryRefreshCenter()
        let sourceRefreshCenter = MediaSourceRefreshCenter()
        let jellyfinConfigurationStore = JellyfinConfigurationStore()
        let mediaService = MediaService(configurationProvider: configurationStore)
        let jellyfinService = JellyfinService(
            configuration: jellyfinConfigurationStore,
            identity: JellyfinClientIdentity(
                clientName: "Jiaying",
                deviceName: deviceName,
                version: ClientBuildInfo.load().version
            ),
            onSessionInvalidated: {
                sourceRefreshCenter.publishRefresh(for: .jellyfin)
            }
        )

        return AppDependencies(
            mediaService: mediaService,
            configurationStore: configurationStore,
            refreshCenter: refreshCenter,
            sourceRefreshCenter: sourceRefreshCenter,
            jellyfinService: jellyfinService,
            jellyfinConfigurationStore: jellyfinConfigurationStore,
            mediaSources: makeMediaSources(
                mediaService: mediaService,
                jellyfinService: jellyfinService
            )
        )
    }

#if DEBUG
    static func uiTesting(jellyfinSignedOut: Bool = false) -> AppDependencies {
        let dependencies = live()
        return AppDependencies(
            mediaService: dependencies.mediaService,
            configurationStore: dependencies.configurationStore,
            refreshCenter: dependencies.refreshCenter,
            sourceRefreshCenter: dependencies.sourceRefreshCenter,
            jellyfinService: dependencies.jellyfinService,
            jellyfinConfigurationStore: dependencies.jellyfinConfigurationStore,
            mediaSources: DemoMediaSources.registry(
                scenario: .content,
                jellyfinReadiness: jellyfinSignedOut ? .authenticationRequired : .ready
            )
        )
    }
#endif

    private static func makeMediaSources(
        mediaService: MediaService,
        jellyfinService: JellyfinService
    ) -> MediaSourceRegistry {
        MediaSourceRegistry(
            familyMedia: MediaSourceContext(
                id: .familyMedia,
                catalog: mediaService,
                timeline: mediaService,
                playbackResolver: mediaService,
                admin: mediaService,
                healthChecker: mediaService
            ),
            jellyfin: MediaSourceContext(
                id: .jellyfin,
                catalog: jellyfinService,
                playbackResolver: jellyfinService,
                playbackReporter: jellyfinService,
                healthChecker: jellyfinService,
                resourceRequestAuthorizer: jellyfinService,
                catalogStructure: .libraryRoot,
                readiness: {
                    jellyfinService.currentSession == nil
                        ? .authenticationRequired
                        : .ready
                }
            )
        )
    }

    private static var deviceName: String {
        switch UIDevice.current.userInterfaceIdiom {
        case .pad:
            "iPad"
        case .tv:
            "Apple TV"
        default:
            "iPhone"
        }
    }
}
