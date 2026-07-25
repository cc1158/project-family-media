import FamilyMediaCore

enum RootTab: Hashable {
    case media
    case settings
}

enum RootSidebarDestination: Hashable {
    case mediaHome
    case familyMedia
    case jellyfin
    case settings

    var title: String {
        switch self {
        case .mediaHome: "媒体首页"
        case .familyMedia: "家庭媒体"
        case .jellyfin: "Jellyfin"
        case .settings: "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .mediaHome: "rectangle.grid.2x2.fill"
        case .familyMedia: "house.fill"
        case .jellyfin: "play.tv.fill"
        case .settings: "gearshape.fill"
        }
    }

    var accessibilityName: String {
        switch self {
        case .mediaHome: "home"
        case .familyMedia: "family"
        case .jellyfin: "jellyfin"
        case .settings: "settings"
        }
    }

    var sourceID: MediaSourceID? {
        switch self {
        case .familyMedia: .familyMedia
        case .jellyfin: .jellyfin
        case .mediaHome, .settings: nil
        }
    }

}

struct RootNavigationState {
    var selectedTab: RootTab = .media
    var selectedSidebarDestination: RootSidebarDestination? = .mediaHome
    var activeMediaSourceID: MediaSourceID?
    private(set) var pendingOnboardingTab: RootTab?

    mutating func prepareOnboardingDestination(openSettings: Bool) {
        pendingOnboardingTab = openSettings ? .settings : .media
    }

    mutating func applyOnboardingDestination() {
        guard let pendingOnboardingTab else { return }
        selectedTab = pendingOnboardingTab
        selectedSidebarDestination = pendingOnboardingTab == .settings
            ? .settings
            : .mediaHome
        activeMediaSourceID = nil
        self.pendingOnboardingTab = nil
    }

    mutating func selectSidebarDestination(
        _ destination: RootSidebarDestination,
        canBrowse: (MediaSourceID) -> Bool
    ) {
        let resolvedDestination: RootSidebarDestination
        if let sourceID = destination.sourceID, !canBrowse(sourceID) {
            resolvedDestination = .settings
        } else {
            resolvedDestination = destination
        }

        selectedSidebarDestination = resolvedDestination
        activeMediaSourceID = resolvedDestination.sourceID
    }

    mutating func resetMediaNavigation(for mode: RootPresentationMode) {
        activeMediaSourceID = nil
        if mode == .iPadSplit, selectedSidebarDestination != .settings {
            selectedSidebarDestination = .mediaHome
        }
    }
}
